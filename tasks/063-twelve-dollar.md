# 063: The $12 Server Challenge

Status: in-progress (2026-11-14). #417 scored 115,000 users; the follow-up, #440,
with 1,024 receive buffers, a checkpoint lane, and the feed as range reads, waits to
be merged and scored; see "The follow-up" and "Range reads and the re-arm".

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

### Measured on x86-64, 2026-11-12, third session

AMD Ryzen 7 5800X3D (8 cores, 16 threads), Windows 11, WSL2 Ubuntu 26.04 on Linux
6.18.58.1-microsoft-standard-WSL2, Docker 29.8.2 on the same kernel. The scripts in
`bench/twelve-dollar/` as their README says, with `G` a folder in WSL holding the
checkouts; images rebuilt from the entry's `install.sh` (Goose v2026.4, gcc 13.3.0).
The entry built with `build-gh.sh goose-http direct-descriptors` against goose-http
`direct-descriptors` with the shutdown fix below; it passes the 42 checks (`check.sh`).

`bench.sh plod|kensac 4000 20`, 60 s after a 15 s ramp, three alternating rounds:

| Server | µs a request | user | kernel | p99 |
|---|---:|---:|---:|---:|
| rust-iouring-kensac | 27.2 to 27.5 | 4.6 to 4.7 | 22.5 to 22.9 | 1.9 to 2.3 ms |
| entry | 32.5 to 33.3 | 10.1 to 10.3 | 22.3 to 23.2 | 52 to 118 ms |

Kernel time is twice the Mac's for both servers: perf puts 40% of the entry's samples
in the receive path that loopback through Docker's bridge and netfilter runs inside
each send. It is the same for both, so the gap is user time: 10.2 µs against 4.65.
`count.sh base`: 0.121 `io_uring_enter`, 0.030 `pread64`, 0.757 `pwrite64`, 0.141
context switches a request, as on arm64.

Where the entry's user time goes (`perf.sh plod`, cpu-clock, 20 s at 4,000 users;
user code is 31% of samples, so 1% is about 0.33 µs):

| Part | Samples | About |
|---|---:|---:|
| SQLite (VDBE, B-tree, page cache) | 23.0% | 7.6 µs |
| goose-http | 2.3% | 0.75 µs |
| Plod and the entry's handlers | 1.7% | 0.55 µs |
| Goose runtime (`find_any`, `format`, copies) | 1.5% | 0.5 µs |
| libc `memcpy` | 1.2% | 0.4 µs |
| goose-sqlite's shim | 0.6% | 0.2 µs |

SQLite alone takes more user time than the whole of kensac, which reads the B-tree
without SQL. No Goose-side function reaches 0.25 µs. What was tried:

- **`find_any` for JSON escapes** is already the fastest choice on x86-64. On the
  entry's strings (a timestamp, a username, bodies of 10 and 140 bytes), the 34-byte
  set's SSSE3 table path takes 7 ns a string, two SSE2 scans (the control range, then
  `"` and `\`) 13 ns, and a byte loop over a table 24 ns. `json_string` costs about
  0.2 µs a request at 29 calls.
- **SQLite at `-O3`** (`c_flags_cc` in goose-sqlite's `sqlite.build`), as kensac
  builds it: 32.5 to 32.7 µs against 32.6 to 32.9 at `-O2` in three alternating rounds
  (`ab.sh 3 base o3`), in noise. Not kept.
- **The whole program at `-O3 -march=native`**, through a `gcc` wrapper passed to
  `--cc` ([findings](../docs/goose-findings.md#goose-build-takes-no-c-compiler-flags)):
  a program's `c_flags_cc` reaches only its own `c_sources`, not the generated C, the
  runtime, or the packages. 33.0 to 33.2 µs (user 10.4 to 10.6) against 32.6 to 33.7
  (user 10.1 to 10.3) at `-O2`, three alternating rounds (`ab.sh 3 o2 o3n`,
  2026-11-12). SQLite is most of the user time and gains nothing; HttpArena's h3 gain
  came from `copy_into`, which isn't hot here. Not kept. The rules allow it (rule 10
  builds on the box, and kensac builds with `target-cpu=native`).
- **SHA-256** looks costly in callgrind (9,000 instructions a block), but valgrind
  hides SHA-NI, so callgrind runs goose-hash's scalar rounds. On the CPU, `sha256_x86`
  is 0.06% of samples. Read callgrind's hash and SIMD costs with that in mind.
- goose-simd (gooseverse) is C intrinsics behind `c_headers`: Plod can't take it, and
  nothing in the profile would.

Writes: with `LIKE_PROB=0 POST_PROB=0` the entry costs 32.7 to 33.0 µs a request
against 32.4 to 32.6 with writes, two rounds each. A user's loop costs 65.7 µs without
writes and 70.5 µs with them, so a write costs about 28 µs, less than an average read;
`pwrite64` is 3.5% of samples inclusive, 1.2 µs a request. At this load a 1 ms pass
holds under one write, so group commit would rarely group, and its best case is
under 0.6 µs a request. It needs a pass-end hook that goose-http doesn't have, so it
wasn't built. The writes do cause the p99 tail: without them p99 is 2 ms.

Scaled by kensac's ratio here (310,000 users at 27.35 µs), 32.7 µs estimates about
259,000 users. The Mac's kernel time (12 µs, closer to a box without Docker's bridge)
with this machine's user times gives (12 + 10.2) / (12 + 4.65), about 233,000. Either
is above goose-iouring-davidhsv (220,000) and near fsharp-kestrel-delneg (247,000) and
csharp-kestrel-mbobka (260,000).

goose-http `direct-descriptors`: its whole `scripts/test.sh` passed on this machine
once a close waits for its shutdown in flight. Before that, h2spec over TLS on
`LOOP=uring-direct` failed 47 of 200 runs of `generic/2` (0 of 200 on `uring`): the
kernel runs a shutdown from io-wq and finds a fixed file by its slot only then, so a
connection's `SHUT_WR` reached the next connection accepted into its slot. After the
fix, 0 of 600 (goose-http's decisions, "Direct descriptors").

### Open

- **User time**: 10.2 µs against 4.65 on x86-64, of which SQLite is 7.6 µs. The
  framework's share is about 2.5 µs, with no single function above 0.25 µs.
- **Writes**: 0.76 `pwrite64` a request. Group commit (step 3) would share WAL frames
  only at rates where a pass holds several writes; it needs a goose-http hook at the
  end of a pass.
- **p99 with writes**: 52 to 118 ms against kensac's 2 ms, and 2 ms without writes:
  the WAL checkpoint running on the one worker. The checkpoint lane brings it to
  2.5 to 2.7 ms on x86-64 (see "The follow-up").
- **goose-http's receive buffers** (2026-11-14): 64 a ring is a CPU cliff past
  capacity. Raising the default costs every worker: HttpArena runs one a core, and
  1,024 would be 4 MB each. goose-http's branch `rearm` queues the `ENOBUFS`
  receives again only once buffers come back (see "Range reads and the re-arm").

Released 2026-11-12: goose-http `v0.5.19` (both branches), goose-sqlite `v0.0.4`
(`query`), and Plod `v0.5.12` (goose-http `v0.5.19`, Goose `v2026.4`). The entry
imports them (fork commit `0f1e8f2`): built with an empty package cache, it passes the
42 checks and measures 32.6 and 32.8 µs a request, as before.

Submitted 2026-11-12 as
[#417](https://github.com/arjaythedev/twelve-dollar-server-challenge/pull/417), head
`8cfed51`, CI green. Before submitting, the entry was checked against the failures and
rule flags the leaderboard records, and one held: it accepted a token without `exp`,
which SPEC.md requires and the review flags in over 30 entries. `8cfed51` refuses one
with 401. With 50,000 idle connections the server's RSS was 20 MB, about 0.3 KB a
connection.

### Scored, 2026-11-13

#417 was merged and scored 115,000 users, tied 99th of 220. The maintainer's notes: CPU
was only 50% during the hold; 120,000 failed at 97% CPU with timeouts and resets, and
160,000 got mostly "connection refused". So the entry failed at a CPU cliff, not at the
CPU per request measured above.

The cause: goose-http gives each ring `Config.ring_buffers` receive buffers, 64 by
default. When more connections than that have data in one pass, the rest get
`ENOBUFS`, their multishot receive ends, and each is queued again, pass after pass.
Below capacity a pass sees a few ready connections and the 64 never run out; past it,
connections queue, and the re-queuing takes CPU the requests needed.

### The follow-up, 2026-11-14

Fork branch `ring-buffers`, commit `b99d2ed`: `ring_buffers: 1024` in the entry's
`Config`, 4 MB, and the README's "How it works" and "Measured". It passes the 42
checks. goose-http's default stays 64 (see "Open").

Measured in Docker on the M1 Pro as before (Linux arm64, k6 1.3.0 in its own
container), 20,000 users with the think times divided by 5 or 10, 60 s after a 15 s
ramp, builds alternating, from a scratch copy of `bench.sh` that adds a pause, a ramp,
and a command wrapper. With the server held to 0.4 CPU so that k6 saturates it
(`CPUS=0.4`, think times divided by 10), two runs each:

| Build | req/s | p95 | p99 | max | µs a request |
|---|---:|---:|---:|---:|---:|
| v0, `8cfed51`, 64 buffers | 13,084 to 13,110 | 459 to 634 ms | 693 to 1,075 ms | 1,439 to 1,762 ms | 24.9 to 25.3 |
| `b99d2ed`, 1,024 buffers | 14,805 to 15,021 | 200 to 261 ms | 329 to 393 ms | 796 to 848 ms | 21.7 to 22.2 |

Below saturation the two are level. At 1 CPU and 8,000 requests a second, three runs
each: p99 11 to 33 ms against 10 to 26 ms, 21.5 to 21.7 µs a request against 21.3 to
23.3. Freezing the server 300 ms every 5 s (`docker pause`), two runs each: p99 319 to
328 ms against 314 to 325. A freeze leaves about 2,400 connections ready at once, so
re-queuing alone is cheap; it costs where a saturated worker never catches up. An
earlier single run (2026-11-13) that showed p99 65 → 12 ms below saturation didn't
repeat.

What was tried and left out:

- **More listeners**: three more on the port (`cfg.listeners`, SO_REUSEPORT), for four
  accept queues. With 300 ms freezes, p99 317 to 319 ms against 314 to 347 without, two
  runs each; with all 20,000 users arriving in 2 s, one pair, too few to tell. Not kept.
- **A checkpoint lane**: a goose-http lane thread with its own connection that
  checkpoints the WAL, asked every 1,024 writes, both connections on `unix-excl` (as a
  URI with `SQLITE_OPEN_URI`) so that they share the WAL index in memory. First as
  PASSIVE then RESTART, so that the WAL starts over. With fsyncs slowed to 20 ms
  (strace's `inject=fsync,fdatasync:delay_exit=20000`), RESTART made it worse: it holds
  the write lock through two fsyncs, the worker waits in the busy handler, which
  sleeps the whole event loop, and p95 rose from 3 ms to 36 to 52 ms, max to 879 ms.
  PASSIVE alone never resets the WAL, since writes keep arriving while it runs (270 MB
  at the worker's bound of 65,536 pages). PASSIVE with the worker's own checkpoint at
  16,000 pages, which copies only the rest: with slow fsyncs, p99 38 to 44 ms against
  77 to 79 without the lane, max 122 to 128 against 247 to 258, two runs each; with
  normal fsyncs and at saturation, level (p99 202 to 355 against 235 to 274 ms at 0.4
  CPU). On the Mac, a gain only on a slow disk, well inside the limits, for about 60
  lines; the fork's branch `checkpoint-lane` (`5f54422`, on `b99d2ed`) held it for the
  x86-64 runs, where it was kept (below). The builds with RESTART exited with status
  1 three times in about 20 runs, cause not found; the PASSIVE build and the buffers
  build ran 16 times without one.
- **Writes on a lane**, rejected before measuring: in WAL mode a commit on one
  connection empties the other's page cache, so the worker would lose its 16 MB cache
  on every write.

kensac checkpoints on a second thread at nice 19; Goose can't set a thread's priority,
but the lane didn't need it, so it isn't in `docs/goose-findings.md`.

#### Measured on x86-64

The machine and setup of the third session: AMD Ryzen 7 5800X3D, WSL2 Ubuntu 26.04 on
Linux 6.18.58.1-microsoft-standard-WSL2, Docker 29.8.2, twelve-box from the entry's
`install.sh` (unchanged in all three builds), k6 1.3.0 in another container,
`load-fast.js` with think times divided by 20, 60 s after a 15 s ramp, nothing else
in Docker. Builds `v0` (`8cfed51`), `v1` (`b99d2ed`), and `v2` (`5f54422`) with
`build.sh`; `v1` and `v2` pass the 42 checks. Three alternating rounds of each, with
`ab.sh`, and kensac once at each load with `bench.sh`. No server exited early.

`CPUS=0.4 VUS=10000 ab.sh 3 v0 v1 v2`, past capacity:

| Build | req/s | p95 | p99 | max | µs a request | user | kernel |
|---|---:|---:|---:|---:|---:|---:|---:|
| v0, 64 buffers | 9,897 to 9,931 | 529 to 551 ms | 623 to 878 ms | 853 to 2,493 ms | 35.1 to 35.2 | 8.9 to 9.6 | 25.6 to 26.2 |
| v1, 1,024 buffers | 10,982 to 11,181 | 413 to 432 ms | 501 to 532 ms | 585 to 765 ms | 31.2 to 31.7 | 6.1 to 7.7 | 23.6 to 25.0 |
| v2, v1 and the lane | 11,274 to 11,405 | 331 to 348 ms | 366 to 475 ms | 452 to 629 ms | 30.9 to 31.4 | 8.3 to 8.8 | 22.5 to 22.8 |
| rust-iouring-kensac | 13,454 | 184 ms | 204 ms | 286 ms | 25.6 | 3.6 | 21.9 |

`ab.sh 3 v0 v1 v2`, 1 CPU and 4,000 users, below capacity:

| Build | req/s | p95 | p99 | max | µs a request |
|---|---:|---:|---:|---:|---:|
| v0, 64 buffers | 6,557 to 6,563 | 1.7 ms | 116 to 124 ms | 218 to 237 ms | 32.3 to 32.6 |
| v1, 1,024 buffers | 6,544 to 6,563 | 1.7 ms | 115 to 123 ms | 237 to 254 ms | 32.3 to 32.6 |
| v2, v1 and the lane | 6,586 to 6,591 | 1.6 ms | 2.5 to 2.7 ms | 58 to 82 ms | 32.5 to 32.7 |
| rust-iouring-kensac | 6,588 | 1.4 ms | 1.8 ms | 28 ms | 27.1 |

Decided (2026-11-14):

- **Buffers kept.** Past capacity, v1 beat v0 in every round with no overlap: 12% more
  requests a second, p95 a fifth lower, 11% less CPU a request, as on the Mac. Below
  capacity the two are level.
- **The lane kept.** Below capacity it takes p99 from 115 to 124 ms to 2.5 to 2.7 ms,
  the tail that writes caused; past capacity, p95 is a fifth below v1's in every
  round. CPU a request is level. On the Mac it gained only with fsyncs slowed to 20
  ms. Why the checkpoint costs more on this machine wasn't measured, nor how fast
  the box's disk syncs. `ring-buffers` was fast-forwarded to
  `checkpoint-lane`, and the README's "How it works" now describes the lane and
  `unix-excl`.

The entry's README took these numbers (fork commit `ffd7b69`). #417 was squash-merged
upstream, so `upstream/main` was merged into `ring-buffers` (`2192d45`), with the
entry's folder as `ffd7b69` has it; the pull request's diff is the three changed
files. `2192d45` passes the 42 checks against upstream's current tests.

The follow-up is [#440](https://github.com/arjaythedev/twelve-dollar-server-challenge/pull/440),
head `2192d45`, opened 2026-11-14; its CI job was running when this was written.

### Range reads and the re-arm, 2026-11-14

What the entries above 250,000 do that this one didn't, from their READMEs and source
at upstream `7408eab`, by expected gain: re-arming `ENOBUFS` receives only once buffers
come back (kensac, fsharp-uring-delneg); the feed as range reads (csharp-kestrel-mbobka,
crystal-epoll-faustinoaq, fsharp-kestrel-delneg, −14% CPU a request on the board's box);
one transaction a pass with group commit (all of them); PGO for SQLite (mbobka,
crystal, delneg, −4.5%); and SQLite options, among them goose-sqlite's
`DEFAULT_FOREIGN_KEYS=1`, which kensac doesn't set. HttpArena's leaders (viltrum)
use epoll without SQPOLL or zero-copy sends, which fit neither one vCPU nor 5 KB
responses. The board's row for #417 gives 41 µs a request against kensac's 25, a wider
gap than the 1.2 measured here, so the box likely runs user code slower than the
5800X3D and these runs understate gains in SQLite.

The machine and setup of "Measured on x86-64" above, `ab.sh`, three alternating
rounds. `v2` is #440's head (`2192d45`); `v3` adds the feed as three range reads: the
20 newest ids from the index alone, then, when they are one run of consecutive ids,
one `BETWEEN` scan of posts joined to users and one grouped `BETWEEN` scan of the likes
index, else the plain query; `v4` adds a worker connection without foreign keys
(`sqlite::open`'s `foreign_keys: false`). The feed's JSON is byte for byte the same,
and both pass the 42 checks.

| Build | Load | req/s | p95 | p99 | µs a request | user |
|---|---|---:|---:|---:|---:|---:|
| v2 | 0.4 CPU, 10,000 users | 10,948 to 11,414 | 323 to 408 ms | 343 to 445 ms | 30.9 to 32.3 | 8.1 to 9.0 |
| v3 | 0.4 CPU, 10,000 users | 10,852 to 11,863 | 292 to 495 ms | 315 to 590 ms | 29.5 to 33.5 | 5.7 to 7.9 |
| v4 | 0.4 CPU, 10,000 users | 11,670 to 12,018 | 277 to 312 ms | 297 to 341 ms | 29.1 to 30.1 | 5.4 to 6.9 |
| v2 | 1 CPU, 4,000 users | 6,594 to 6,599 | 1.6 ms | 2.5 to 4.7 ms | 32.4 to 33.7 | 10.3 to 10.4 |
| v3 | 1 CPU, 4,000 users | 6,578 to 6,596 | 1.5 ms | 2.4 to 2.7 ms | 30.8 to 30.9 | 8.4 to 9.2 |
| v4 | 1 CPU, 4,000 users | 6,581 to 6,588 | 1.5 ms | 2.4 to 2.5 ms | 30.6 to 30.7 | 8.4 to 8.5 |

v3's worst round ran beside goose-http's test suite. Kept: v4, pushed to `ring-buffers`
as fork commit `c64ce3f`, so #440 carries it. User time a request falls by a fifth;
without foreign keys alone is level.

goose-http branch `rearm` (`3f830d7`, not merged or released): a receive that ends
with `ENOBUFS` parks its connection, oldest first, and the end of a pass re-arms only
as many as its ring will have free buffers; `ur_wait` starts at the next ring each
call. Its whole `scripts/test.sh` passed in WSL. In a test of 400 connections with 4
buffers, `ENOBUFS` fell from 11 to 14 a request to 0.9, completions from 12 to 16 to
2.9. In the entry (`v5`, `v4` built against it), two rounds each at 0.4 CPU and
20,000 users, where `v4b` and `v5b` are the same with 64 buffers:

| Build | req/s | p95 | p99 | max | µs a request |
|---|---:|---:|---:|---:|---:|
| v4b, 64 buffers | 10,864 to 10,990 | 1,313 to 1,357 ms | 1,371 to 1,749 ms | 1,524 to 1,951 ms | 34.2 to 34.7 |
| v5b, 64 and the re-arm | 11,638 to 11,687 | 1,151 to 1,183 ms | 1,391 to 1,547 ms | 4,040 to 5,086 ms | 32.2 to 32.3 |
| v4, 1,024 buffers | 12,696 to 12,752 | 1,052 to 1,108 ms | 1,306 to 1,353 ms | 1,408 to 1,464 ms | 29.5 to 29.7 |
| v5, 1,024 and the re-arm | 12,613 to 12,616 | 1,091 to 1,107 ms | 1,268 to 1,525 ms | 1,367 to 1,744 ms | 29.8 |

With 64 buffers the re-arm gives 7% more requests a second at 6% less CPU, but the
slowest request waits 4 to 5 s: parked connections queue behind each other. With
1,024 it is level (and +1% at 10,000 users, three rounds), so the entry keeps
goose-http `v0.5.19`. Before `rearm` merges, the parked wait needs a bound.

Group commit and one transaction a pass need a goose-http hook at the end of a pass,
a public API, so they wait for a proposal (AGENTS.md, "Keep changes small").

### Next

Wait for #440 to be merged and scored, and record its hold here. Expected: past
120,000, since 12% more requests a second at the cliff is about 130,000, and the range
reads add about 6% more. The board measured #417 at 41 µs a request against kensac's
25, a wider gap than here, so the ceiling from CPU a request is about
310,000 × 25 / 41, near 190,000, before the range reads. Whether the refusals at
160,000 follow the cliff or are a limit of their own isn't known. goose-http's
`rearm` waits for a bound on the parked wait (above).

## Acceptance criteria

- [x] goose-sqlite's tests pass on Linux x86_64 (branch `query`, WSL2 Ubuntu 26.04,
      2026-11-12)
- [x] The query layer is in a goose-sqlite release (`v0.0.4`, 2026-11-12)
- [ ] The group-commit decision is in `docs/decisions.md` and `docs/architecture.md`
- [x] The entry passes the challenge's `test/run.sh`, 42 checks (macOS arm64, and
      Linux arm64 in Docker, 2026-11-12)
- [x] The pull request is open upstream (#417, 2026-11-12)
- [x] The board's 5-minute hold for #417, recorded here (115,000 users, 2026-11-13)
- [x] The follow-up pull request is open upstream (#440, 2026-11-14)
- [ ] The board's hold for the follow-up, recorded here
