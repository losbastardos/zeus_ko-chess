#!/usr/bin/env python3
"""texel_tension_mix.py — stavba 2M HalfKP datasetu: stratifikovana baza
+ ring-tension overlay (mix1, ring only; storm vetva nie je zrekonstruovana).

Sekvencia (rozhodnutie 2026-11-05):
  1. base    — stratifikovany vyber cez Lumbras ery + dedup FEN
  2. overlay — ring tension kvota (default 30 % celku, strong:weak 60:40)
  3. merge   — zlucenie ramien, shuffle, vystup pre SF d12 labelovanie

Ring tension spec (overena v boji, mix1 650k):
  ring: kral + 8 susednych policok (orezane na hraniciach dosky)
  tension: pocet nepriatelskych figur Q,R,B,N,P, ktore napadaju >=1
           policko ringu (krali sa nepocitaju)
  level = max(attackers na bieleho, attackers na cierneho)
    weak   = level 1
    strong = level >= 2
  overlay kvota: 60 % strong, 40 % weak
    (ref: level_hist {2: 90000, 1: 60000} pri 650k behu)
  label: SF d12, STM perspektiva, audit std 200-350 cp

Vstupne CSV: vystup pgn2csv.py (fen,result,ply,game_index,source).

Pouzitie:
  python3 tests/tuning/texel_tension_mix.py base \
    --inputs scratch/texel_*.csv --out scratch/base_2m.csv \
    --target 1400000 --seed 20261105
  python3 tests/tuning/texel_tension_mix.py overlay \
    --inputs scratch/texel_*.csv --out scratch/overlay_600k.csv \
    --quota 600000 --strong-frac 0.60 --pool 3000000 --seed 20261105
  python3 tests/tuning/texel_tension_mix.py merge \
    --base scratch/base_2m.csv --overlay scratch/overlay_600k.csv \
    --out scratch/texel_2m_mix.csv
"""

from __future__ import annotations

import argparse
import csv
import random
import subprocess
import sys
from collections import Counter

import chess

RING_DXDY = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if not (dx == 0 and dy == 0)]
ATTACKERS = (chess.QUEEN, chess.ROOK, chess.BISHOP, chess.KNIGHT, chess.PAWN)


def ring_squares(ksq: int) -> list:
    """Kral + 8 susedov, orezane na dosku."""
    kx, ky = chess.square_file(ksq), chess.square_rank(ksq)
    out = [ksq]
    for dx, dy in RING_DXDY:
        fx, fy = kx + dx, ky + dy
        if 0 <= fx < 8 and 0 <= fy < 8:
            out.append(chess.square(fx, fy))
    return out


def ring_attackers(board: chess.Board, color: int) -> int:
    """Pocet nepriatelskych Q,R,B,N,P utocnych figur, ktore napadaju
    aspon jedno policko ringu krala `color`."""
    ksq = board.king(color)
    if ksq is None:
        return 0
    ring = ring_squares(ksq)
    enemy = not color
    count = 0
    for piece_type in ATTACKERS:
        for sq in board.pieces(piece_type, enemy):
            attacks = board.attacks(sq)
            if any(rs in attacks for rs in ring):
                count += 1
    return count


def tension_level(fen: str) -> int:
    board = chess.Board(fen)
    return max(ring_attackers(board, chess.WHITE),
               ring_attackers(board, chess.BLACK))


def fen_key(fen: str) -> str:
    """Dedup kluc: doska + strana na tahu + rošáda + ep (bez pocitadiel)."""
    parts = fen.split()
    return " ".join(parts[:4]) if len(parts) >= 4 else fen


# ---------------------------------------------------------------- base ----

AWK_RESERVOIR = r"""
BEGIN { srand(SEED); n = TARGET }
NR <= n { res[NR] = $0 }
NR > n { j = int(rand() * NR); if (j < n) res[j + 1] = $0 }
END { for (i = 1; i <= n; i++) if (i in res) print res[i] }
"""


def cmd_base(args) -> int:
    inputs = sorted(args.inputs)
    if not inputs:
        print("error: --inputs prazdny", file=sys.stderr)
        return 2
    per_file = args.target // len(inputs)
    seen: set = set()
    total = 0
    with open(args.out, "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["fen", "result", "ply", "game_index", "source"])
        for path in inputs:
            proc = subprocess.run(
                ["awk", "-v", f"TARGET={per_file}", "-v", f"SEED={args.seed}",
                 AWK_RESERVOIR, path],
                capture_output=True, text=True)
            kept = 0
            dup = 0
            for line in proc.stdout.splitlines():
                if not line.strip():
                    continue
                fen = line.split(",", 1)[0]
                key = fen_key(fen)
                if key in seen:
                    dup += 1
                    continue
                seen.add(key)
                w.writerow(line.split(",")[:5])
                kept += 1
            total += kept
            print(f"base: {path}: kept={kept} dup_skipped={dup}")
    print(f"base total: {total} -> {args.out}")
    return 0


# -------------------------------------------------------------- overlay ----

def cmd_overlay(args) -> int:
    rng = random.Random(args.seed)
    # 1) rychly awk reservoir vyber kandidatskej pooly cez vsetky vstupy
    per_file = max(1, args.pool // len(args.inputs))
    pool = []
    for path in sorted(args.inputs):
        proc = subprocess.run(
            ["awk", "-v", f"TARGET={per_file}", "-v", f"SEED={args.seed}",
             AWK_RESERVOIR, path],
            capture_output=True, text=True)
        for line in proc.stdout.splitlines():
            if line.strip():
                pool.append(line)
    print(f"overlay: candidate pool={len(pool)}")

    # 2) tension evaluacia + stratifikacia strong/weak
    want_strong = int(args.quota * args.strong_frac)
    want_weak = args.quota - want_strong
    strong: list = []
    weak: list = []
    level_hist: Counter = Counter()
    seen: set = set()
    rng.shuffle(pool)
    for line in pool:
        if len(strong) >= want_strong and len(weak) >= want_weak:
            break
        fen = line.split(",", 1)[0]
        key = fen_key(fen)
        if key in seen:
            continue
        try:
            level = tension_level(fen)
        except Exception:
            continue
        seen.add(key)
        level_hist[level] += 1
        if level >= 2 and len(strong) < want_strong:
            strong.append(line)
        elif level == 1 and len(weak) < want_weak:
            weak.append(line)

    print(f"overlay: level_hist={dict(sorted(level_hist.items()))}")
    print(f"overlay: strong={len(strong)} (wanted {want_strong}), "
          f"weak={len(weak)} (wanted {want_weak})")
    if len(strong) < want_strong or len(weak) < want_weak:
        print("warning: kvota nesplnena — pool prilis mala alebo prah prilis "
              "tazky; zvys --pool", file=sys.stderr)

    with open(args.out, "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["fen", "result", "ply", "game_index", "source"])
        for line in strong + weak:
            w.writerow(line.split(",")[:5])
    print(f"overlay total: {len(strong) + len(weak)} -> {args.out}")
    return 0


# ---------------------------------------------------------------- merge ----

def cmd_merge(args) -> int:
    rng = random.Random(args.seed)
    rows = []
    for path, tag in ((args.base, "base"), (args.overlay, "overlay")):
        with open(path, "r", encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                rows.append((row["fen"], row["result"], tag))
    rng.shuffle(rows)
    with open(args.out, "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["fen", "result", "arm"])
        for fen, result, tag in rows:
            w.writerow([fen, result, tag])
    print(f"merge total: {len(rows)} (base+overlay) -> {args.out}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("base")
    b.add_argument("--inputs", nargs="+", required=True)
    b.add_argument("--out", required=True)
    b.add_argument("--target", type=int, default=1_400_000)
    b.add_argument("--seed", type=int, default=20261105)
    b.set_defaults(func=cmd_base)

    o = sub.add_parser("overlay")
    o.add_argument("--inputs", nargs="+", required=True)
    o.add_argument("--out", required=True)
    o.add_argument("--quota", type=int, default=600_000)
    o.add_argument("--strong-frac", type=float, default=0.60)
    o.add_argument("--pool", type=int, default=3_000_000)
    o.add_argument("--seed", type=int, default=20261105)
    o.set_defaults(func=cmd_overlay)

    m = sub.add_parser("merge")
    m.add_argument("--base", required=True)
    m.add_argument("--overlay", required=True)
    m.add_argument("--out", required=True)
    m.add_argument("--seed", type=int, default=20261105)
    m.set_defaults(func=cmd_merge)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
