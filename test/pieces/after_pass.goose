// plod::after_pass: the route gets the WAKE, in its case function, and owns
// its waits from there: the TIMEOUT when the wake couldn't be queued, and the
// CLOSED of a client that goes. serve_one gives the WAKE from its wakes.
import std;
import http from "github.com/kaitk/goose-http@v0.5.20";
import plod from "../../";
import expect from "../";

enum Use { None, Written }

struct St { use: Use = Use.None }

// What the case function saw, in order: W, T, C.
struct App { log: u8[>..]& }

fn resume(u: Use.None, cx) { plod::fail(cx, 500, "not_waiting"); }

fn resume(u: Use.Written, cx) {
    if cx.kind == http::WAKE {
        cx.app.log.append("W ");
        plod::text(cx, 201, "committed");
    } else if cx.kind == http::TIMEOUT {
        cx.app.log.append("T ");
        plod::text(cx, 201, "committed late");
    } else if cx.kind == http::CLOSED {
        cx.app.log.append("C ");
        plod::text(cx, 201, "nowhere");
    }
}

fn handle(cx) {
    if plod::resumed(cx) {
        plod::on_reply(cx) { resume(cx.state.use, cx); };
        return;
    }
    plod::routes(cx) { cx =>
        plod::post(cx, "/posts") { plod::after_pass(cx, Use.Written); };
    };
}

fn main() {
    var log: u8[>..] = [];
    var app = App { log: log };
    fn req(wakes: const plod::Wake[:]) -> u8[>..] {
        return plod::serve_one(expect::request("POST", "/posts"), app, St { .. }, wakes) { cx => handle(cx); };
    }

    let woke = req([plod::Wake { .. }]);
    expect::same(expect::status_of(woke), "HTTP/1.1 201 Created", "woke status");
    expect::same(expect::body_of(woke), "committed", "woke body");
    expect::same(log, "W ", "woke's calls");

    // A wake that couldn't be queued: the TIMEOUT goes to the route.
    log.clear();
    let late = req([plod::Wake { timeout: true }]);
    expect::same(expect::body_of(late), "committed late", "timeout body");
    expect::same(log, "T ", "timeout's calls");

    // A client that goes before the pass ends: CLOSED, whose answer goes
    // nowhere, and serve_one's 500 for a route that never answered.
    log.clear();
    let gone = req([]);
    expect::same(expect::status_of(gone), "HTTP/1.1 500 Internal Server Error", "closed status");
    assert(find(gone, "nowhere") < 0);
    expect::same(log, "C ", "closed's calls");

    // And not_served outside serve and serve_one.
    let parsed, status = http::parse("POST /posts HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n");
    assert(status == 200);
    var buf: u8[>..] = [];
    var keep = true;
    var stream = http::Stream { .. };
    var st = St { .. };
    var scratch: u8[>..] = [];
    var none = plod::NoRouter { .. };
    var cx = plod::Cx<St, App, plod::NoRouter> {
        req: parsed, body: "", out: http::Reply { buf: buf, common: "", keep_alive: keep, minor: 1, head: false, stream: stream },
        state: st, app: app, scratch: scratch, router: none,
    };
    plod::route(cx) { plod::after_pass(cx, Use.Written); };
    expect::same(expect::body_of(buf), "{\"error\":\"not_served\"}", "not served");
    print("plod::after_pass: ok");
}
