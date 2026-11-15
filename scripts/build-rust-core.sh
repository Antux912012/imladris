#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

export PATH="$PATH:/usr/lib/sdk/rust-stable/bin:$HOME/.cargo/bin"

SRC_ROOT="$1"
OUT_LIB="$2"
case "$OUT_LIB" in
  /*) ;;
  *) OUT_LIB="$PWD/$OUT_LIB" ;;
esac
CRATE_DIR="$SRC_ROOT/rust/imladris_core"
TARGET_DIR="$CRATE_DIR/target"

OFFLINE_FLAG=""
if [ -d "$CRATE_DIR/vendor" ]; then
  OFFLINE_FLAG="--offline"
fi

cd "$CRATE_DIR"
cargo build --release $OFFLINE_FLAG --target-dir "$TARGET_DIR"
cp "$TARGET_DIR/release/libimladris_core.a" "$OUT_LIB"
