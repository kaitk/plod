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

### Open

- **Connections past `LimitNOFILE` in one process.** Every k6 user holds a
  connection, and the box gives a process 65,535 descriptors. The leaders take them as
  io_uring direct descriptors, across several rings in one process. goose-http has
  neither, so the entry runs one process per 64,000 connections, and each process
  more costs about 8 µs a request (above). That is a goose-http change; one process
  would cost 28.6 µs here, about 1.6 times kensac.
- **Kernel time**: 16 µs a request against kensac's 12. kensac waits for up to 256
  completions or 1 ms per pass and commits a pass's writes together; goose-http
  answers each wake at once. Not measured apart.
- **User time**: 12.5 µs against 4. Most is SQLite's bytecode engine for the feed's 20
  rows and their like counts; kensac reads the B-tree directly, which the rules allow
  but this entry, as an application written on Plod, doesn't.

### Next

Agreed for the next session (2026-11-12), both in goose-http, with no Plod change:

1. **Batched waits**, first, as it is small and shows how much of the kernel gap is
   wake-ups: `ur_wait`'s `io_uring_submit_and_wait_timeout(…, 1, …)` waits for up to
   N completions or a cap such as 1 ms, never past the next timer, behind a `Config`
   field whose default keeps today's behaviour. Linux 6.12's minimum wait does it
   more exactly; the box runs 6.8.
2. **Direct descriptors, then rings past the first.** Accept into the ring's file
   table and send and receive on fixed files, keeping the epoll emulation on plain
   descriptors. Four spots need care: the client address (`net_peer`'s `getpeername`;
   single-shot accepts that return it instead), the inline `send(2)` for sends of
   64 KB or more, `ur_send_file`'s splice (`SPLICE_F_FD_IN_FIXED`), and the
   emulation. Then a worker adds a ring when one is near 65,535 connections; the
   extra rings report to the first by a poll on their descriptors, so the loop still
   waits in one place.

Look for other quick wins before starting either: profile the 3-process entry again,
kernel side included.

## Acceptance criteria

- [ ] goose-sqlite's tests pass on Linux x86_64
- [ ] The query layer is in a goose-sqlite release
- [ ] The group-commit decision is in `docs/decisions.md` and `docs/architecture.md`
- [x] The entry passes the challenge's `test/run.sh`, 42 checks (macOS arm64, and
      Linux arm64 in Docker, 2026-11-12)
- [ ] A 5-minute hold measured on a 1 vCPU VM, recorded here
- [ ] The pull request is open upstream
