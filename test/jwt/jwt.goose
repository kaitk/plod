// plod::jwt_verify and plod::jwt_sign: RFC 7515's HS256 example (A.1, also
// RFC 7519 §3.1), tokens signed here and checked against Python's hmac, and
// each refusal: malformed text, the algorithm, the key, the signature, the
// dates and their leeway, the issuer, and the audience.
import std;
import json;
import http from "github.com/kaitk/goose-http@v0.5.13";
import hash from "github.com/kaitk/goose-hash@v0.0.4";
import plod from "../../";
import plod.jwt;

fn name(e: plod::JwtError) -> const u8[:] {
    match e {
        None => "ok",
        Malformed => "malformed",
        Algorithm => "algorithm",
        KeyNotFound => "key not found",
        Signature => "signature",
        Expired => "expired",
        NotYetValid => "not yet valid",
        Issuer => "issuer",
        Audience => "audience",
    }
}

// A token of the given header and payload JSON, signed with secret.
fn token(head: const u8[:], body: const u8[:], secret: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    plod::base64url_encode(out, head);
    out.push('.');
    plod::base64url_encode(out, body);
    let mac = hash::hmac_sha256(secret, out);
    out.push('.');
    plod::base64url_encode(out, mac);
    return out;
}

fn verdict(tok: const u8[:], keys: const plod::JwtKey[:], check: plod::JwtCheck) -> const u8[:] {
    return name(plod::jwt_verify(tok, keys, check) { t => });
}

fn show(what: const u8[:], tok: const u8[:], keys: const plod::JwtKey[:], check: plod::JwtCheck) {
    print(what, ": ", verdict(tok, keys, check));
}

fn same_token(what: const u8[:], got: const u8[:], want: const u8[:]) {
    if got == want { print(what, ": as Python signs it"); } else { print(what, ": got ", got); }
}

let HS = "{\"alg\":\"HS256\"}";

fn main() {
    // RFC 7515 A.1.
    let rfc = "eyJ0eXAiOiJKV1QiLA0KICJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    var k: u8[>..] = [];
    let secret, decoded = plod::base64url_decode(k, "AyM1SysPpbyDfgZld3umj1qzKObwVMkoqQ-EstJQLr_T-1qS0gZH75aKtMN3Yj0iPS4hcgUuTwjAzZr1Z9CAow");
    assert(decoded);
    let rfc_keys = [plod::JwtKey { secret: secret }];
    plod::jwt_verify(rfc, rfc_keys, plod::JwtCheck { now: 1300819300 }) { t =>
        var r = json::reader(t.payload);
        var root = false;
        json::each_member(r) { key =>
            if key == "http://example.com/is_root" { root = json::read_bool(r); } else { json::skip(r); }
        };
        print("rfc 7515 A.1: iss ", t.iss, ", exp ", t.exp, ", is_root ", root);
    };
    show("rfc 7515 A.1, at exp + leeway - 1", rfc, rfc_keys, plod::JwtCheck { now: 1300819380 + 59 });
    show("rfc 7515 A.1, at exp + leeway", rfc, rfc_keys, plod::JwtCheck { now: 1300819380 + 60 });
    show("rfc 7515 A.1, no leeway, at exp", rfc, rfc_keys, plod::JwtCheck { leeway: 0, now: 1300819380 });
    show("rfc 7515 A.1, another secret", rfc, [plod::JwtKey { secret: "secret" }], plod::JwtCheck { now: 1 });

    // Signing, against Python's hmac over the same header and payload.
    let k1 = plod::JwtKey { kid: "k1", secret: "secret" };
    let k2 = plod::JwtKey { kid: "k2", secret: "other" };
    let both = [k1, k2];
    var signed: u8[>..] = [];
    plod::jwt_sign(signed, k1, plod::Jwt { iss: "plod", sub: "ada", aud: "api", jti: "j1", iat: 1000, .. }, 60) { p =>
        json::format_key(p, "role");
        json::format_string(p, "admin");
    };
    same_token("signed, kid, ttl, own claim", signed,
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImsxIn0.eyJpYXQiOjEwMDAsIm5iZiI6MTAwMCwiZXhwIjoxMDYwLCJpc3MiOiJwbG9kIiwic3ViIjoiYWRhIiwiYXVkIjoiYXBpIiwianRpIjoiajEiLCJyb2xlIjoiYWRtaW4ifQ.A4fcatFyaWrHquCzSKNz9exCIggi1vfPFlKcDVKlYg4");
    var bare: u8[>..] = [];
    plod::jwt_sign(bare, plod::JwtKey { secret: "secret" }, plod::Jwt { jti: "j2", iat: 1000, .. }) { p => };
    same_token("signed, no kid, no claims of its own", bare,
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjEwMDAsIm5iZiI6MTAwMCwianRpIjoiajIifQ.8EXxi1Liuc99CZLL0TwS9n57Fen1osJFjpXD85F2n0o");
    plod::jwt_verify(signed, both, plod::JwtCheck { issuer: "plod", audience: "api", now: 1030 }) { t =>
        print("signed, verified: sub ", t.sub, ", aud ", t.aud, ", jti ", t.jti,
              ", iat ", t.iat, ", nbf ", t.nbf, ", exp ", t.exp);
    };
    {
        // The clock and a random jti, where the claims leave them out.
        var now: u8[>..] = [];
        plod::jwt_sign(now, k1, plod::Jwt { .. }, 300) { p => };
        let err = plod::jwt_verify(now, both) { t =>
            let fresh = t.iat > 1700000000 && t.nbf == t.iat && t.exp == t.iat + 300;
            print("signed now: dated ", fresh, ", jti of ", t.jti.len, " characters");
        };
        print("signed now: ", name(err));
    }

    // The key: kid names one of several; without kid, only one key will do.
    let k3 = plod::JwtKey { kid: "k3", secret: "secret" };
    show("kid k1 among k1, k2", signed, both, plod::JwtCheck { now: 1030 });
    show("kid k1 among k2", signed, [k2], plod::JwtCheck { now: 1030 });
    show("kid k1 against k3, same secret", signed, [k3], plod::JwtCheck { now: 1030 });
    show("no kid, one key", bare, [k1], plod::JwtCheck { now: 1030 });
    show("no kid, two keys", bare, both, plod::JwtCheck { now: 1030 });
    show("no kid, no keys", bare, [], plod::JwtCheck { now: 1030 });

    // The algorithm is the verifier's.
    show("alg none, no signature", "eyJhbGciOiJub25lIn0.eyJzdWIiOiJhZGEifQ.", [k1], plod::JwtCheck { now: 1 });
    show("alg HS512", token("{\"alg\":\"HS512\"}", "{}", "secret"), [k1], plod::JwtCheck { now: 1 });
    show("alg absent", token("{\"typ\":\"JWT\"}", "{}", "secret"), [k1], plod::JwtCheck { now: 1 });
    show("crit", token("{\"alg\":\"HS256\",\"crit\":[\"b64\"],\"b64\":false}", "{}", "secret"), [k1],
         plod::JwtCheck { now: 1 });

    // The signature, over the header and payload as sent.
    let good = token(HS, "{\"sub\":\"ada\"}", "secret");
    show("HS256, no claims to check", good, [k1], plod::JwtCheck { now: 1 });
    var flipped = copy(good);
    flipped[flipped.len - 2] = if flipped[flipped.len - 2] == 'A' { 'B' } else { 'A' };
    show("a signature's byte changed", flipped, [k1], plod::JwtCheck { now: 1 });
    var swapped: u8[>..] = [];
    swapped.append(good[..find(good, ".") + 1]);
    plod::base64url_encode(swapped, "{\"sub\":\"eve\"}");
    swapped.append(good[find(good[find(good, ".") + 1..], ".") + find(good, ".") + 1..]);
    show("another payload, the same signature", swapped, [k1], plod::JwtCheck { now: 1 });
    show("signature cut short", good[..good.len - 3], [k1], plod::JwtCheck { now: 1 });

    // Malformed text.
    show("empty", "", [k1], plod::JwtCheck { now: 1 });
    show("one part", "abc", [k1], plod::JwtCheck { now: 1 });
    show("two parts", "abc.def", [k1], plod::JwtCheck { now: 1 });
    show("four parts", str(good, ".x"), [k1], plod::JwtCheck { now: 1 });
    show("padding", str(good, "="), [k1], plod::JwtCheck { now: 1 });
    show("standard alphabet", str(good[..5], "+", good[6..]), [k1], plod::JwtCheck { now: 1 });
    show("header not JSON", token("{alg", "{}", "secret"), [k1], plod::JwtCheck { now: 1 });
    show("payload an array", token(HS, "[1]", "secret"), [k1], plod::JwtCheck { now: 1 });
    show("payload not JSON", token(HS, "{\"sub\":", "secret"), [k1], plod::JwtCheck { now: 1 });
    show("exp a string", token(HS, "{\"exp\":\"soon\"}", "secret"), [k1], plod::JwtCheck { now: 1 });
    show("exp negative", token(HS, "{\"exp\":-5}", "secret"), [k1], plod::JwtCheck { now: 1 });

    // Dates: a fraction of a second, and nbf with its leeway.
    let fraction = token(HS, "{\"exp\":1000.9}", "secret");
    show("exp 1000.9, no leeway, at 999", fraction, [k1], plod::JwtCheck { leeway: 0, now: 999 });
    show("exp 1000.9, no leeway, at 1000", fraction, [k1], plod::JwtCheck { leeway: 0, now: 1000 });
    let later = token(HS, "{\"nbf\":2000}", "secret");
    show("nbf 2000, at nbf - leeway - 1", later, [k1], plod::JwtCheck { now: 2000 - 61 });
    show("nbf 2000, at nbf - leeway", later, [k1], plod::JwtCheck { now: 2000 - 60 });

    // Issuer and audience.
    let aud = token(HS, "{\"iss\":\"plod\",\"aud\":[\"web\",\"api\"]}", "secret");
    show("iss plod, wanted plod", aud, [k1], plod::JwtCheck { issuer: "plod", now: 1 });
    show("iss plod, wanted other", aud, [k1], plod::JwtCheck { issuer: "other", now: 1 });
    show("no iss, wanted plod", good, [k1], plod::JwtCheck { issuer: "plod", now: 1 });
    show("aud [web, api], wanted api", aud, [k1], plod::JwtCheck { audience: "api", now: 1 });
    show("aud [web, api], wanted cli", aud, [k1], plod::JwtCheck { audience: "cli", now: 1 });
    show("no aud, wanted api", good, [k1], plod::JwtCheck { audience: "api", now: 1 });
    show("aud a number", token(HS, "{\"aud\":7}", "secret"), [k1], plod::JwtCheck { now: 1 });
}
