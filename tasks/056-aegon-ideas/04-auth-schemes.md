# 04: Basic, API key, and cookie authentication, and role guards

Status: done (2026-10-27), without the optional form and the hook ("What was built").

`rest::bearer` handles one scheme. Aegon's
[auth guide](https://udaykhare09.github.io/Aegon/guide/auth) (read 2026-10-20) has four
extractors, each passing the credential to the program's verifier and storing the
principal it returns for the route:

- Bearer, with a one-line form that takes a JWT verifier (subtask 05)
- A cookie, by name, also with a JWT form
- An API key in a named header
- Basic (RFC 7617), with a realm

Each answers 401 with problem details and the right `WWW-Authenticate` challenge. Each
takes an `on_unauthorized` hook for a custom answer, and an option that lets a request
without credentials through, for optional authentication.

Role guards: `require_role` (one role, or all of several) and `require_any_role`,
answering 403 with the missing role named. Aegon checks at compile time that the
principal has roles. In goose-rest the principal goes in `cx.state`, and a guard is an
inline block around the route that reads a roles field there. It compiles to the same
`if` the best practices show, so it adds no run-time cost.

## What was built (2026-10-27)

`plod::basic`, `plod::api_key`, and `plod::cookie_auth` in `middleware.goose`, beside
`plod::bearer`, over goose-http's `http::basic_auth`, `http::field_of`, and
`http::cookie_of`; `plod::jwt_cookie` in `jwt.goose`, beside `plod::jwt_bearer`.
Basic's 401 carries `WWW-Authenticate: Basic realm="…", charset="UTF-8"`, and
`plod::invalid_credentials` refuses with the same challenge. An API key and a cookie
have no HTTP authentication scheme, so their 401s carry no `WWW-Authenticate`.

The guards are `plod::require_role(cx, roles, role)` and
`plod::require_any_role(cx, roles, wanted)`: statements that fail 403 `forbidden`
with `detail` `role: admin`, or `role: admin or editor`, over any array of strings.
"All of several" is one call per role. A statement compiles to the same `if` as an
inline block around the route, with less to write.

Left out, under `AGENTS.md`'s "Keep changes small":

- The optional form. A route that lets a request through without credentials reads
  them itself with `http::bearer`, `http::basic_auth`, `plod::header`, or
  `plod::cookie`, each of which says whether the request has them.
- `on_unauthorized`. The 401's body is already the program's, through its error
  shape (`docs/reference.md`, "Errors"), and a route that wants another answer reads
  the credential itself, as above.

Tests: `test/middleware/auth_schemes.goose` (each scheme missing, malformed, empty,
valid, and refused, and each guard) and `test/middleware/jwt_bearer.goose`'s cookie
cases.

## Acceptance criteria

- [x] `plod::basic`, `plod::api_key`, and `plod::cookie_auth`, with 401 and the right
      `WWW-Authenticate` for Basic (2026-10-27)
- [ ] ~~An optional form for each that runs the block without a credential, and an
      `on_unauthorized` hook~~: left out (2026-10-27), above
- [x] `plod::require_role` and `plod::require_any_role` over a principal in `cx.state`,
      with 403 naming the missing role (2026-10-27)
- [x] Tests for missing, malformed, and valid credentials, and for each guard
      (2026-10-27)
- [x] The README's middleware list and `docs/reference.md` updated (2026-10-27)
