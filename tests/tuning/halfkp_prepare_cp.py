#!/usr/bin/env python3
"""Priprava HalfKP 50k datasetu (Faza 1, trainer-side only).

Vstup: CSV s polami fen, eval_cp.
Vystup: NPZ s kompaktnymi sparse featurami pre p0(STM) a p1(OPP).
"""

from __future__ import annotations

import argparse
import csv
import sys

import numpy as np

try:
    import chess
except Exception as exc:  # pragma: no cover
    print(f"error: python-chess required ({exc})", file=sys.stderr)
    raise SystemExit(2)

from halfkp_features import feature_indices_for_color


F_HALFKP = 2 * 64 * 5 * 64  # 40960
MAX_ACTIVE = 64  # bezpecna rezerva (typicky <=30)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Prepare HalfKP CP dataset (CSV -> NPZ)")
    p.add_argument("--csv", required=True, help="input CSV with columns fen, eval_cp")
    p.add_argument("--out", required=True, help="output NPZ path")
    p.add_argument("--max-positions", type=int, default=50000)
    p.add_argument("--cp-clip", type=float, default=2000.0)
    p.add_argument("--cp-label-perspective", choices=["stm", "white"], default="stm")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    fens = []
    ys = []

    with open(args.csv, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                fen = row["fen"]
                cp = float(row["eval_cp"])
            except Exception:
                continue

            stm_black = fen.split()[1] == "b"
            if args.cp_label_perspective == "white" and stm_black:
                cp = -cp
            if args.cp_clip > 0:
                cp = max(-args.cp_clip, min(args.cp_clip, cp))

            fens.append(fen)
            ys.append(cp)
            if args.max_positions > 0 and len(fens) >= args.max_positions:
                break

    n = len(fens)
    if n == 0:
        print("error: empty dataset after parsing/filtering", file=sys.stderr)
        return 2

    idx_stm = np.full((n, MAX_ACTIVE), -1, dtype=np.int32)
    idx_opp = np.full((n, MAX_ACTIVE), -1, dtype=np.int32)
    cnt_stm = np.zeros(n, dtype=np.uint8)
    cnt_opp = np.zeros(n, dtype=np.uint8)
    y = np.asarray(ys, dtype=np.float32)

    for i, fen in enumerate(fens):
        b = chess.Board(fen)
        _, stm = feature_indices_for_color(b, b.turn)
        _, opp = feature_indices_for_color(b, not b.turn)
        if len(stm) > MAX_ACTIVE or len(opp) > MAX_ACTIVE:
            print(f"error: active feature overflow at row {i} (stm={len(stm)} opp={len(opp)})", file=sys.stderr)
            return 2
        cnt_stm[i] = len(stm)
        cnt_opp[i] = len(opp)
        if stm:
            idx_stm[i, : len(stm)] = np.asarray(stm, dtype=np.int32)
        if opp:
            idx_opp[i, : len(opp)] = np.asarray(opp, dtype=np.int32)

    np.savez_compressed(
        args.out,
        idx_stm=idx_stm,
        idx_opp=idx_opp,
        cnt_stm=cnt_stm,
        cnt_opp=cnt_opp,
        y=y,
        F=np.int32(F_HALFKP),
        n=np.int32(n),
    )

    print(f"prepared: {args.out}")
    print(f"positions={n}")
    print(f"active_mean_stm={float(cnt_stm.mean()):.3f} active_mean_opp={float(cnt_opp.mean()):.3f}")
    print(f"target_std={float(y.std()):.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
