#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

CANDIDATE_PATH="${1:-./chess-static}"
BASELINE_PATH="${2:-./chess-static}"
RUN_TAG="${RUN_TAG:-nightly-$(date -u +%Y%m%d-%H%M%S)}"

if [[ ! -x "$CANDIDATE_PATH" ]]; then
    echo "ERROR: candidate not executable: $CANDIDATE_PATH"
    exit 2
fi

if [[ ! -x "$BASELINE_PATH" ]]; then
    echo "ERROR: baseline not executable: $BASELINE_PATH"
    exit 3
fi

echo "[nightly] Candidate: $CANDIDATE_PATH"
echo "[nightly] Baseline:  $BASELINE_PATH"
echo "[nightly] Run tag:   $RUN_TAG"

echo "[nightly] Step 1/2: strength gate"
BUILD_BIN="${BUILD_BIN:-0}" ./utils/strength_gate.sh "$CANDIDATE_PATH"

echo "[nightly] Step 2/2: A/B compare + report"
REPORT_TSV="${REPORT_TSV:-tests/reports/ab_history.tsv}" \
REPORT_MD="${REPORT_MD:-tests/reports/ab_latest.md}" \
STRICT="${STRICT:-1}" \
RUN_TAG="$RUN_TAG" \
./utils/ab_compare.sh "$CANDIDATE_PATH" "$BASELINE_PATH"

# Volitelny krok (dlhy, default vypnuty): matchup vs Arasan 26.
if [[ "${ARASAN_MATCHUP:-0}" == "1" ]]; then
    echo "[nightly] Step 3/3: matchup vs Arasan (GAMES=${MATCHUP_GAMES:-100}, TC=${MATCHUP_TC:-10+0.1})"
    ENGINE="$CANDIDATE_PATH" \
    GAMES="${MATCHUP_GAMES:-100}" TC="${MATCHUP_TC:-10+0.1}" \
    RUN_TAG="$RUN_TAG" \
    ./utils/arasan_matchup.sh "${MATCHUP_GAMES:-100}" "${MATCHUP_TC:-10+0.1}"
else
    echo "[nightly] Step 3/3: matchup vs Arasan preskoceny (ARASAN_MATCHUP=${ARASAN_MATCHUP:-0})"
fi

echo "[nightly] PASS"
