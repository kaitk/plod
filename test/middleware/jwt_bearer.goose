// plod::jwt_bearer: a valid token's subject, no token, an expired one, one
// signed with another secret, and one the route refuses itself, by its jti;
// then plod::jwt_cookie: a valid cookie, an expired one, and none.
import std;
import http from "github.com/kaitk/goose-http@v0.5.13";
import hash from "github.com/kaitk/goose-hash@v0.0.4";
import plod from "../../";
import plod.jwt;
import expect from "../";
import common;

let KEYS = [plod::JwtKey { secret: "secret" }];

fn with_jwt(fields: const u8[:]) -> u8[>..] {
    return answer(expect::request("GET", "/", fields)) { cx =>
        plod::route(cx) {
            plod::jwt_bearer(cx, KEYS, plod::JwtCheck { issuer: "plod", now: 1030 }) { t =>
                guard t.jti != "revoked" else { plod::invalid_token(cx); }
                plod::text(cx, 200, t.sub);
            };
        };
    };
}

fn with_jwt_cookie(fields: const u8[:]) -> u8[>..] {
    return answer(expect::request("GET", "/", fields)) { cx =>
        plod::route(cx) {
            plod::jwt_cookie(cx, "token", KEYS, plod::JwtCheck { issuer: "plod", now: 1030 }) { t =>
                plod::text(cx, 200, t.sub);
            };
        };
    };
}

fn signed(c: plod::Jwt, secret: const u8[:] = "secret", field: const u8[:] = "Authorization: Bearer ") -> u8[>..] {
    var out: u8[>..] = [];
    out.append(field);
    plod::jwt_sign(out, plod::JwtKey { secret: secret }, c, 60) { p => };
    out.append("\r\n");
    return out;
}

fn main() {
    let ok = with_jwt(signed(plod::Jwt { iss: "plod", sub: "ok", jti: "j1", iat: 1000, .. }));
    expect::same(expect::status_of(ok), "HTTP/1.1 200 OK");
    expect::same(expect::body_of(ok), "ok");
    let refused = str("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Bearer error=\"invalid_token\"\r\n",
                      "Content-Type: application/json\r\nContent-Length: 25\r\n\r\n{\"error\":\"invalid_token\"}");
    expect::same(with_jwt(signed(plod::Jwt { iss: "plod", jti: "j1", iat: 900, .. })), refused, "expired");
    expect::same(with_jwt(signed(plod::Jwt { iss: "plod", jti: "j1", iat: 1000, .. }, "other")), refused, "secret");
    expect::same(with_jwt(signed(plod::Jwt { iss: "else", jti: "j1", iat: 1000, .. })), refused, "issuer");
    expect::same(with_jwt(signed(plod::Jwt { iss: "plod", jti: "revoked", iat: 1000, .. })), refused, "revoked");
    expect::same(expect::status_of(with_jwt("")), "HTTP/1.1 401 Unauthorized");

    let baked = with_jwt_cookie(signed(plod::Jwt { iss: "plod", sub: "ok", jti: "j1", iat: 1000, .. }, "secret",
                                       "Cookie: theme=dark; token="));
    expect::same(expect::status_of(baked), "HTTP/1.1 200 OK", "cookie");
    expect::same(expect::body_of(baked), "ok", "cookie");
    expect::same(with_jwt_cookie(signed(plod::Jwt { iss: "plod", jti: "j1", iat: 900, .. }, "secret", "Cookie: token=")),
                 str("HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: 25\r\n\r\n",
                     "{\"error\":\"invalid_token\"}"), "cookie, expired");
    expect::same(with_jwt_cookie("Cookie: theme=dark\r\n"),
                 str("HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: 27\r\n\r\n",
                     "{\"error\":\"unauthenticated\"}"), "cookie, none");
    print("plod::jwt_bearer, jwt_cookie: ok");
}
