#!/usr/bin/env python3
"""Shared HalfKP feature indexing helpers (v3 draft).

Tento modul je jeden zdroj pravdy pre:
- treningovy feature hasher,
- dump/equivalence testy trainer vs engine.

Perspektivna konvencia dumpu:
- p0 = strana na tahu (STM)
- p1 = super (OPP)

Index formula (per perspective color):
    idx = (((own * 64 + king_rel) * 5 + type_idx) * 64 + piece_rel)
    own: 0 ak farba figury == farba perspektivy, inak 1
    type_idx: P,N,B,R,Q -> 0..4
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Tuple

import chess

PIECE_TO_IDX = {
    chess.PAWN: 0,
    chess.KNIGHT: 1,
    chess.BISHOP: 2,
    chess.ROOK: 3,
    chess.QUEEN: 4,
}

F_HALFKP_V3 = 2 * 64 * 5 * 64


@dataclass(frozen=True)
class FeatureRecord:
    perspective: int
    own: int
    king_rel: int
    piece_type_idx: int
    piece_rel: int
    idx: int


def _rel_sq(sq: int, perspective: int) -> int:
    return sq if perspective == 0 else (sq ^ 56)


def _perspective_color(perspective: int) -> bool:
    return chess.WHITE if perspective == 0 else chess.BLACK


def _perspective_id(perspective_color: bool) -> int:
    return 0 if perspective_color == chess.WHITE else 1


def _idx(own: int, king_rel: int, piece_type_idx: int, piece_rel: int) -> int:
    return (((own * 64 + king_rel) * 5 + piece_type_idx) * 64 + piece_rel)


def feature_records_for_color(board: chess.Board, pov_color: bool) -> Tuple[int, List[FeatureRecord]]:
    """Vrati (king_rel, feature records) pre jednu perspektivu farby."""
    perspective = _perspective_id(pov_color)
    king_sq = board.king(pov_color)
    if king_sq is None:
        raise ValueError("Position without king is not supported")

    king_rel = _rel_sq(king_sq, perspective)
    out: List[FeatureRecord] = []

    for sq, piece in board.piece_map().items():
        if piece.piece_type == chess.KING:
            continue
        type_idx = PIECE_TO_IDX.get(piece.piece_type)
        if type_idx is None:
            continue
        own = 0 if piece.color == pov_color else 1
        piece_rel = _rel_sq(sq, perspective)
        idx = _idx(own, king_rel, type_idx, piece_rel)
        out.append(
            FeatureRecord(
                perspective=perspective,
                own=own,
                king_rel=king_rel,
                piece_type_idx=type_idx,
                piece_rel=piece_rel,
                idx=idx,
            )
        )

    out.sort(key=lambda r: r.idx)
    return king_rel, out


def feature_indices_for_color(board: chess.Board, pov_color: bool) -> Tuple[int, List[int]]:
    king_rel, records = feature_records_for_color(board, pov_color)
    return king_rel, [r.idx for r in records]


def dump_lines(board: chess.Board) -> List[str]:
    """Vrati presny 3-riadkovy dump format kompatibilny s engine halfkpdump."""
    p0_color = board.turn
    p1_color = not board.turn

    ks0, idx0 = feature_indices_for_color(board, p0_color)
    ks1, idx1 = feature_indices_for_color(board, p1_color)

    line0 = "halfkpdump"
    line1 = f"p0 ks={ks0} n={len(idx0)} idx:" + (" " + " ".join(str(x) for x in idx0) if idx0 else "")
    line2 = f"p1 ks={ks1} n={len(idx1)} idx:" + (" " + " ".join(str(x) for x in idx1) if idx1 else "")
    return [line0, line1, line2]


def parse_fens(path: str) -> Iterable[str]:
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            fen = line.strip()
            if not fen or fen.startswith("#"):
                continue
            yield fen


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description="HalfKP v3 feature dumper")
    ap.add_argument("--fen", default="")
    ap.add_argument("--fen-list", default="")
    args = ap.parse_args()

    fens: List[str] = []
    if args.fen:
        fens.append(args.fen)
    if args.fen_list:
        fens.extend(parse_fens(args.fen_list))

    if not fens:
        ap.error("provide --fen or --fen-list")

    for i, fen in enumerate(fens, start=1):
        b = chess.Board(fen)
        print(f"fen={fen}")
        for line in dump_lines(b):
            print(line)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
