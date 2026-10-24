# 062: Static files, and whether a cache pays

Status: in progress (2026-10-24): built and measured; the release and the board's
numbers are left. Where the time
of a static file over TLS goes in `plod::files`, and, if reading the disk is it, a file
cache in goose-http that a program chooses where it calls `plod::files`, bounded, and
following the disk. Reading the disk was most of it: `plod::cached_files`, over
goose-http's `http::serve_cached`, answers static-h2 60% faster ("Results").

## Why

HttpArena scores static-h2 and static-h3 (task 047, "The pull request"). In the
results of 2026-10-23 (Plod `v0.5.4`, HttpArena's 64-core Threadripper), the entry's
static-h2 is about 350 of 1,000:

| Profile | Connections | Entry | CPU | Leader |
|---|---:|---:|---:|---:|
| static-h2 | 256 | 407,892 | 6,241% | swerver, about 1.1 M on average |
| static-h2 | 1,024 | 375,952 | 6,442% | |
| static-tls (reference only) | 1,024 | 437,637 | 6,491% | fib, 1,229,892 |

Both serve about 15 KB a response, the leaders' within 5%, so the gap isn't in what
is sent. At 6,300% CPU for 392 K requests a second, a request costs about 160 µs of
CPU; baseline-h2 costs about 2 µs (14.4 M at 3,000%). AES-GCM over 15 KB is a few
microseconds, so neither the bytes nor the cipher explain it on their own. static-h3
will be scored the same way once the entry runs it.

## What the rules allow

`site/content/docs/add-framework/implementation-rules/frameworks/standard.md` at
HttpArena's `d9438f6`, "Static files: the cache is the framework's, not the entry's":
an entry may serve from memory when the cache is the framework's own documented
static handler, and the cache follows the disk ("Replace a file and the next response
must carry the new bytes"). A cache assembled in the entry is out, as is a mapping
filled once and never checked. Choosing a file's `.br` or `.gz` copy off
`Accept-Encoding` is allowed for every entry.

## What `plod::files` does now

Per request, with goose-http `v0.5.9`'s `file.goose`:

- `http::open_precompressed` opens the file and reads its size and time, then opens
  the copy that `Accept-Encoding` weighs highest (`.br` under HttpArena's
  `br;q=1, gzip;q=0.8`), and closes the original: two opens and a close before a byte
  is read.
- Over TLS, the body is read in pieces of up to 64 KiB (`FILE_PIECE`) at each `MORE`,
  into a buffer of its own and then into the write buffer, and encrypted from there.
  `sendfile` (`direct`) runs only on plain TCP, for pieces from 64 KiB.
- The file is closed at the end. Nothing is kept between requests.

The 20 files are 1.16 MB together; the largest, `vendor.js`, is 300 KB, 67 KB as
`.br`.

## Steps

1. A/B, on any machine with Docker: static-h2's load (HttpArena's
   `scripts/lib/tools/h2load.sh` for static-h2: its URI list, `Accept-Encoding`, and
   streams) against the entry as it is, and against a throwaway build that serves the
   20 files' bytes from memory, on the same CPUs, interleaved. Not committed: the rule
   forbids that build as an entry. The ratio says whether opening and reading the
   files is the cost. The absolute numbers don't matter, so Docker Desktop is fine.
2. If it isn't, profile static-h2 on Linux (`perf record` on the server's workers),
   once a Linux machine is free (the desktop runs the h3 tuning as of 2026-10-24):
   the h2 framing and flow control, the copies, the `MORE` turns per file, and TLS
   records are the candidates. A cache wouldn't help then; record the cause here and
   the fix in goose-http.
3. If it is, design the cache, then build it in goose-http (a file cache is HTTP
   machinery) with a Plod form of `plod::files` that takes it:
   - The program chooses it where it calls `plod::files`; no field on `Cx` and no
     cost to a program that doesn't (AGENTS.md, "Keep changes small").
   - Bounded as a promise: a byte budget per worker, reserved when the worker starts,
     and a file past what's left isn't cached but served from disk as now. Workers
     share nothing, so each holds its own copy; say what that costs at 64 workers.
   - Follows the disk: each request checks the file's size, time, and inode with one
     `stat` before serving cached bytes, and reads it again where they changed. Say
     what that check costs against the two opens it replaces.
   - The `.br` and `.gz` copies are cached as files of their own, chosen as
     `open_precompressed` chooses them.
   - A test that replaces a file and gets the new bytes on the next request, and one
     that fills the budget.
4. Measure the entry's static-h2 and static-tls before and after, and baseline's peak
   RSS, which a cache must not raise for routes that don't use it.

## Results

Measured 2026-10-24 on Tiamat: Ryzen 7 5800X3D, WSL2 Ubuntu 26.04.1, kernel
6.18.54.1-microsoft-standard-WSL2, natively, not in Docker. The entry built from the
local checkouts with gcc `-O3 -march=native`, as its image builds it: Plod `v0.5.8`
and goose-http `v0.5.11` as released (disk), the same with the shim's
`net_file_open`, `net_file_read`, and `net_file_close` answering from the 50 files read
into memory at start (memory, the throwaway, not committed), and this task's cache
(cache). 4 workers on CPUs 0-3, `ulimit -n` 1,048,576 as in Docker. The load on CPUs
4-15 with 12 threads for 5 s: static-h2 is h2load with HttpArena's 20 URIs, its
`Accept-Encoding`, and 32 streams; static-tls is wrk with `static-rotate.lua` on 8081;
static-h3 is HttpArena's h2load-h3, 64 connections of 64 streams. Cycles are the
server's, by `perf stat`, per request. One round, the builds interleaved.

### The A/B: the disk is the cost

| Profile | Disk | Memory | Change | User cycles a request | Kernel cycles a request |
|---|---:|---:|---:|---|---|
| static-h2, 256 | 144.9 K | 210.8 K | +45% | 45.6 K, 48.9 K | 65.3 K, 26.0 K |
| static-h2, 1,024 | 137.4 K | 198.5 K | +44% | 50.6 K, 53.0 K | 68.3 K, 26.8 K |
| static-tls, 1,024 | 94.8 K | 129.4 K | +37% | 51.0 K, 50.1 K | 101.5 K, 57.1 K |
| static-h3, 64 | 102.8 K | 131.1 K | +27% | 94.5 K, 99.6 K | |

Goose's work is the same; the kernel's halves. `perf record` of the kernel's cycles on
static-h2 at 256 connections, disk: `openat` 31% (its path walk 13%), `pread` 8%,
`close` 8%, `fstat` 4%, and the sends 33%. So the h2 framing, the copies, and the TLS
records weren't the cause, and step 2's profile wasn't needed.

At `ulimit -n` 10,240, the disk build answered 12,850 requests of static-h2 at 1,024
connections with 500: 32 streams of 1,024 connections hold more files open than that.
Docker's limit, which HttpArena's containers get, is 1,048,576.

### The cache

goose-http's `http::serve_cached`, and Plod's `plod::cached_files` over it, with the
design and its costs in goose-http's
[decisions](https://github.com/kaitk/goose-http/blob/main/docs/decisions.md#a-program-can-keep-small-files-in-a-workers-cache-that-follows-the-disk).
The entry's budget is 1 MiB a worker. HttpArena's requests reach 19 files, 258 KB, so
16.5 MB at 64 workers.

Locally `/data/static` is a symlink into HttpArena's checkout, which makes each path
walk 8 components; HttpArena's containers bind-mount the directory, 3. These runs bind
it as the container does, in a mount namespace:

| Profile | Disk | Memory | Cache | Cache against disk | Kernel cycles a request |
|---|---:|---:|---:|---:|---|
| static-h2, 256 | 157.5 K | 226.0 K | 251.1 K | +60% | 56.8 K, 23.1 K, 29.3 K |
| static-tls, 1,024 | 107.5 K | 139.1 K | 126.9 K | +18% | 89.4 K, 54.0 K, 68.0 K |
| static-h3, 64 | 118.0 K | 147.6 K | 133.0 K | +13% | 55.6 K, 22.6 K, 39.4 K |

With the symlink, static-h2 at 1,024 connections went from 142.9 K to 221.6 K (+55%).
On h2 the cache beats the memory build: a cached file goes whole in the request's turn,
with one copy and no `MORE`, so its user instructions fall 11% (87 K to 78 K). The gap
to the memory build elsewhere is the stats, about 2.25 a request: the file, and each
copy tried, two of them missing for the `.woff2` and `.webp` files.

Peak RSS: static-h2 at 256 connections 52 MiB against 47; at 1,024, 83 against 116; and
static-h3 60 against 120, since a cached response leaves in its turn. baseline (wrk,
4,096 connections, `/baseline11`, 2 rounds) is unchanged: 18 MiB on both builds, and
4,340 to 4,343 user instructions a request.

HttpArena's staleness probe, by hand on a copy of the files: `app.js` and its `.br` and
`.gz` replaced by `mv` with random bytes of the same length, then put back by `mv` of a
`cp -p` copy, with its old time. Over h2 and HTTP/1.1 over TLS, with `br`, `gzip`, and
`identity`, each answer after the replacement carried the new bytes, and each after
the restore the old.

Tests: goose-http's `test/http/file_cache.goose` (a file read in, a range of it, a
replacement by `rename` at the same length, a `.br` copy, the budget full, and a file
past 64 KB), and Plod's `test/pieces/files.goose`, whose cases now run through both
`plod::files` and `plod::cached_files`, with a replaced file.

## Acceptance criteria

- [x] The A/B's ratio recorded here, with the machine and how it was run (2026-10-24)
- [x] The cause named: the disk path, or what else, with the profile behind it
      (2026-10-24)
- [x] If a cache: its design recorded in goose-http's `docs/decisions.md`, built, and
      tested for a replaced file and a full budget (2026-10-24)
- [x] If a cache: the entry's static-h2 measured before and after, and the entry using
      it through Plod's documented call (2026-10-24)
- [ ] Released, and the board's static-h2, static-tls, and static-h3 recorded
