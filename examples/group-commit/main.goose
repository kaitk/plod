// Group commit with plod::after_pass: each POST /notes writes its note into
// the open transaction, beginning one if none is open, and waits for the end
// of the worker's pass. The first WAKE of the pass commits every note written
// in it with one append to the journal, and each note is answered 201 only
// after its commit, or 500 if the commit failed. A database's BEGIN and
// COMMIT go where begin and settle are below; the open transaction and its
// generation live in App, the worker's own.
//
//   goose build -o build/examples/group-commit examples/group-commit/main.goose
//   JOURNAL=build/notes.txt build/examples/group-commit 8080
//   curl -s -d 'first note' localhost:8080/notes
import std;
import os;
import http from "github.com/kaitk/goose-http@v0.5.20";
import plod from "../../";

enum Use { None, Written }

// The request's note, and the transaction it went into.
struct St { use: Use = Use.None, id: i64 = 0, gen: i64 = 0 }

// The worker's journal and its open transaction: the notes written since it
// began, and its generation. failed is the last generation whose commit
// failed.
struct App {
    journal: u8[..1024] = "",
    pending: u8[..65536] = "",
    open: bool = false,
    gen: i64 = 0,
    failed: i64 = -1,
    notes: i64 = 0,
    commits: i64 = 0,
}

fn handle(cx) {
    plod::routes(cx) { cx =>
        plod::get(cx, "/health") { plod::text(cx, 200, "ok"); };
        plod::post(cx, "/notes") {
            let text = plod::body(cx, 1024);
            guard text.len > 0 && find(text, "\n") < 0 else { plod::fail(cx, 422, "one_line"); }
            // A note that won't fit commits the open transaction first.
            if cx.app.pending.len + text.len + 1 > cx.app.pending.cap { settle(cx.app, cx.app.gen); }
            begin(cx.app);
            cx.app.pending.append(text);
            cx.app.pending.append("\n");
            cx.app.notes++;
            cx.state.gen = cx.app.gen;
            cx.state.id = cx.app.notes;
            plod::after_pass(cx, Use.Written);
        };
        plod::get(cx, "/notes") {
            var text: u8[>..] = [];
            read_file(cx.app.journal, text);
            plod::text(cx, 200, text);
        };
        plod::get(cx, "/stats") {
            plod::json_bytes(cx, 200, str("{\"notes\":", cx.app.notes, ",\"commits\":", cx.app.commits, "}"));
        };
    };
}

// BEGIN, unless a transaction is open already.
fn begin(app: App&) {
    guard !app.open else { return; }
    app.open = true;
    app.gen++;
}

// COMMIT gen's transaction, if it's still open: the first call of the pass
// commits, and the rest find it done.
fn settle(app: App&, gen: i64) {
    guard app.open && app.gen == gen else { return; }
    app.open = false;
    app.commits++;
    if !append_file(app.journal, app.pending) { app.failed = gen; }
    app.pending.clear();
}

fn resume(u: Use.None, cx) { plod::fail(cx, 500, "not_waiting"); }

// Every event settles the note's transaction: a client that goes, or a
// TIMEOUT, must not leave it open.
fn resume(u: Use.Written, cx) {
    settle(cx.app, cx.state.gen);
    guard cx.kind != http::CLOSED else { return; }
    guard cx.app.failed != cx.state.gen else { plod::fail(cx, 500, "not_committed"); }
    plod::json_bytes(cx, 201, str("{\"id\":", cx.state.id, "}"));
}

thread_fn worker(cfg: http::Config, journal: u8[..1024]) {
    var app = App { journal: journal };
    let e = plod::serve(cfg, app, St { .. }) { cx =>
        if plod::resumed(cx) {
            plod::on_reply(cx) { resume(cx.state.use, cx); };
        } else {
            handle(cx);
        }
    };
    if e.code != 0 { http::report(e); }
}

fn main() {
    let a = args();
    var port: i64 = 8080;
    if a.len > 1 {
        let p, ok = parse_int(a[1]);
        if ok { port = p; }
    }
    var path: u8[>..] = [];
    if !env("JOURNAL", path) { path.append("notes.txt"); }
    guard path.len <= 1024 else { write_stderr("JOURNAL is too long\n"); exit(2); }
    var journal: u8[..1024] = "";
    journal.append(path);
    http::exit_on_error(http::stop_on_signals());
    // after_pass waits as http::later does, so the loop needs a box.
    let cfg = http::Config { port: port as i32, workers: 1, mail_slots: 64, max_waiting: 1024, .. };
    http::run(cfg, journal, worker);
}
