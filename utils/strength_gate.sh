#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

RECORD_BASELINE=0
if [[ "${1:-}" == "--record-baseline" ]]; then
    RECORD_BASELINE=1
    shift
fi

ENGINE_PATH="${1:-./chess-static}"

BUILD_BIN="${BUILD_BIN:-1}"
BF_DEPTH="${BF_DEPTH:-14}"
ARASAN_DEPTH="${ARASAN_DEPTH:-6}"
BF_MIN_HITS="${BF_MIN_HITS:-}"
ARASAN_MIN_HITS="${ARASAN_MIN_HITS:-}"
BF_TIMEOUT_SEC="${BF_TIMEOUT_SEC:-180}"
ARASAN_TIMEOUT_SEC="${ARASAN_TIMEOUT_SEC:-900}"
BASELINE_FILE="${BASELINE_FILE:-tests/suites/strength_baseline.env}"

if [[ -z "$BF_MIN_HITS" || -z "$ARASAN_MIN_HITS" ]]; then
    if [[ -f "$BASELINE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$BASELINE_FILE"
    fi
fi

BF_MIN_HITS="${BF_MIN_HITS:-1}"
ARASAN_MIN_HITS="${ARASAN_MIN_HITS:-17}"

if [[ ! -x "$ENGINE_PATH" ]]; then
    echo "ERROR: Engine not executable: $ENGINE_PATH"
    exit 2
fi

if [[ "$BUILD_BIN" == "1" ]]; then
    echo "[1/4] Building chess-static"
    make chess-static >/dev/null
fi

echo "[2/4] Running regression"
ENGINE_PATH="$ENGINE_PATH" bash tests/regression.sh >/dev/null

run_suite() {
    local suite_file="$1"
    local depth="$2"
    local timeout_sec="$3"
    local out_file
    local line
    local score

    out_file="$(mktemp)"
    timeout "${timeout_sec}s" sh -c "printf 'uci\nsuite ${suite_file} ${depth}\nquit\n' | '$ENGINE_PATH' --uci" >"$out_file" 2>&1 || {
        echo "ERROR: suite timed out or failed: $suite_file"
        tail -n 20 "$out_file" || true
        rm -f "$out_file"
        exit 3
    }

    line="$(grep 'suite result' "$out_file" | tail -n 1 || true)"
    if [[ -z "$line" ]]; then
        echo "ERROR: No suite result line for: $suite_file"
        tail -n 20 "$out_file" || true
        rm -f "$out_file"
        exit 4
    fi

    score="$(printf '%s' "$line" | sed -n 's/.*score=\([0-9]\+\/[0-9]\+\).*/\1/p')"
    if [[ -z "$score" ]]; then
        echo "ERROR: Could not parse score for: $suite_file"
        echo "$line"
        rm -f "$out_file"
        exit 5
    fi

    rm -f "$out_file"
    echo "$score"
}

echo "[3/4] Running BF suite"
bf_score="$(run_suite tests/suites/bf_regression.fenbm "$BF_DEPTH" "$BF_TIMEOUT_SEC")"
bf_hits="${bf_score%/*}"
bf_total="${bf_score#*/}"

echo "[4/4] Running Arasan suite"
arasan_score="$(run_suite tests/suites/external/arasan2026.epd "$ARASAN_DEPTH" "$ARASAN_TIMEOUT_SEC")"
arasan_hits="${arasan_score%/*}"
arasan_total="${arasan_score#*/}"

echo ""
echo "Gate summary"
echo "- BF depth ${BF_DEPTH}: ${bf_hits}/${bf_total} (min ${BF_MIN_HITS})"
echo "- Arasan depth ${ARASAN_DEPTH}: ${arasan_hits}/${arasan_total} (min ${ARASAN_MIN_HITS})"

if [[ "$RECORD_BASELINE" == "1" ]]; then
    cat >"$BASELINE_FILE" <<EOF
BF_MIN_HITS=${bf_hits}
ARASAN_MIN_HITS=${arasan_hits}
BF_DEPTH=${BF_DEPTH}
ARASAN_DEPTH=${ARASAN_DEPTH}
EOF
    echo "BASELINE SAVED: $BASELINE_FILE"
    exit 0
fi

if (( bf_hits < BF_MIN_HITS )); then
    echo "FAIL: BF gate failed"
    exit 10
fi

if (( arasan_hits < ARASAN_MIN_HITS )); then
    echo "FAIL: Arasan gate failed"
    exit 11
fi

echo "PASS: strength gate passed"
