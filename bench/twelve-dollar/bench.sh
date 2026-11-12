#!/usr/bin/env bash
S=$(cd "$(dirname "$0")" && pwd); G=${G:?set G to the folder that holds the twelve-dollar-plod and goose-sqlite checkouts}
# bench.sh plod|kensac VUS SCALE [DURATION]: one k6 run against a 1-CPU, 2 GB server
# container (NOFILE its descriptor limit); prints k6's summary lines, CPU µs per request, and memory peak.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
which=$1 vus=$2 scale=$3 dur=${4:-60s}
docker rm -f srv >/dev/null 2>&1 || true
common=(--name srv --network twelve-net --cpus=1 --memory=2g --memory-swap=2g --ulimit nofile=${NOFILE:-65535}:${NOFILE:-65535}
        --security-opt seccomp=unconfined -e JWT_SECRET=twelve-dollar-challenge -e HOST=0.0.0.0 -e PORT=3000
        -e SQLITE_PATH=/tmp/db/feed.db -v $G/twelve-dollar-plod/seed:/seed:ro)
case $which in
plod)   docker run -d "${common[@]}" -e PROCS=${PROCS:-6} -v $G/twelve-dollar-plod:/work/twelve-dollar-plod:ro twelve-box \
          bash -c 'mkdir -p /tmp/db && cp /seed/feed.db /tmp/db/ && exec bash /work/twelve-dollar-plod/submissions/goose-plod-kaitk/start.sh' >/dev/null ;;
kensac) docker run -d "${common[@]}" -v $S/kensac:/app:ro kensac-box \
          bash -c 'mkdir -p /tmp/db && cp /seed/feed.db /tmp/db/ && exec bash /app/start.sh' >/dev/null ;;
esac
for _ in $(seq 60); do docker exec srv bash -c 'exec 3<>/dev/tcp/127.0.0.1/3000' 2>/dev/null && break; sleep 0.5; done
sleep 1
read u0 us0 sy0 < <(docker exec srv awk '/^usage_usec/{u=$2} /^user_usec/{us=$2} /^system_usec/{sy=$2} END{print u, us, sy}' /sys/fs/cgroup/cpu.stat)
docker run --rm --network twelve-net -v $S/k6:/k6 -w /k6 grafana/k6:1.3.0 run -q --summary-export=/k6/summary.json \
  -e BASE_URL=http://srv:3000 -e LIKE_PROB=${LIKE_PROB:-0.15} -e POST_PROB=${POST_PROB:-0.02} -e VUS=$vus -e SCALE=$scale -e RAMP_UP=15s -e DURATION=$dur -e TOKENS=/k6/tokens.json \
  load-fast.js >$S/k6/out.txt 2>&1 || true
read u1 us1 sy1 < <(docker exec srv awk '/^usage_usec/{u=$2} /^user_usec/{us=$2} /^system_usec/{sy=$2} END{print u, us, sy}' /sys/fs/cgroup/cpu.stat)
peak=$(docker exec srv cat /sys/fs/cgroup/memory.peak)
reqs=$(jq '.metrics.http_reqs.count' $S/k6/summary.json)
jq -r --arg w "$which" --arg v "$vus" --arg s "$scale" --argjson cpu $((u1 - u0)) --argjson usr $((us1 - us0)) --argjson sys $((sy1 - sy0)) --argjson peak $peak '
  .metrics as $m | "\($w) vus=\($v) scale=\($s): \($m.http_reqs.rate|floor) req/s, p95 \($m.http_req_duration["p(95)"]*10|round/10) ms, p99 \($m.http_req_duration["p(99)"]*10|round/10) ms, max \($m.http_req_duration.max|round) ms, failed \($m.http_req_failed.value*10000|round/100) %, \($cpu / $m.http_reqs.count * 10|round/10) µs/req (user \($usr / $m.http_reqs.count * 10|round/10), kernel \($sys / $m.http_reqs.count * 10|round/10)), peak \($peak/1048576|round) MiB"' $S/k6/summary.json
docker rm -f srv >/dev/null
