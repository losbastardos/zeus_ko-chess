#!/usr/bin/env python3
"""HalfKP feature equivalence checker (string-diff mode).

Pre kazdy FEN:
1. vygeneruje expected dump cez shared hasher,
2. vyziada engine prikazom halfkpdump,
3. porovna vysledok ako cisty string (riadok-po-riadku).

Format dumpu:
    halfkpdump
    p0 ks=<king_rel> n=<count> idx: <zoradene idx>
    p1 ks=<king_rel> n=<count> idx: <zoradene idx>
"""

from __future__ import annotations

import argparse
import difflib
import subprocess
import sys
from pathlib import Path
from typing import List

import chess

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from halfkp_features import dump_lines


def load_fens(path: str) -> List[str]:
    out: List[str] = []
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            out.append(line)
    return out


def expected_dump(fen: str) -> str:
    board = chess.Board(fen)
    return "\n".join(dump_lines(board))


def _extract_dump_block(lines: List[str]) -> str:
    """Najde posledny halfkpdump blok v ramci jedneho readyok segmentu."""
    hdr_idx = -1
    for i, line in enumerate(lines):
        if line == "halfkpdump":
            hdr_idx = i
    if hdr_idx < 0 or hdr_idx + 2 >= len(lines):
        return ""
    return "\n".join(lines[hdr_idx : hdr_idx + 3])


def run_engine_dumps(engine: str, fens: List[str], timeout: int) -> List[str]:
    # Jedna UCI session pre vsetky FEN: position+halfkpdump+isready stream.
    chunks: List[str] = ["uci"]
    for fen in fens:
        chunks.append(f"position fen {fen}")
        chunks.append("halfkpdump")
        chunks.append("isready")
    chunks.append("quit")
    cmds = "\n".join(chunks) + "\n"

    proc = subprocess.run(
        [engine, "--uci"],
        input=cmds,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )

    lines = [ln.rstrip() for ln in proc.stdout.splitlines() if ln.strip()]
    out: List[str] = []
    seg: List[str] = []
    for line in lines:
        if line == "readyok":
            out.append(_extract_dump_block(seg))
            seg = []
            continue
        seg.append(line)
    return out


def show_diff(expected: str, actual: str) -> str:
    exp = expected.splitlines()
    got = actual.splitlines()
    return "\n".join(
        difflib.unified_diff(exp, got, fromfile="expected", tofile="engine", lineterm="")
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="HalfKP trainer-vs-engine dump equivalence")
    ap.add_argument("--engine", default="./chess-static")
    ap.add_argument("--fens", default="tests/tuning/halfkp_equivalence_fens.txt")
    ap.add_argument("--max-print", type=int, default=5)
    ap.add_argument("--timeout-per-fen", type=int, default=2)
    args = ap.parse_args()

    fens = load_fens(args.fens)
    if not fens:
        print("error: empty FEN list")
        return 2

    timeout = max(20, len(fens) * args.timeout_per_fen)
    dumps = run_engine_dumps(args.engine, fens, timeout)
    if len(dumps) != len(fens):
        print(
            f"FAIL protocol expected_blocks={len(fens)} got_blocks={len(dumps)}"
        )
        return 1

    bad = 0
    for i, fen in enumerate(fens, start=1):
        exp = expected_dump(fen)
        got = dumps[i - 1]
        if exp != got:
            bad += 1
            print(f"MISMATCH #{i} fen={fen}")
            if bad <= args.max_print:
                print(show_diff(exp, got))

    if bad:
        print(f"FAIL cases={len(fens)} mismatches={bad}")
        return 1

    print(f"OK cases={len(fens)} mismatches=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
