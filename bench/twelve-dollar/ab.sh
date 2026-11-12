#!/usr/bin/env bash
S=$(cd "$(dirname "$0")" && pwd); G=${G:?set G to the folder that holds the twelve-dollar-plod and goose-sqlite checkouts}
# ab.sh ROUNDS VARIANT...: runs bench.sh plod 4000 20 with each bins/VARIANT in turn,
# ROUNDS times, and prints each variant's runs and its lowest µs a request.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
B=$G/twelve-dollar-plod/submissions/goose-plod-kaitk/bin/server
rounds=$1; shift
cp $B $S/bins/.current
for r in $(seq $rounds); do
  for v in "$@"; do
    cp $S/bins/$v $B
    echo "$v $($S/bench.sh plod ${VUS:-4000} 20 ${DUR:-60s})" | tee -a $S/bins/ab.log
  done
done
cp $S/bins/.current $B
for v in "$@"; do
  grep "^$v plod" $S/bins/ab.log | tail -$rounds | sed -E 's/.* ([0-9.]+) µs\/req \(user ([0-9.]+), kernel ([0-9.]+)\).*/\1 \2 \3/' | sort -n |
    awk -v v=$v '{a[NR]=$0} END {printf "%s: min %s; all:", v, a[1]; for (i=1;i<=NR;i++) printf " [%s]", a[i]; print ""}'
done
