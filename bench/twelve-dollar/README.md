# The $12 challenge's measurement setup

Task 063 records what these measured. Each script needs `G`, the folder that holds
the checkouts: the fork's `twelve-dollar-plod` (branch `goose-plod-kaitk`),
goose-sqlite's branch `query` as `goose-sqlite-query`, and for `build-gh.sh` a
goose-http checkout. Output and caches (`k6/`, `bins/`, `cg/`, `perf/`, `goose-home4/`,
`kensac/`) go beside the scripts, and `.gitignore` keeps them out of commits.

The seed comes from the challenge's `seed/make-seed.sh`, which needs Node and the
sqlite3 CLI; `docker run --rm -v $G/twelve-dollar-plod:/w -w /w node:22-bookworm bash -c
"apt-get update && apt-get install -y sqlite3 && bash seed/make-seed.sh"` runs it
without either. On a Linux host, Docker keeps file owners, so the containers' users
need write access to what they write: `deploy` (uid 1001) to
`submissions/goose-plod-kaitk/`, `goose-home4/`, and `kensac/`, and k6's user to
`k6/`, `perf/`, `cg/`, and `bins/` (`chmod 777` is enough). Docker Desktop on macOS
maps owners and needs neither.

- `box/`, `kbox/`, `vbox/`, `pbox/`: the images `twelve-box` (the entry's install.sh),
  `kensac-box` (kensac's install.sh), `twelve-vg` (twelve-box with valgrind), and
  `twelve-perf` (Alpine's perf). `docker build -t <name> <dir>` builds one;
  `docker network create twelve-net` once. `vbox/` builds `FROM twelve-box`.
- `build.sh`: builds the entry inside twelve-box, with the package cache in
  `goose-home4/`. `build-gh.sh GH_DIR REF` builds it with the goose-http checkout
  `$G/GH_DIR` mounted in the cache as ref `REF`, for a `server.goose` that imports
  `github.com/kaitk/goose-http@REF` before goose fetches that ref itself.
- `check.sh`: the challenge's `test/test.sh`, its 42 checks, against the built entry.
- `bench.sh plod|kensac VUS SCALE [DURATION]`: one k6 run against a 1-CPU, 2 GB server
  container; prints req/s, p95/p99, µs a request (user, kernel) from the cgroup, and
  memory peak. `NOFILE` sets the descriptor limit (65,535), and `CPUS` the server's
  CPUs (1): k6 from one container can't saturate a whole CPU, so a test of the server
  past its capacity holds it to less, such as `CPUS=0.4`.
- `ab.sh ROUNDS VARIANT...`: `bench.sh plod 4000 20` for each `bins/VARIANT` in turn,
  and each one's lowest µs a request. Copy a build's `bin/server` into `bins/` first.
- `count.sh VARIANT...`: `io_uring_enter`, `pread64`, `pwrite64`, and context switches
  a request, by `perf stat`: counts that a busy machine doesn't move.
- `perf.sh plod|kensac`: perf samples of the server, kernel included, into `perf/`.
- `profile.sh`: the server under callgrind, 300 users for 40 s, into `cg/`.
- `load-fast.js`: the challenge's `bench/load.js` with think times divided by `SCALE`;
  copy it and the seed's `tokens.json` into `k6/`. k6 from one container tops out
  near 19,000 req/s and 28,000 connections.
- kensac: copy `submissions/rust-iouring-kensac` from the challenge into `kensac/` and
  build it with `docker run --rm -v $PWD/kensac:/app -w /app kensac-box bash build.sh`.

`box/install.sh` is the entry's at the time it was copied; rebuild the image from the
entry's current `install.sh` when that changes.
