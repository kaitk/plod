# Measurement notes

`bench/all.sh` session `2026-10-25T2003-Tiamat` measured Plod `5c6b3a1` (`v0.5.9`
with docs and HttpArena entry changes only) and goose-http `35805477` (`v0.5.12`) with
Goose `v2026.3`. The machine passed the idle check at once, a 1-minute load of 0.52 and
Windows CPU at 2%. Plod's tests passed in the session, with the Linux Node 24 and
`GOOSE_CC=clang` of `docs/development.md`'s WSL setup. goose-http's tests failed in
`test-drain.sh`: `test-drain-turns.py`'s epoll half got `ConnectionResetError` on
its first read, after the uring half passed. Three reruns afterwards passed. Its
fixture doesn't call `http::stop_on_signals`, so the uring server's listener can
outlive it on the shared port (goose-http's `docs/known-issues.md`, "A killed io_uring
server's listener outlives it"). All benchmark servers passed the workload checks.

viltrum ran straight after the session, against the same goose-http checkout, into
`../2026-10-25T2003-rest-Tiamat-viltrum/`:

```sh
RATE_A=100000 RATE_B=24000 RATE_C=1700 SERVERS=viltrum EXTRA=viltrum bench/rest.sh run
```

Machine: Tiamat, Ryzen 7 5800X3D, 8 cores and 16 logical CPUs, Windows 11,
WSL2 Ubuntu 26.04.1, kernel 6.18.54.1-microsoft-standard-WSL2, gcc 15.2.0.
Four workers on CPUs 0-3; wrk 4.1.0 on CPUs 4-15 with 8 threads and 256 connections.
Each cell uses a fresh server, 5 s warm-up and three interleaved 15 s runs.
Uploads alone use 1 thread and 32 connections. Fixed rates are A 100,000/s,
B 24,000/s and C 1,700/s. `env.txt` records the remaining settings.

The summaries retain the ranges; the uploads-alone medians below retain the precision
of `d-<server>-alone-r<run>.uploads.wrk`'s `Requests/sec` lines:

| Server | Three runs, uploads/s | Median |
|---|---|---:|
| goose-uring | 1,113.12; 1,108.63; 1,131.24 | 1,113.12 |
| goose-epoll | 1,139.10; 1,151.00; 1,139.43 | 1,139.43 |
| goose-uring-plod | 1,086.91; 1,102.75; 1,118.49 | 1,102.75 |
| goose-epoll-plod | 1,133.57; 1,112.22; 1,112.88 | 1,112.88 |

`count.txt` comes from `bench/rest.sh count`, as on 2026-10-20: one epoll worker on
CPU 0, h2load on CPUs 4-15, 256 connections, 16 requests in flight on each, 10 million
requests, one run per case.

Every saturation rate on A to C is lower than in session `2026-10-20T0854-Tiamat`:
goose-http alone by 1.5-5.8% on io_uring and 3.6-6.6% on epoll, and Plod by 2.7-6.6%
and 3.7-5.5%. The user instructions per request in `count.txt` are within 2.0% of
that session's in every case but tier M, so the rates fall with the machine's drift,
as on 2026-10-22. Tier M's 5,324.8 user instructions per request are 0.0% above the
2026-10-22 session's 5,323.9 and 7.2% above 2026-10-20's 4,968.4.

viltrum on tier C serialized reached 133-151 of 153 bookings a second, 50 of 51
clients, and 87-98% of each route's rate, with p99 0.5-5.6 s, though its saturation
rate there, 2.3 K a second, is above the fixed rate's total of 1,700. Its peak RSS on B templated, 927 MB, is more than twice the 423 MB of task
061's one-round run of 2026-10-24.
