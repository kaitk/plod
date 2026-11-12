#!/usr/bin/env bash
S=$(cd "$(dirname "$0")" && pwd); G=${G:?set G to the folder that holds the twelve-dollar-plod and goose-sqlite checkouts}
# build-gh.sh GH_DIR REF [LINES]: build.sh's build with the goose-http checkout ../GH_DIR mounted in
# the package cache as goose-http's ref REF, for a server.goose that imports
# github.com/kaitk/goose-http@REF (Goose warns that Plod asks for another ref, and takes the root's).
docker run --rm -v $G/twelve-dollar-plod:/work/twelve-dollar-plod -v $G/goose-sqlite-query:/work/goose-sqlite-query \
  -v $S/goose-home4:/home/deploy/.goose -v $G/$1:/home/deploy/.goose/pkg/github.com/kaitk/goose-http/$2:ro \
  -w /work/twelve-dollar-plod twelve-box bash submissions/goose-plod-kaitk/build.sh 2>&1 | grep -v "^  in fn\|deprecated\|^extern\|^\^\|^$" | tail -${3:-1}
