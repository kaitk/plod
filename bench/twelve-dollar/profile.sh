#!/usr/bin/env bash
S=$(cd "$(dirname "$0")" && pwd); G=${G:?set G to the folder that holds the twelve-dollar-plod and goose-sqlite checkouts}
# profile.sh: one server process under callgrind, 300 fast users for 40 s; writes $S/cg/cg.out.1
rm -f $S/cg/cg.out*
docker rm -f srv >/dev/null 2>&1
docker run -d --name srv --network twelve-net --security-opt seccomp=unconfined --ulimit nofile=65535:65535 -e JWT_SECRET=twelve-dollar-challenge -e HOST=0.0.0.0 -e PORT=3000 -e SQLITE_PATH=/tmp/db/feed.db -v $G/twelve-dollar-plod/seed:/seed:ro -v $G/twelve-dollar-plod:/work/twelve-dollar-plod:ro -v $S/cg:/cg twelve-vg bash -c 'mkdir -p /tmp/db && cp /seed/feed.db /tmp/db/ && cd /cg && exec valgrind --tool=callgrind --callgrind-out-file=/cg/cg.out /work/twelve-dollar-plod/submissions/goose-plod-kaitk/bin/server' >/dev/null
sleep 8
docker run --rm --network twelve-net -v $S/k6:/k6 -w /k6 grafana/k6:1.3.0 run -q --summary-export=/k6/cgsum.json -e BASE_URL=http://srv:3000 -e VUS=300 -e SCALE=20 -e RAMP_UP=5s -e DURATION=40s -e TOKENS=/k6/tokens.json load-fast.js >/dev/null 2>&1
echo "requests: $(jq '.metrics.http_reqs.count' $S/k6/cgsum.json)"
docker exec srv callgrind_control -d; for i in $(seq 60); do [ -s $S/cg/cg.out.1 ] && break; sleep 1; done; sleep 2
docker rm -f srv >/dev/null
docker run --rm -v $S/cg:/cg twelve-vg bash -c 'callgrind_annotate /cg/cg.out.1 2>/dev/null | sed -n 20,60p; callgrind_annotate --tree=caller /cg/cg.out.1 > /cg/tree.txt 2>/dev/null' | cut -c1-130
