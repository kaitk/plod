#!/usr/bin/env bash
# Runs once as root on a clean Ubuntu 24.04: a C compiler, curl/unzip, and the official Rust
# 1.94.0 standalone toolchain (sha256-checked) installed into /usr/local, so the unprivileged
# build user finds cargo on its PATH.
set -euo pipefail
apt-get update
apt-get install -y build-essential curl ca-certificates unzip xz-utils
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) SHA=e8fa4185f3ef6ae32725ff638b1ecdbff28f5d651dc0b3111e2539350d03b15a ;;
  aarch64) SHA=c6fd6d1c925ed986df3b2c0b89bbc90ce15afb62e4d522a054e7d50c856b3c1a ;;
  *) echo "unsupported architecture $ARCH"; exit 1 ;;
esac
PKG="rust-1.94.0-$ARCH-unknown-linux-gnu"
TMP="$(mktemp -d)"
curl -fsSL --retry 3 -o "$TMP/$PKG.tar.xz" "https://static.rust-lang.org/dist/$PKG.tar.xz"
echo "$SHA  $TMP/$PKG.tar.xz" | sha256sum -c -
tar -xJf "$TMP/$PKG.tar.xz" -C "$TMP"
"$TMP/$PKG/install.sh" --prefix=/usr/local --components=rustc,cargo,"rust-std-$ARCH-unknown-linux-gnu"
rm -rf "$TMP"
cargo --version
