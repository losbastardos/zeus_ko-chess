#!/usr/bin/env bash

set -euo pipefail

CANDIDATE_PATH="${1:-./chess-static}"
BASELINE_PATH="${2:-./chess-static}"
CASES_FILE="${3:-tests/suites/perft_parity_cases.txt}"

if [[ ! -x "$CANDIDATE_PATH" ]]; then
    echo "ERROR: candidate not executable: $CANDIDATE_PATH"
    exit 2
fi

if [[ ! -x "$BASELINE_PATH" ]]; then
    echo "ERROR: baseline not executable: $BASELINE_PATH"
    exit 2
fi

if [[ ! -f "$CASES_FILE" ]]; then
    echo "ERROR: cases file not found: $CASES_FILE"
    exit 2
fi

run_perft() {
    local engine="$1"
    local depth="$2"
    local position="$3"
    local out
    local nodes

    out=$(printf "position %s\nperft %s\nquit\n" "$position" "$depth" | "$engine" --uci 2>/dev/null || true)
    nodes=$(printf "%s\n" "$out" | awk '/^[0-9]+$/ {n=$1} END{if (n == "") exit 1; print n}') || return 1
    printf "%s" "$nodes"
}

echo "Perft parity"
echo "- candidate: $CANDIDATE_PATH"
echo "- baseline:  $BASELINE_PATH"
echo "- cases:     $CASES_FILE"

total=0
ok=0

while IFS=';' read -r label depth position; do
    [[ -z "${label}" ]] && continue
    [[ "${label:0:1}" == "#" ]] && continue

    total=$((total + 1))

    cand_nodes="$(run_perft "$CANDIDATE_PATH" "$depth" "$position")" || {
        echo "FAIL: candidate perft parse error case=$label depth=$depth"
        exit 1
    }

    base_nodes="$(run_perft "$BASELINE_PATH" "$depth" "$position")" || {
        echo "FAIL: baseline perft parse error case=$label depth=$depth"
        exit 1
    }

    if [[ "$cand_nodes" != "$base_nodes" ]]; then
        echo "MISMATCH: case=$label depth=$depth candidate=$cand_nodes baseline=$base_nodes"
        exit 1
    fi

    ok=$((ok + 1))
    echo "OK: case=$label depth=$depth nodes=$cand_nodes"
done < "$CASES_FILE"

echo "Summary: $ok/$total cases identical"
