# 05: JWT signing and verification

Status: in progress (2026-10-27). HS256 is built: `plod.jwt`, a module over goose-hash,
with `plod::jwt_bearer`, `jwt_verify`, and `jwt_sign` (`docs/reference.md`, "JWT").
JWKS and RS256 and ES256 are left ("What was built", below). Task 035's full example
waited on HS256 alone.

Aegon's [JWT guide](https://udaykhare09.github.io/Aegon/guide/jwt) (read 2026-10-20)
makes a checklist.

Verification:

- The algorithm is pinned by the verifier, never taken from the token's header.
- HMAC is compared in constant time.
- `exp` and `nbf` are checked with a leeway, and `iss` and `aud` when configured.
- A denylist by `jti`, behind an interface a program backs with the store of subtask 09
  or Redis.
- A typed claims struct is the result, and each failure has its own error: malformed,
  algorithm mismatch, signature mismatch, expired, not yet valid, issuer, audience,
  parse error, revoked, key not found.

Signing:

- `iat`, `exp` from a TTL, `nbf`, and a random `jti` are filled in unless the claims
  set them.
- `kid` goes in the header.

Keys:

- A JWKS (RFC 7517) can be served at `/.well-known/jwks.json` or consumed.
- A token without `kid` is refused when the set holds more than one key, and checked
  against the one key otherwise.
- A key resolver looks up a key by `kid`, for rotation.

Decoding without verification, for logging or behind a gateway that verified the token
already.

HS256, HS384, and HS512 can be Goose with goose-hash's HMAC. RS, PS, and ES need goose-tls
and OpenSSL, so they go in an optional module, as compression does. Converting ECDSA
signatures between DER and raw `R || S` (RFC 7515 §3.4) is part of that module.

## What was built (2026-10-27)

Checked first: Goose's `master` at `upstream/master` on 2026-10-27, 138 commits past
`v2026.3`, adds no base64url, HMAC, or JWT, and no open pull request does. Its
`base64` (already in `v2026.3`) reads only the standard alphabet, padded. Goose's
issue 113 offers pure-Goose RSA, ECDSA, and X.509 as packages of their own, not stdlib.

`jwt.goose` takes the checklist as follows:

- Verification: all of it but the denylist. The errors are `plod::JwtError`'s, with a
  parse error folded into `Malformed`. The claims are a `plod::Jwt` handed to a block,
  `jwt_verify(token, keys, check) { t => ... }`: `json::read_string`'s slices are
  rooted at the reader, local to the call, so a returned struct can't hold them
  (spec §9.2), and the block keeps them uncopied.
- The denylist: no interface. The program checks `t.jti` in the block and calls
  `plod::invalid_token(cx)`, the same `if` an interface would compile to; the test
  does it.
- Signing: as listed. The program's own claims come from a block that writes them
  with json's writer.
- Keys: the `kid` rule over a slice of `plod::JwtKey`, which is rotation's resolver: a
  program lists the old key and the new one.
- JWKS: left for public keys. An HS256 JWKS holds the shared secret, so serving one at
  `/.well-known/jwks.json` would publish it, and consuming one is reading a config file.
- Decoding without verification: left. Behind a gateway, `plod::bearer` and
  `json::reader` over the decoded payload do it, and a helper waits for a program that
  needs one.
- HS384 and HS512: left. They need SHA-512, which goose-hash doesn't have.

Tests: `test/jwt/jwt.goose`, with RFC 7515's A.1 example (RFC 7519 §3.1's too), two
tokens signed here that match Python's `hmac` byte for byte, and each refusal;
`test/middleware/jwt_bearer.goose`, the route's answers; and
`test/jwt/jwt_without_hash.goose`, a program without goose-hash that must not compile.

### The plan for RS256 and ES256

A second optional module, `plod.jwt_pk`, over goose-tls, which links OpenSSL 3's
libcrypto already. goose-tls signs ES256 for goose-acme's JWS (`tls::sign_es256`), so
ES256 goes first: verification and loading a public key from a JWK or PEM go in
goose-tls, a task there, and the module converts signatures between JWS's raw `R || S`
and DER (RFC 7515 §3.4). RS256 and PS256 follow over the same calls. JWKS comes with
the module: serving the public keys at `/.well-known/jwks.json` and consuming another
issuer's, with the `kid` rule. A pure-Goose module over issue 113's packages would
drop OpenSSL, once one of them is maintained as a package.

## Acceptance criteria

- [x] HS256 signing and verification in Goose, feeding `plod::bearer`'s verifier
      (`plod::jwt_bearer`, 2026-10-27); subtask 04's cookie form takes `jwt_verify`
      when it's built
- [x] Each check above tested, with RFC 7515's and RFC 7519's examples among the vectors
      (2026-10-27)
- [ ] JWKS serving and consuming, with the `kid` rule, tested: in `plod.jwt_pk`
- [x] A plan for RS256 and ES256 recorded, with the module and its dependency
      (2026-10-27)
- [x] The README's JWT row and `docs/reference.md` updated (2026-10-27)
