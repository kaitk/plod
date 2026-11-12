#!/usr/bin/env bash
S=$(cd "$(dirname "$0")" && pwd); G=${G:?set G to the folder that holds the twelve-dollar-plod and goose-sqlite checkouts}
docker run --rm -v $G/twelve-dollar-plod:/work/twelve-dollar-plod -v $G/goose-sqlite-query:/work/goose-sqlite-query -v $S/goose-home4:/home/deploy/.goose -w /work/twelve-dollar-plod twelve-box bash submissions/goose-plod-kaitk/build.sh 2>&1 | grep -v "^  in fn" | tail -${1:-1}
