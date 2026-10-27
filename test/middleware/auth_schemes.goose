// plod::basic, plod::api_key, and plod::cookie_auth: missing, malformed, and
// valid credentials, and one the block refuses; then plod::require_role and
// plod::require_any_role over a principal's roles.
import std;
import http from "github.com/kaitk/goose-http@v0.5.13";
import plod from "../../";
import expect from "../";
import common;

fn with_basic(fields: const u8[:]) -> u8[>..] {
    return answer(expect::request("GET", "/", fields)) { cx =>
        plod::route(cx) {
            plod::basic(cx, "api") { user, password =>
                guard user == "ada" && password == "pass:word" else { plod::invalid_credentials(cx, "api"); }
                plod::text(cx, 200, "ok");
            };
        };
    };
}

fn with_key(fields: const u8[:]) -> u8[>..] {
    return answer(expect::request("GET", "/", fields)) { cx =>
        plod::route(cx) {
            plod::api_key(cx, "X-API-Key") { key =>
                guard key == "k3y" else { plod::fail(cx, 401, "invalid_key"); }
                plod::text(cx, 200, "ok");
            };
        };
    };
}

fn with_cookie(fields: const u8[:]) -> u8[>..] {
    return answer(expect::request("GET", "/", fields)) { cx =>
        plod::route(cx) {
            plod::cookie_auth(cx, "sid") { sid =>
                guard sid == "s1" else { plod::fail(cx, 401, "invalid_session"); }
                plod::text(cx, 200, "ok");
            };
        };
    };
}

fn with_roles(roles: const u8[:][:], all: bool) -> u8[>..] {
    return answer(expect::request("GET", "/", "")) { cx =>
        plod::route(cx) {
            if all {
                plod::require_role(cx, roles, "admin");
                plod::require_role(cx, roles, "billing");
            } else {
                plod::require_any_role(cx, roles, ["admin", "editor"]);
            }
            plod::text(cx, 200, "ok");
        };
    };
}

fn unauthorized(challenge: const u8[:], body: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    out.append("HTTP/1.1 401 Unauthorized\r\n");
    if challenge.len > 0 { format(out, "WWW-Authenticate: ", challenge, "\r\n"); }
    format(out, "Content-Type: application/json\r\nContent-Length: ", body.len, "\r\n\r\n", body);
    return out;
}

fn forbidden(body: const u8[:]) -> u8[>..] {
    return str("HTTP/1.1 403 Forbidden\r\nContent-Type: application/json\r\nContent-Length: ", body.len,
               "\r\n\r\n", body);
}

fn main() {
    let ok = str("HTTP/1.1 200 OK\r\n", OK);
    let challenge = "Basic realm=\"api\", charset=\"UTF-8\"";
    let none = unauthorized(challenge, "{\"error\":\"unauthenticated\"}");
    // "ada:pass:word": the password keeps its colon.
    expect::same(with_basic("Authorization: Basic YWRhOnBhc3M6d29yZA==\r\n"), ok, "basic");
    expect::same(with_basic("Authorization: basic YWRhOnBhc3M6d29yZA==\r\n"), ok, "basic, any case");
    expect::same(with_basic(""), none, "basic, none");
    expect::same(with_basic("Authorization: Bearer t0k\r\n"), none, "basic, another scheme");
    expect::same(with_basic("Authorization: Basic !!!\r\n"), none, "basic, not base64");
    expect::same(with_basic("Authorization: Basic YWRh\r\n"), none, "basic, no colon");
    expect::same(with_basic("Authorization: Basic YWRhOm5vcGU=\r\n"),
                 unauthorized(challenge, "{\"error\":\"invalid_credentials\"}"), "basic, refused");

    let anonymous = unauthorized("", "{\"error\":\"unauthenticated\"}");
    expect::same(with_key("X-API-Key: k3y\r\n"), ok, "api key");
    expect::same(with_key("x-api-key: k3y\r\n"), ok, "api key, any case");
    expect::same(with_key(""), anonymous, "api key, none");
    expect::same(with_key("X-API-Key: \r\n"), anonymous, "api key, empty");
    expect::same(with_key("X-API-Key: nope\r\n"), unauthorized("", "{\"error\":\"invalid_key\"}"), "api key, refused");

    expect::same(with_cookie("Cookie: theme=dark; sid=s1\r\n"), ok, "cookie");
    expect::same(with_cookie("Cookie: theme=dark\r\n"), anonymous, "cookie, none");
    expect::same(with_cookie("Cookie: sid=\r\n"), anonymous, "cookie, empty");
    expect::same(with_cookie("Cookie: sid=s2\r\n"), unauthorized("", "{\"error\":\"invalid_session\"}"),
                 "cookie, refused");

    expect::same(with_roles(["billing", "admin"], true), ok, "roles, all held");
    expect::same(with_roles(["admin"], true), forbidden("{\"error\":\"forbidden\",\"detail\":\"role: billing\"}"),
                 "roles, one missing");
    expect::same(with_roles([], true), forbidden("{\"error\":\"forbidden\",\"detail\":\"role: admin\"}"),
                 "roles, none");
    expect::same(with_roles(["editor"], false), ok, "any role, one held");
    expect::same(with_roles(["viewer"], false),
                 forbidden("{\"error\":\"forbidden\",\"detail\":\"role: admin or editor\"}"), "any role, none held");
    print("plod::basic, api_key, cookie_auth, require_role, require_any_role: ok");
}
