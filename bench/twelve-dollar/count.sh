#!/usr/bin/env bash
S=$(cd "$(dirname "$0")" && pwd); G=${G:?set G to the folder that holds the twelve-dollar-plod and goose-sqlite checkouts}
# count.sh VARIANT...: for each bins/VARIANT, one process under the bench's load (4,000 users,
# SCALE=20), perf stat over 20 s of the steady state: io_uring_enter calls, context switches,
# and task-clock, each per request (requests from the cgroup-free k6 rate over the window).
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
B=$G/twelve-dollar-plod/submissions/goose-plod-kaitk/bin/server
cp $B $S/bins/.current
for v in "$@"; do
  cp $S/bins/$v $B
  docker rm -f srv k6 >/dev/null 2>&1 || true
  docker run -d --name srv --network twelve-net --cpus=1 --memory=2g --ulimit nofile=65535:65535 --security-opt seccomp=unconfined \
    -e JWT_SECRET=twelve-dollar-challenge -e HOST=0.0.0.0 -e PORT=3000 -e SQLITE_PATH=/tmp/db/feed.db -e PROCS=${PROCS:-1} \
    -v $G/twelve-dollar-plod/seed:/seed:ro -v $G/twelve-dollar-plod:/work/twelve-dollar-plod:ro twelve-box \
    bash -c 'mkdir -p /tmp/db && cp /seed/feed.db /tmp/db/ && exec bash /work/twelve-dollar-plod/submissions/goose-plod-kaitk/start.sh' >/dev/null
  for _ in $(seq 60); do docker exec srv bash -c 'exec 3<>/dev/tcp/127.0.0.1/3000' 2>/dev/null && break; sleep 0.5; done
  docker run -d --name k6 --rm --network twelve-net -v $S/k6:/k6 -w /k6 grafana/k6:1.3.0 run -q --summary-export=/k6/count.json \
    -e BASE_URL=http://srv:3000 -e VUS=4000 -e SCALE=20 -e RAMP_UP=15s -e DURATION=30s -e TOKENS=/k6/tokens.json load-fast.js >/dev/null
  sleep 20
  out=$(docker run --rm --privileged --pid=container:srv twelve-perf bash -c \
    'perf stat -x, -e syscalls:sys_enter_io_uring_enter,syscalls:sys_enter_pread64,syscalls:sys_enter_pwrite64,context-switches -p $(pgrep server | paste -sd, -) -- sleep 20 2>&1 >/dev/null')
  docker wait k6 >/dev/null 2>&1 || true
  rate=$(jq '.metrics.http_reqs.rate' $S/k6/count.json)
  docker rm -f srv >/dev/null
  echo "$out" | awk -F, -v v=$v -v rate=$rate '{c[$3]=$1} END {n=rate*20; printf "%s: %.0f req/s; per request: %.3f io_uring_enter, %.3f pread64, %.3f pwrite64, %.3f context switches\n", v, rate, c["syscalls:sys_enter_io_uring_enter"]/n, c["syscalls:sys_enter_pread64"]/n, c["syscalls:sys_enter_pwrite64"]/n, c["context-switches"]/n}'
done
cp $S/bins/.current $B
