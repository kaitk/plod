# 063: The $12 Server Challenge

Status: todo (2026-11-12)

The [$12 Server Challenge](https://github.com/arjaythedev/twelve-dollar-server-challenge)
scores a five-endpoint feed API on SQLite on a 1 vCPU, 2 GB box: the most users that hold
five minutes with p95 under 500 ms, p99 under 1 s, and under 1% errors. Plod enters as a
framework: routes, extractors, and middleware as an application writes them, on
goose-http, not a hand-written event loop.

## The board on 2026-11-12

From the challenge's `LEADERBOARD.md` at `e4a9036`:

| Entry | Users held | Note |
|---|---:|---|
| rust-iouring-kensac (first) | 310,000 | hand-written io_uring, SQLite B-tree reads, one thread |
| goose-iouring-ahmadsh2007 | 270,000 | kensac's design in Goose, C for io_uring and SQLite |
| goose-iouring-davidhsv | 220,000 | the same design, with a write queue |
| csharp-kestrel-btree-mbobka | 280,000 | Kestrel host, B-tree reads |
| csharp-kestrel-mbobka | 260,000 | Kestrel host, SQL |
| fsharp-kestrel-delneg | 247,000 | Kestrel host |
| rust-axum-tbsvttr | 76,000 | Axum |

The first seventeen entries are within 15% of each other at 25 to 28 µs a request, most
of it in SQLite. The framework entries are Plod's comparison: the goal is the highest
framework entry, 250,000 users or more, with SQL through prepared statements and no
B-tree reads.

The rules that shape the entry:

- SQLite only, in-process (rule 2). goose-postgres and Turso don't apply: Turso's MVCC
  writers and asynchronous I/O gain nothing on one vCPU with the data in the page cache
  (2026-11-12).
- No caching across requests; prepared statements are allowed (rule 5).
- A 201 means the row is committed, in WAL with `synchronous=NORMAL` or stronger. Group
  commit is allowed if each response waits for its commit (rule 6).
- Built from source on the box by `install.sh` and `build.sh`, pinned versions, healthy
  within 60 s of `start.sh` (rule 10).
- Direct on `0.0.0.0:80` means up to about 15,000 keep-alive connections.

## Steps

1. **goose-sqlite on Linux x86_64**, built from its amalgamation, with its task 001
   finished.
2. **A query layer in goose-sqlite** in the shape of a composable `Sql`: literal text,
   fragments that splice, values bound in order, statements prepared once and reused,
   and a row read into a value for one row, many, or none. Aegon's builder and
   relations stay with Aegon idea 16.
3. **Group commit in Plod.** Every leader runs one thread and commits a pass's writes
   together, answering each after its commit. On one vCPU, a lane per database adds a
   thread hop per request, so reads run on the worker and writes queue for the pass's
   commit. The shape goes in `docs/decisions.md`, beside task 052's, without fields in
   `Cx` or code on shared paths.
4. **The entry**, `submissions/goose-plod-kaitk/` in the fork
   [`kaitk/twelve-dollar-server-challenge`](https://github.com/kaitk/twelve-dollar-server-challenge),
   importing tagged releases of Plod, goose-http, and goose-sqlite; `install.sh` takes
   the pinned Goose release, gcc, and liburing.
5. **Measure** on a 1 vCPU Linux VM with the challenge's `bench/load.js`, record the
   numbers here, then open the pull request.

## Acceptance criteria

- [ ] goose-sqlite's tests pass on Linux x86_64
- [ ] The query layer is in a goose-sqlite release
- [ ] The group-commit decision is in `docs/decisions.md` and `docs/architecture.md`
- [ ] The entry passes the challenge's `test/run.sh`, 42 checks
- [ ] A 5-minute hold measured on a 1 vCPU VM, recorded here
- [ ] The pull request is open upstream
