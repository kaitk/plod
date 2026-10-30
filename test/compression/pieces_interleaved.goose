// Two responses in pieces inside plod::compressed, interleaved: begin A,
// send A, begin B, send B, end B, send A, end A, on one fd, as two HTTP/3
// exchanges have (-1) and two streams of one h2 connection do. Each body is
// its own pieces coded alone, as the exchanges' addresses, which goose-http
// keeps apart, pick their encoders; and every encoder is back after.
import std;
import http from "github.com/kaitk/goose-http@v0.5.16";
import compress from "github.com/kaitk/goose-compress@v0.1.4";
import plod from "../../";
import plod.compression;
import expect from "../";
import common;

// The pieces numbered ns coded alone, each flushed, then the coding's
// trailer: an h2 or HTTP/3 body, which has no chunks.
fn alone(ns: const i64[:]) -> u8[>..] {
    var e = compress::encoder(compress::GZIP, 1);
    var body: u8[>..] = [];
    for n in ns {
        compress::write(e, piece(n), body);
        compress::flush(e, body);
    }
    compress::finish(e, body);
    return body;
}

fn interleaved(fd: i32) {
    let req = http::Request { method: "GET", target: "/x", minor: 1, keep_alive: true, body: 0, chunked: false,
                              expect: false, len: 0, fields: GZIP };
    plod::offered = http::Compression { zstd: false, .. };
    var xa = plod::Exchange { mode: plod::OFFERED, .. };
    var xb = plod::Exchange { mode: plod::OFFERED, .. };
    var bufa: u8[>..] = [];
    var bufb: u8[>..] = [];
    // Keys as goose-http's loops give them: a slot, and a number drawn for each.
    var sa = http::Stream { later: http::MailAddress { key: http::later_base(5) | http::later_draw() }, .. };
    var sb = http::Stream { later: http::MailAddress { key: http::later_base(6) | http::later_draw() }, .. };
    var ka = true;
    var kb = true;
    let outa = http::Reply { buf: bufa, common: "", keep_alive: ka, minor: http::H2_MINOR, head: false, stream: sa, fd: fd };
    let outb = http::Reply { buf: bufb, common: "", keep_alive: kb, minor: http::H2_MINOR, head: false, stream: sb, fd: fd };
    var sta = St { .. };
    var stb = St { .. };
    var calls: u8[>..] = [];
    var app = App { calls: calls };
    var scra: u8[>..] = [];
    var scrb: u8[>..] = [];
    var nr = plod::NoRouter { .. };
    var ca = plod::Cx<St, App, plod::NoRouter> { req: req, body: "", out: outa, state: sta, app: app, scratch: scra,
                                                 kind: http::REQUEST, ex: xa, router: nr };
    var cb = plod::Cx<St, App, plod::NoRouter> { req: req, body: "", out: outb, state: stb, app: app, scratch: scrb,
                                                 kind: http::REQUEST, ex: xb, router: nr };
    plod::begin(ca, 200, "text/plain", -1, Use.None);
    plod::send(ca, piece(1));
    plod::begin(cb, 200, "text/plain", -1, Use.None);
    plod::send(cb, piece(2));
    plod::end(cb);
    plod::send(ca, piece(3));
    plod::end(ca);
    // Each body follows the blank line that ends its head.
    expect::same(bufa[find(bufa, "\r\n\r\n") + 4..], alone([1, 3]));
    expect::same(bufb[find(bufb, "\r\n\r\n") + 4..], alone([2]));
    assert(all_released());
}

fn main() {
    interleaved(-1);
    interleaved(7);
    print("responses in pieces on one fd, interleaved: ok");
}
