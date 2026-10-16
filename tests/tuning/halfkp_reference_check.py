#!/usr/bin/env python3
"""Test R: nezavisla HalfKP referencia vs aktualny hasher.

Ciel:
- referencny indexer napisany "na zelenej luke" podla kanonickej formule,
- porovnanie indexovych mnozin pre p0/p1 s existujucim halfkp_features.py,
- report mismatchov (ak existuju) s konkretne odlisnymi indexami.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import chess

from halfkp_features import feature_indices_for_color as dut_feature_indices_for_color

PIECE_TO_TYPE_IDX = {
    chess.PAWN: 0,
    chess.KNIGHT: 1,
    chess.BISHOP: 2,
    chess.ROOK: 3,
    chess.QUEEN: 4,
}


@dataclass(frozen=True)
class PerspectiveDump:
    king_rel: int
    idx: list[int]


def parse_fens(path: Path) -> Iterable[str]:
    for raw in path.read_text(encoding="utf-8").splitlines():
        fen = raw.strip()
        if not fen or fen.startswith("#"):
            continue
        yield fen


def rel_square(square: int, pov_color: bool) -> int:
    # White POV: identity, Black POV: vertical mirror (xor 56).
    return square if pov_color == chess.WHITE else (square ^ 56)


def reference_indices_for_color(board: chess.Board, pov_color: bool) -> PerspectiveDump:
    king_sq = board.king(pov_color)
    if king_sq is None:
        raise ValueError("position without king")

    king_rel = rel_square(king_sq, pov_color)
    out: list[int] = []

    for sq, piece in board.piece_map().items():
        if piece.piece_type == chess.KING:
            continue
        t = PIECE_TO_TYPE_IDX.get(piece.piece_type)
        if t is None:
            continue

        own = 0 if piece.color == pov_color else 1
        piece_rel = rel_square(sq, pov_color)
        idx = (((own * 64 + king_rel) * 5 + t) * 64 + piece_rel)
        out.append(idx)

    out.sort()
    return PerspectiveDump(king_rel=king_rel, idx=out)


def fmt_diff(ref: list[int], dut: list[int]) -> tuple[str, str]:
    s_ref = set(ref)
    s_dut = set(dut)
    missing = sorted(s_ref - s_dut)
    extra = sorted(s_dut - s_ref)
    miss_txt = " ".join(str(x) for x in missing[:24])
    extra_txt = " ".join(str(x) for x in extra[:24])
    return miss_txt, extra_txt


def main() -> int:
    ap = argparse.ArgumentParser(description="HalfKP Test R: reference vs DUT hasher")
    ap.add_argument("--fen-list", default="tests/tuning/halfkp_equivalence_fens.txt")
    ap.add_argument("--limit", type=int, default=10)
    ap.add_argument("--report", default="tests/reports/halfkp_reference_check_20261015.txt")
    args = ap.parse_args()

    fens = list(parse_fens(Path(args.fen_list)))
    if args.limit > 0:
        fens = fens[: args.limit]

    lines: list[str] = []
    lines.append("halfkp_reference_check")
    lines.append(f"fen_list={args.fen_list}")
    lines.append(f"limit={len(fens)}")

    mismatches = 0
    for i, fen in enumerate(fens, start=1):
        board = chess.Board(fen)
        p0 = board.turn
        p1 = not board.turn

        ref0 = reference_indices_for_color(board, p0)
        ref1 = reference_indices_for_color(board, p1)

        dut_ks0, dut_idx0 = dut_feature_indices_for_color(board, p0)
        dut_ks1, dut_idx1 = dut_feature_indices_for_color(board, p1)

        ok0 = (ref0.king_rel == dut_ks0) and (ref0.idx == dut_idx0)
        ok1 = (ref1.king_rel == dut_ks1) and (ref1.idx == dut_idx1)

        lines.append(f"case {i}: {'OK' if (ok0 and ok1) else 'MISMATCH'}")
        lines.append(f"fen={fen}")

        if not ok0:
            mismatches += 1
            miss, extra = fmt_diff(ref0.idx, dut_idx0)
            lines.append(f"p0 ks_ref={ref0.king_rel} ks_dut={dut_ks0} n_ref={len(ref0.idx)} n_dut={len(dut_idx0)}")
            lines.append(f"p0 missing(ref-dut): {miss}")
            lines.append(f"p0 extra(dut-ref): {extra}")
        if not ok1:
            mismatches += 1
            miss, extra = fmt_diff(ref1.idx, dut_idx1)
            lines.append(f"p1 ks_ref={ref1.king_rel} ks_dut={dut_ks1} n_ref={len(ref1.idx)} n_dut={len(dut_idx1)}")
            lines.append(f"p1 missing(ref-dut): {miss}")
            lines.append(f"p1 extra(dut-ref): {extra}")

    lines.append(f"summary: cases={len(fens)} perspective_mismatches={mismatches}")
    status = "PASS" if mismatches == 0 else "FAIL"
    lines.append(f"status={status}")

    Path(args.report).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"report: {args.report}")
    print(f"summary: cases={len(fens)} perspective_mismatches={mismatches} status={status}")
    return 0 if mismatches == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
