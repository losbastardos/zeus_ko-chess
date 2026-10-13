#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

CANDIDATE_PATH="${1:-}"
BASELINE_PATH="${2:-./chess-static}"

if [[ -z "$CANDIDATE_PATH" ]]; then
    echo "Usage: $0 <candidate_engine> [baseline_engine]"
    exit 2
fi

BF_DEPTH="${BF_DEPTH:-14}"
ARASAN_DEPTH="${ARASAN_DEPTH:-6}"
BF_TIMEOUT_SEC="${BF_TIMEOUT_SEC:-600}"
ARASAN_TIMEOUT_SEC="${ARASAN_TIMEOUT_SEC:-900}"
STRICT="${STRICT:-0}"
CAND_THREADS="${CAND_THREADS:-1}"
BASE_THREADS="${BASE_THREADS:-1}"
REPORT_TSV="${REPORT_TSV:-}"
REPORT_MD="${REPORT_MD:-}"
RUN_TAG="${RUN_TAG:-}"

if [[ -z "$RUN_TAG" ]]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_head="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
        if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
            RUN_TAG="${git_head}-dirty"
        else
            RUN_TAG="$git_head"
        fi
    else
        RUN_TAG="manual"
    fi
fi

for engine in "$CANDIDATE_PATH" "$BASELINE_PATH"; do
    if [[ ! -x "$engine" ]]; then
        echo "ERROR: Engine not executable: $engine"
        exit 3
    fi
done

run_suite() {
    local engine="$1"
    local suite_file="$2"
    local depth="$3"
    local timeout_sec="$4"
    local threads="$5"
    local suite_path
    local out_file
    local line
    local hits
    local total
    local nodes
    local time_ms

    suite_path="$suite_file"
    if [[ "$suite_path" != /* ]]; then
        suite_path="$PWD/$suite_path"
    fi

    out_file="$(mktemp)"
    timeout "${timeout_sec}s" sh -c "printf 'uci\nsetoption name Threads value ${threads}\nisready\nsuite ${suite_path} ${depth}\nquit\n' | '$engine' --uci" >"$out_file" 2>&1 || {
        echo "ERROR: suite failed: $suite_file ($engine)"
        tail -n 20 "$out_file" || true
        rm -f "$out_file"
        exit 4
    }

    line="$(grep 'suite result' "$out_file" | tail -n 1 || true)"
    if [[ -z "$line" ]]; then
        echo "ERROR: suite result not found: $suite_file ($engine)"
        tail -n 20 "$out_file" || true
        rm -f "$out_file"
        exit 5
    fi

    hits="$(printf '%s' "$line" | sed -n 's/.*hits=\([0-9]\+\).*/\1/p')"
    total="$(printf '%s' "$line" | sed -n 's/.*score=[0-9]\+\/\([0-9]\+\).*/\1/p')"
    nodes="$(printf '%s' "$line" | sed -n 's/.*nodes=\([0-9]\+\).*/\1/p')"
    time_ms="$(printf '%s' "$line" | sed -n 's/.*time_ms=\([0-9]\+\).*/\1/p')"

    rm -f "$out_file"

    if [[ -z "$hits" || -z "$total" ]]; then
        echo "ERROR: parse failure: $suite_file ($engine)"
        echo "$line"
        exit 6
    fi

    echo "$hits $total ${nodes:-0} ${time_ms:-0}"
}

echo "Running A/B suites"
echo "- candidate: $CANDIDATE_PATH"
echo "- baseline:  $BASELINE_PATH"
echo "- threads:   candidate=$CAND_THREADS baseline=$BASE_THREADS"

suite_out="$(run_suite "$CANDIDATE_PATH" tests/suites/bf_regression.fenbm "$BF_DEPTH" "$BF_TIMEOUT_SEC" "$CAND_THREADS")"
read -r cand_bf cand_bf_total cand_bf_nodes cand_bf_time <<<"$suite_out"

suite_out="$(run_suite "$BASELINE_PATH" tests/suites/bf_regression.fenbm "$BF_DEPTH" "$BF_TIMEOUT_SEC" "$BASE_THREADS")"
read -r base_bf base_bf_total base_bf_nodes base_bf_time <<<"$suite_out"

suite_out="$(run_suite "$CANDIDATE_PATH" tests/suites/external/arasan2026.epd "$ARASAN_DEPTH" "$ARASAN_TIMEOUT_SEC" "$CAND_THREADS")"
read -r cand_ar cand_ar_total cand_ar_nodes cand_ar_time <<<"$suite_out"

suite_out="$(run_suite "$BASELINE_PATH" tests/suites/external/arasan2026.epd "$ARASAN_DEPTH" "$ARASAN_TIMEOUT_SEC" "$BASE_THREADS")"
read -r base_ar base_ar_total base_ar_nodes base_ar_time <<<"$suite_out"

delta_bf=$((cand_bf - base_bf))
delta_ar=$((cand_ar - base_ar))

echo ""
echo "A/B summary"
echo "- BF depth ${BF_DEPTH}: candidate ${cand_bf}/${cand_bf_total}, baseline ${base_bf}/${base_bf_total}, delta ${delta_bf}"
echo "- Arasan depth ${ARASAN_DEPTH}: candidate ${cand_ar}/${cand_ar_total}, baseline ${base_ar}/${base_ar_total}, delta ${delta_ar}"
echo "- Candidate nodes/time: BF ${cand_bf_nodes}/${cand_bf_time} ms, Arasan ${cand_ar_nodes}/${cand_ar_time} ms"
echo "- Baseline  nodes/time: BF ${base_bf_nodes}/${base_bf_time} ms, Arasan ${base_ar_nodes}/${base_ar_time} ms"

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ -n "$REPORT_TSV" ]]; then
    report_dir="$(dirname "$REPORT_TSV")"
    mkdir -p "$report_dir"
    expected_header="timestamp\trun_tag\tcandidate\tbaseline\tcandidate_threads\tbaseline_threads\tbf_depth\tbf_candidate\tbf_baseline\tbf_delta\tarasan_depth\tar_candidate\tar_baseline\tar_delta\tstrict"

    if [[ ! -f "$REPORT_TSV" ]]; then
        echo -e "$expected_header" >"$REPORT_TSV"
    else
        current_header="$(head -n 1 "$REPORT_TSV" || true)"
        legacy_header1=$'timestamp\tcandidate\tbaseline\tbf_depth\tbf_candidate\tbf_baseline\tbf_delta\tarasan_depth\tar_candidate\tar_baseline\tar_delta\tstrict'
        legacy_header2=$'timestamp\trun_tag\tcandidate\tbaseline\tbf_depth\tbf_candidate\tbf_baseline\tbf_delta\tarasan_depth\tar_candidate\tar_baseline\tar_delta\tstrict'
        if [[ "$current_header" == "$legacy_header1" ]]; then
            tmp_file="$(mktemp)"
            echo -e "$expected_header" >"$tmp_file"
            tail -n +2 "$REPORT_TSV" | awk -F'\t' 'BEGIN{OFS="\t"} {print $1, "legacy", $2, $3, 1, 1, $4, $5, $6, $7, $8, $9, $10, $11, $12}' >>"$tmp_file"
            mv "$tmp_file" "$REPORT_TSV"
            echo "Report migrated to run_tag format: $REPORT_TSV"
        elif [[ "$current_header" == "$legacy_header2" ]]; then
            tmp_file="$(mktemp)"
            echo -e "$expected_header" >"$tmp_file"
            tail -n +2 "$REPORT_TSV" | awk -F'\t' 'BEGIN{OFS="\t"} {print $1, $2, $3, $4, 1, 1, $5, $6, $7, $8, $9, $10, $11, $12, $13}' >>"$tmp_file"
            mv "$tmp_file" "$REPORT_TSV"
            echo "Report migrated to threads columns: $REPORT_TSV"
        fi
    fi

    echo -e "${timestamp}\t${RUN_TAG}\t${CANDIDATE_PATH}\t${BASELINE_PATH}\t${CAND_THREADS}\t${BASE_THREADS}\t${BF_DEPTH}\t${cand_bf}/${cand_bf_total}\t${base_bf}/${base_bf_total}\t${delta_bf}\t${ARASAN_DEPTH}\t${cand_ar}/${cand_ar_total}\t${base_ar}/${base_ar_total}\t${delta_ar}\t${STRICT}" >>"$REPORT_TSV"
    echo "Report updated: $REPORT_TSV"
fi

if [[ -n "$REPORT_MD" ]]; then
    report_md_dir="$(dirname "$REPORT_MD")"
    mkdir -p "$report_md_dir"

    cat >"$REPORT_MD" <<EOF
# A/B Compare Report

- Timestamp (UTC): ${timestamp}
- Run tag: ${RUN_TAG}
- Candidate: ${CANDIDATE_PATH}
- Baseline: ${BASELINE_PATH}
- Candidate threads: ${CAND_THREADS}
- Baseline threads: ${BASE_THREADS}

## Suites

- BF depth ${BF_DEPTH}: candidate ${cand_bf}/${cand_bf_total}, baseline ${base_bf}/${base_bf_total}, delta ${delta_bf}
- Arasan depth ${ARASAN_DEPTH}: candidate ${cand_ar}/${cand_ar_total}, baseline ${base_ar}/${base_ar_total}, delta ${delta_ar}

## Speed Snapshot

- Candidate nodes/time: BF ${cand_bf_nodes}/${cand_bf_time} ms, Arasan ${cand_ar_nodes}/${cand_ar_time} ms
- Baseline nodes/time: BF ${base_bf_nodes}/${base_bf_time} ms, Arasan ${base_ar_nodes}/${base_ar_time} ms

## Strict Mode

- STRICT=${STRICT}
EOF
    echo "Report updated: $REPORT_MD"
fi

if (( STRICT == 1 )); then
    if (( cand_bf < base_bf )); then
        echo "FAIL: candidate worse on BF"
        exit 10
    fi
    if (( cand_ar < base_ar )); then
        echo "FAIL: candidate worse on Arasan"
        exit 11
    fi
    echo "PASS: candidate >= baseline on both suites"
fi
