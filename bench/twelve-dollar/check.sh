#!/usr/bin/env bash
S=$(cd "$(dirname "$0")" && pwd); G=${G:?set G to the folder that holds the twelve-dollar-plod and goose-sqlite checkouts}
# check.sh: the challenge's test/test.sh (its 42 checks) against the built entry, PROCS processes
# (1 by default), on a fresh copy of the seed, in twelve-box with io_uring allowed.
docker run --rm --security-opt seccomp=unconfined --ulimit nofile=65535:65535 -e PROCS=${PROCS:-1} \
  -e JWT_SECRET=twelve-dollar-challenge -e HOST=127.0.0.1 -e PORT=3000 -e SQLITE_PATH=/tmp/db/feed.db \
  -v $G/twelve-dollar-plod:/work/twelve-dollar-plod:ro twelve-box bash -c '
    mkdir -p /tmp/db && cp /work/twelve-dollar-plod/seed/feed.db /tmp/db/
    bash /work/twelve-dollar-plod/submissions/goose-plod-kaitk/start.sh > /tmp/server.log 2>&1 &
    for _ in $(seq 60); do curl -m 2 -sf http://127.0.0.1:3000/health >/dev/null && break; sleep 0.5; done
    bash /work/twelve-dollar-plod/test/test.sh http://127.0.0.1:3000 2>&1 | tail -${LINES:-4}; rc=${PIPESTATUS[0]}
    echo "== server log"; tail -5 /tmp/server.log; exit $rc'
