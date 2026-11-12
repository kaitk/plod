#!/usr/bin/env bash
S=$(cd "$(dirname "$0")" && pwd); G=${G:?set G to the folder that holds the twelve-dollar-plod and goose-sqlite checkouts}
# perf.sh plod|kensac [VUS SCALE SECONDS]: a k6 run as bench.sh's, with perf sampling
# the server's processes (cpu-clock, call graphs, kernel included) for SECONDS once the
# ramp is over; writes perf/<which>.data and perf/<which>.txt.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
which=$1 vus=${2:-4000} scale=${3:-20} secs=${4:-20}
docker rm -f srv >/dev/null 2>&1 || true
common=(--name srv --network twelve-net --cpus=1 --memory=2g --memory-swap=2g --ulimit nofile=65535:65535
        --security-opt seccomp=unconfined -e JWT_SECRET=twelve-dollar-challenge -e HOST=0.0.0.0 -e PORT=3000
        -e SQLITE_PATH=/tmp/db/feed.db -v $G/twelve-dollar-plod/seed:/seed:ro)
case $which in
plod)   docker run -d "${common[@]}" -e PROCS=${PROCS:-3} -v $G/twelve-dollar-plod:/work/twelve-dollar-plod:ro twelve-box \
          bash -c 'mkdir -p /tmp/db && cp /seed/feed.db /tmp/db/ && exec bash /work/twelve-dollar-plod/submissions/goose-plod-kaitk/start.sh' >/dev/null ;;
kensac) docker run -d "${common[@]}" -v $S/kensac:/app:ro kensac-box \
          bash -c 'mkdir -p /tmp/db && cp /seed/feed.db /tmp/db/ && exec bash /app/start.sh' >/dev/null ;;
esac
for _ in $(seq 60); do docker exec srv bash -c 'exec 3<>/dev/tcp/127.0.0.1/3000' 2>/dev/null && break; sleep 0.5; done
docker run -d --name k6 --rm --network twelve-net -v $S/k6:/k6 -w /k6 grafana/k6:1.3.0 run -q \
  -e BASE_URL=http://srv:3000 -e VUS=$vus -e SCALE=$scale -e RAMP_UP=15s -e DURATION=$((secs + 15))s -e TOKENS=/k6/tokens.json load-fast.js >/dev/null
sleep 22
docker run --rm --privileged --pid=container:srv -v $S/perf:/perf twelve-perf bash -c \
  "pids=\$(pgrep server | paste -sd, -); perf record -q -g -F 1999 -p \$pids -o /perf/$which.data -- sleep $secs >/dev/null 2>&1;
   perf report -i /perf/$which.data --no-children --stdio --sort sym -g none --percent-limit 0.4 2>/dev/null | grep -v '^#' | grep -v '^$' > /perf/$which.txt;
   perf report -i /perf/$which.data --no-children --stdio --sort dso -g none 2>/dev/null | grep -v '^#' | grep -v '^$' | head -12 >> /perf/$which.txt"
docker wait k6 >/dev/null 2>&1 || true
docker rm -f srv >/dev/null
head -70 $S/perf/$which.txt
