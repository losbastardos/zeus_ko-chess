#!/usr/bin/env bash
# ============================================================
# Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
# Vsetky prava vyhradene / All rights reserved.
# ============================================================

set -euo pipefail

cd "$(dirname "$0")/.."

ENGINE_PATH="${ENGINE_PATH:-./chess-static}"

if [[ ! -x "$ENGINE_PATH" ]]; then
    make chess-static >/dev/null
fi

if [[ ! -x "$ENGINE_PATH" ]]; then
    echo "ERROR: Engine not executable: $ENGINE_PATH" >&2
    exit 2
fi

backup="$(mktemp)"
cp chess.ini "$backup"
cleanup() {
    cp "$backup" chess.ini
    rm -f "$backup"
}
trap cleanup EXIT

sed -i 's/^language=.*/language=en/' chess.ini

out1="$(mktemp)"
printf '2\n\nexit\n' | "$ENGINE_PATH" >"$out1"
grep -q 'Invalid input' "$out1"
rm -f "$out1"

out2="$(mktemp)"
printf '1\n1\n2\nexit\n' | "$ENGINE_PATH" >"$out2"
grep -q 'You play: Black' "$out2"
grep -q 'h   g   f   e   d   c   b   a' "$out2"
rm -f "$out2"

echo 'regression tests passed'
