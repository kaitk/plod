#!/usr/bin/env bash
# Runs once as root on a clean Ubuntu 24.04: a C compiler, liburing, git (goose
# build fetches the packages server.goose declares, at their tags), and the
# Goose compiler from its official release, checked against its SHA-256. The
# release has no archive for Linux on arm64, so there its tag is built from
# source.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential liburing-dev git curl ca-certificates

GOOSE_RELEASE=v2026.4
GOOSE_SHA256=559ad7572df89fcd1273512d8679528bcdf876c252ec1f31608d3808b24125b3

case "$(uname -m)" in
x86_64)
    dir=/opt/goose-$GOOSE_RELEASE-linux-x64
    if [[ ! -x $dir/goose ]]; then
        archive=$(mktemp)
        trap 'rm -f "$archive"' EXIT
        curl -fsSL --retry 3 -o "$archive" \
            "https://github.com/aardappel/goose/releases/download/$GOOSE_RELEASE/goose-$GOOSE_RELEASE-linux-x64.tar.gz"
        echo "$GOOSE_SHA256  $archive" | sha256sum -c -
        tar -xzf "$archive" -C /opt
    fi
    ln -sf "$dir/goose" /usr/local/bin/goose
    ;;
*)
    apt-get install -y --no-install-recommends cmake ninja-build g++
    dir=/opt/goose-$GOOSE_RELEASE
    if [[ ! -x $dir/build/goose ]]; then
        rm -rf "$dir"
        git clone -q --depth 1 --branch "$GOOSE_RELEASE" https://github.com/aardappel/goose.git "$dir"
        cmake -S "$dir" -B "$dir/build" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
        cmake --build "$dir/build" >/dev/null
    fi
    ln -sf "$dir/build/goose" /usr/local/bin/goose
    ;;
esac
goose version
