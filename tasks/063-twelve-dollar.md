# 063: The $12 Server Challenge

Status: in-progress (2026-11-12). The entry passes the challenge's 42 checks on
macOS and on Linux; see "State".

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

## State

Built 2026-11-12, local commits only:

- goose-sqlite, branch `query`: the `Conn` query layer (step 2), `NO_MUTEX`, handle
  lookups without a lock, and a `busy_timeout` that yields before it sleeps, with
  tests and decisions.
- The entry, branch `goose-plod-kaitk` of the fork: `app.goose`, five routes in about
  250 lines, and `server.goose`. It imports goose-sqlite by relative path until
  goose-sqlite has a release with the branch; then it takes the tag.
- No Plod change. Group commit (step 3) wasn't needed to pass rule 6 or to run: each
  write commits alone in WAL with `synchronous=NORMAL`. Whether group commit saves
  kernel time stays open below.

Continued 2026-11-12, local commits only:

- goose-http `batched-waits` (worktree `../goose-http-batched-waits`):
  `Config.ring_batch_us`, a wait that holds for up to 256 completions, never past the
  next timer, default 0; with its test, decision, and architecture entry, and the
  Ubuntu 24.04 ALPN trap in `docs/known-issues.md`. Its whole `scripts/test.sh` passed
  in an Ubuntu 26.04 arm64 container.
- goose-http `direct-descriptors`, on top of it (`../goose-http-direct`):
  `Config.ring_direct`, connections as io_uring direct descriptors, rings added as
  tables fill, up to 16, peer addresses from single-shot accepts; `LOOP=uring-direct`
  in the benchmark server and `scripts/test.sh`; test, decision, architecture. Its
  tests passed through the uring-direct HTTP tests, whose fd-limit step now skips
  for direct descriptors; the steps after it (epoll loop, echo, examples) and h2spec
  (x86-64 only) haven't run on this branch.
- Plod `json-string` (`../plod-json-string`): `format_fields` writes strings with
  `http::json_string`, and the stdlib's byte-at-a-time scan is in
  `docs/goose-findings.md`. Plod's `scripts/test.sh` passed on macOS.
- The entry: one process, `ring_direct`, `ring_batch_us: 1000`,
  `locking_mode = EXCLUSIVE`, `wal_autocheckpoint = 16000`, and `http::json_string`.
  It imports goose-http at `@direct-descriptors`, which builds only with that
  worktree mounted in the package cache as the ref (`../twelve-bench/build-gh.sh`)
  until the branch is pushed or released. It passes the 42 checks on Linux arm64.

### Measured

Docker on an M1 Pro, Linux arm64, server container 1 CPU and 2 GB, k6 1.3.0 in another
container, `bench/load.js` with its think times divided by 20 (4,000 users, 6,300
requests a second). CPU per request from the container's cgroup, over the whole run:

| Server | µs a request | user | kernel |
|---|---:|---:|---:|
| rust-iouring-kensac | 16.0 | 4.0 | 12.0 |
| entry, first build, 6 processes | 61.2 | | |
| entry, 1 process, first build | 35.2 | | |
| entry, 1 process, final | 28.6 | 12.5 | 16.1 |
| entry, 2 processes, final | 37.1 | 15.5 | 21.6 |
| entry, 3 processes, final | 44.4 | 18.1 | 26.2 |
| entry, 6 processes, final | 52.9 | 21.2 | 31.7 |

What moved it, found with callgrind on one process:

- `ONE_POST` was re-prepared on every request: with `JOIN users`, SQLite's constant
  propagation marks the bound id, so each new binding expires the statement. A scalar
  subquery for the author doesn't (11 percent of instructions).
- `PRAGMA mmap_size` made every page read look the page up in the WAL index (30
  percent); without mmap, the page cache answers.
- Mutexes were 17 percent: goose-sqlite's handle table and SQLite's connection mutex,
  a lock pair per column read. `NO_MUTEX` and lock-free lookups removed them.
- Writers in several processes sleep in SQLite's busy handler, which stalls the
  process's event loop: two processes at 20,000 fast users fell to 9,600 requests a
  second with a 6 s maximum. Yielding first held 16,700. k6 in this setup tops out
  near 19,000 a second and at about 28,000 connections from one container, so
  saturation and connection counts aren't measured here.

Scaled by kensac's ratio (310,000 users at 16.0 µs here), three processes at 44.4 µs
estimate about 112,000 users: above Axum (76,000) and Go's net/http (55,000), below
uWebSockets (125,000) and Kestrel (260,000). One process, at 28.6 µs, would estimate
about 173,000.

### Measured, 2026-11-12, second session

The same setup. The Mac was loaded by other work for much of the session, and runs
drifted up to 40%, so changes were compared in alternating rounds, by the lowest of
each, or by counts (`perf stat`, callgrind) that load doesn't move. perf works in
Docker's VM (Linux 7.0) as cpu-clock samples from a privileged Alpine container
(`../twelve-bench/perf.sh`, `count.sh`, `ab.sh`). A quiet stretch at the end gave
these, two runs each:

| Server | µs a request | user | kernel |
|---|---:|---:|---:|
| rust-iouring-kensac | 15.6 to 16.2 | 3.9 to 4.1 | 11.7 to 12.0 |
| entry, 3 processes, before this session | 42.0 to 42.7 | 17.2 to 17.5 | 24.8 to 25.2 |
| entry, 1 process, all of the below | 21.4 to 22.0 | 9.7 to 10.0 | 11.7 to 11.9 |

What moved it:

- **One process.** With 3 processes, `pread64` was 10% of samples: each commit
  changes the WAL, so the other processes drop their whole page cache at their next
  read. With 1 it was 0.15%. Direct descriptors make one process possible: at 4,000
  connections they cost nothing measurable (21.4 µs in three rounds against 21.1 to
  22.8), and with `RLIMIT_NOFILE` at 512 the load ran on 8 rings, no failures, the
  process holding 16 descriptors; each extra ring costs an enter a pass.
- **`locking_mode = EXCLUSIVE`**: no `fcntl` locks or `-shm` per transaction, as kensac's
  `unix-excl` VFS. 39.5 → 36.3 µs at the best of three rounds (busy machine).
- **Batched waits**, 1 ms: `io_uring_enter` 1.14 → 0.11 a request, context switches
  0.38 → 0.11; lower CPU in each of three rounds, by 3 to 7 µs.
- **`wal_autocheckpoint` 16,000** against 4,000: 32.6 against 36.6 at best, in noise.
- **`http::json_string`**: the stdlib's escape loop was 85% of the feed handler's own
  samples; 100,365 → 97,042 instructions a request. On arm64 `find_any` has no vector
  path; x86-64's SSE2 path should save more.
- Not worth it: a 64 MB page cache (page reads stay 0.03 a request at 16 MB), and one
  read transaction per pass (starting one costs 750 instructions a request with
  exclusive locking).

Kernel time now equals kensac's; the user-time gap is 6 µs. Scaled by kensac's ratio,
21.7 µs estimates about 227,000 users: above goose-iouring-davidhsv (220,000), below
fsharp-kestrel-delneg (247,000), csharp-kestrel-mbobka (260,000), and
csharp-kestrel-btree-mbobka (280,000); far above rust-axum-tbsvttr (76,000).

### Open

- **User time**: 9.7 µs against 4. In callgrind, SQLite's VDBE and B-tree are about
  70%; the rest is goose-http, Plod, and the JSON writer. The box is x86-64, where
  Goose's SIMD paths differ from arm64's, so profile there.
- **Writes**: 0.76 `pwrite64` a request, about 4.5 a write, each commit writing its own
  WAL frames. Group commit (step 3) would share them; worth about 0.5 µs a request
  here, more at the box's rate.
- **goose-http `direct-descriptors`**: run the rest of `scripts/test.sh` and h2spec,
  on x86-64; then release goose-http with both branches, for the entry to import a tag.

### Next

Moved to an x86-64 machine (2026-11-12), with the scripts in `bench/twelve-dollar/`: finish `direct-descriptors`' tests there,
re-measure the entry on x86-64, and look for Goose-level wins where a profile shows
them (vector scans, bounds checks), including gooseverse's goose-simd.

## Acceptance criteria

- [ ] goose-sqlite's tests pass on Linux x86_64
- [ ] The query layer is in a goose-sqlite release
- [ ] The group-commit decision is in `docs/decisions.md` and `docs/architecture.md`
- [x] The entry passes the challenge's `test/run.sh`, 42 checks (macOS arm64, and
      Linux arm64 in Docker, 2026-11-12)
- [ ] A 5-minute hold measured on a 1 vCPU VM, recorded here
- [ ] The pull request is open upstream
