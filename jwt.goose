// plod::jwt_verify, plod::jwt_sign, and plod::jwt_bearer: JSON Web Tokens
// (RFC 7519) signed with HS256 (RFC 7515, RFC 7518 §3.2). Only a program
// that imports this module needs goose-hash, for HMAC-SHA-256, which its
// root file declares at the tag below:
//
//   import http from "github.com/kaitk/goose-http@v0.5.13";
//   import hash from "github.com/kaitk/goose-hash@v0.0.4";
//   import plod from "github.com/kaitk/plod@<tag>";
//   import plod.jwt;
namespace plod;

import std;
import json;
import hash from "github.com/kaitk/goose-hash@v0.0.4";

// A key to sign and verify with: its secret, and the name a token's header
// gives it in "kid".
struct JwtKey { kid: const u8[:] = "", secret: const u8[:] }

// What jwt_verify checks besides the signature. exp and nbf allow leeway
// seconds of clock skew. issuer and audience, when set, must be the token's
// iss and one of its aud. now, when not 0, stands for the clock, in seconds
// since the epoch.
struct JwtCheck { issuer: const u8[:] = "", audience: const u8[:] = "", leeway: i64 = 60, now: i64 = 0 }

// A token's registered claims (RFC 7519 §4.1), "" or -1 where it has none.
// aud is the audience jwt_verify matched, or the token's aud when that is
// one string. payload is the payload's JSON, from which the program reads
// its own claims with json::reader.
struct Jwt {
    iss: const u8[:] = "", sub: const u8[:] = "", aud: const u8[:] = "", jti: const u8[:] = "",
    exp: i64 = -1, nbf: i64 = -1, iat: i64 = -1, payload: const u8[:] = "",
}

enum JwtError { None, Malformed, Algorithm, KeyNotFound, Signature, Expired, NotYetValid, Issuer, Audience }

// Runs F(t) with token's claims, and returns JwtError.None, when token is a
// compact JWS whose header says HS256, whose MAC is the one its key gives,
// and whose claims pass check; otherwise returns why not, without running
// F. The claims' strings are slices of a buffer that lasts as long as F.
// The algorithm is HS256 whatever the header says: any other alg, "none"
// among them, is JwtError.Algorithm. The key is the one the header's kid
// names; a token without kid takes the only key, and is refused when there
// are several. A header with crit, whose extensions this doesn't know, is
// malformed (RFC 7515 §4.1.11).
fn jwt_verify<F>(token: const u8[:], keys: const JwtKey[:], check: JwtCheck = JwtCheck { .. }) -> JwtError {
    let dot = find(token, ".");
    guard dot >= 0 else { return JwtError.Malformed; }
    let rest = token[dot + 1..];
    let dot2 = find(rest, ".");
    guard dot2 >= 0 else { return JwtError.Malformed; }
    var buf: u8[>..] = [];
    let header, header_ok = base64url_decode(buf, token[..dot]);
    let payload, payload_ok = base64url_decode(buf, rest[..dot2]);
    let mac, mac_ok = base64url_decode(buf, rest[dot2 + 1..]);
    guard header_ok && payload_ok && mac_ok else { return JwtError.Malformed; }

    var r = json::reader(header);
    var alg = nothing(r);
    var kid = nothing(r);
    var named = false;
    var crit = false;
    json::each_member(r) { key =>
        if key == "alg" { alg = json::read_string(r, buf); }
        else if key == "kid" { kid = json::read_string(r, buf); named = true; }
        else { crit = crit || key == "crit"; json::skip(r); }
    };
    guard json::finish(r) && !crit else { return JwtError.Malformed; }
    guard alg == "HS256" else { return JwtError.Algorithm; }

    var at = -1;
    if named {
        for k, i in keys { if at < 0 && k.kid == kid { at = i; } }
    } else if keys.len == 1 {
        at = 0;
    }
    guard at >= 0 else { return JwtError.KeyNotFound; }
    guard hash::equal(hash::hmac_sha256(keys[at].secret, token[..dot + 1 + dot2]), mac) else {
        return JwtError.Signature;
    }

    var p = json::reader(payload);
    let none = nothing(p);
    var t = Jwt { iss: none, sub: none, aud: none, jti: none, payload: p.text };
    var dated = true;
    var heard = check.audience.len == 0;
    json::each_member(p) { key =>
        if key == "iss" { t.iss = json::read_string(p, buf); }
        else if key == "sub" { t.sub = json::read_string(p, buf); }
        else if key == "jti" { t.jti = json::read_string(p, buf); }
        else if key == "exp" { let d, ok = numeric_date(p); t.exp = d; dated = dated && ok; }
        else if key == "nbf" { let d, ok = numeric_date(p); t.nbf = d; dated = dated && ok; }
        else if key == "iat" { let d, ok = numeric_date(p); t.iat = d; dated = dated && ok; }
        else if key == "aud" && json::peek(p) == '[' {
            json::each_element(p) {
                let a = json::read_string(p, buf);
                if !heard && a == check.audience { t.aud = a; heard = true; }
            };
        } else if key == "aud" {
            t.aud = json::read_string(p, buf);
            heard = heard || t.aud == check.audience;
        } else { json::skip(p); }
    };
    guard json::finish(p) && dated else { return JwtError.Malformed; }

    let now = if check.now != 0 { check.now } else { time_ns() / 1000000000 };
    guard t.exp < 0 || now < t.exp + check.leeway else { return JwtError.Expired; }
    guard t.nbf < 0 || now + check.leeway >= t.nbf else { return JwtError.NotYetValid; }
    guard check.issuer.len == 0 || t.iss == check.issuer else { return JwtError.Issuer; }
    guard heard else { return JwtError.Audience; }
    F(t);
    return JwtError.None;
}

// An empty slice rooted at r, for a variable that json::read_string(r, ...)
// assigns later: r.text[..0] would be rooted at the text's buffer, and the
// checker refuses to rebind a variable to a slice of another root.
fn nothing(r: json::Reader&) -> const u8[:] { return r.text[..0]; }

// A NumericDate (RFC 7519 §2) at the reader, in whole seconds, and whether
// it was one from the epoch on that an i64 holds.
fn numeric_date(r: json::Reader&) -> i64, bool {
    let v = json::read_number(r);
    guard v >= 0.0 && v < 1e15 else { return -1, false; }
    return v as! i64, true;
}

// Appends a token signed with key, whose header names key.kid when it has
// one. Its payload holds c's registered claims, with iat the clock, nbf
// iat, and jti 16 random bytes where c has none, and exp iat + ttl where c
// has none and ttl is positive; c.payload is ignored. F(p) appends the
// program's own members to p, separated by commas, with json::format_key
// and json's writer, and appends nothing if it has none.
fn jwt_sign<F>(out: u8[>..]&, key: JwtKey, c: Jwt, ttl: i64 = 0) {
    var head: u8[>..] = [];
    head.append("{\"alg\":\"HS256\",\"typ\":\"JWT\"");
    if key.kid.len > 0 {
        head.push(',');
        json::format_key(head, "kid");
        json::format_string(head, key.kid);
    }
    head.push('}');

    let iat = if c.iat >= 0 { c.iat } else { time_ns() / 1000000000 };
    let exp = if c.exp >= 0 { c.exp } else if ttl > 0 { iat + ttl } else { -1 };
    var body: u8[>..] = [];
    body.push('{');
    json::format_key(body, "iat");
    json::format_int(body, iat);
    body.push(',');
    json::format_key(body, "nbf");
    json::format_int(body, if c.nbf >= 0 { c.nbf } else { iat });
    if exp >= 0 {
        body.push(',');
        json::format_key(body, "exp");
        json::format_int(body, exp);
    }
    claim(body, "iss", c.iss);
    claim(body, "sub", c.sub);
    claim(body, "aud", c.aud);
    body.append(",\"jti\":");
    if c.jti.len > 0 {
        json::format_string(body, c.jti);
    } else {
        var id: u8[16] = [0; 16];
        hash::random_bytes(id);
        body.push('"');
        base64url_encode(body, id);
        body.push('"');
    }
    var own: u8[>..] = [];
    F(&own);
    if own.len > 0 {
        body.push(',');
        body.append(own);
    }
    body.push('}');

    let start = out.len;
    base64url_encode(out, head);
    out.push('.');
    base64url_encode(out, body);
    let mac = hash::hmac_sha256(key.secret, out[start..]);
    out.push('.');
    base64url_encode(out, mac);
}

// ,"name":"value", where value isn't empty.
fn claim(out: u8[>..]&, name: const u8[:], value: const u8[:]) {
    guard value.len > 0;
    out.push(',');
    json::format_key(out, name);
    json::format_string(out, value);
}

// Runs F(t) with the request's bearer token verified by jwt_verify, t its
// claims. A request without a bearer token fails as plod::bearer does, and
// one jwt_verify refuses with 401 invalid_token. Checks of the program's
// own, such as a jti it has revoked, call plod::invalid_token(cx) in F. It
// goes inside plod::route, as bearer does.
inline fn jwt_bearer<F>(cx, keys: const JwtKey[:], check: JwtCheck = JwtCheck { .. }) {
    bearer(cx) { token =>
        let err = jwt_verify(token, keys, check) { t => F(t); };
        guard err == JwtError.None else { invalid_token(cx); }
    };
}

// The bytes of s, base64url without padding (RFC 7515 §2), appended to out,
// and whether s was that. As std's base64 does, it ignores the bits left
// over in the last character.
fn base64url_decode(out: u8[>..]&, s: const u8[:]) -> const u8[:], bool {
    guard s.len % 4 != 1 else { return "", false; }
    let start = out.len;
    var v: u32 = 0;
    var bits: u32 = 0;
    for c in s {
        let d = base64url_value(c);
        guard d < 64 else { return "", false; }
        v = v << 6 | d;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((v >> bits & 255) as! u8);
        }
    }
    return out[start..], true;
}

// The 6-bit value of a base64url character, 64 for any other byte.
fn base64url_value(c: u8) -> u32 {
    if c - 'A' < 26 { return c - 'A'; }
    if c - 'a' < 26 { return c - 'a' + 26; }
    if c - '0' < 10 { return c - '0' + 52; }
    if c == '-' { return 62; }
    if c == '_' { return 63; }
    return 64;
}

let BASE64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

// Appends s in base64url without padding.
fn base64url_encode(out: u8[>..]&, s: const u8[:]) {
    var i = 0;
    while i < s.len {
        let n = min(s.len - i, 3);
        var v: u32 = 0;
        for j in 3 {
            v = v << 8;
            if j < n { v |= s[i + j]; }
        }
        for j in n + 1 {
            let shift = (18 - 6 * j) as! u32;
            out.push(BASE64URL[(v >> shift & 63) as i64]);
        }
        i += 3;
    }
}
