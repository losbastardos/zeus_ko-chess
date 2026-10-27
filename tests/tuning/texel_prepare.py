#!/usr/bin/env python3
"""Prepare a Texel-style dataset from PGN games.

line closed 2026-10-27, kept for reference.

Output CSV columns:
- fen: board FEN including side/castling/en-passant and counters
- result: white-game result label in {1.0, 0.5, 0.0}
- ply: ply index inside game
- game_index: 1-based game index in input stream
- source: input file path

Sampling policy:
- skip first N plies (opening noise)
- then sample every K plies
- optional hard cap on total exported positions
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from dataclasses import dataclass
from typing import Iterable, List, Optional

try:
    import chess
    import chess.pgn
except Exception as exc:  # pragma: no cover
    print(f"error: python-chess is required ({exc})", file=sys.stderr)
    raise SystemExit(2)


RESULT_MAP = {
    "1-0": 1.0,
    "1/2-1/2": 0.5,
    "0-1": 0.0,
}


@dataclass
class ExportConfig:
    skip_plies: int
    sample_every: int
    max_positions: int


def iter_games(paths: Iterable[str]):
    for p in paths:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            while True:
                game = chess.pgn.read_game(f)
                if game is None:
                    break
                yield p, game


def collect_rows(paths: List[str], cfg: ExportConfig):
    rows = []
    total_games = 0
    kept_games = 0

    for source, game in iter_games(paths):
        total_games += 1
        result_token = game.headers.get("Result", "*")
        if result_token not in RESULT_MAP:
            continue

        label = RESULT_MAP[result_token]
        board = game.board()
        kept_games += 1

        for ply, move in enumerate(game.mainline_moves(), start=1):
            board.push(move)

            if ply <= cfg.skip_plies:
                continue
            if (ply - cfg.skip_plies + (total_games & 1)) % cfg.sample_every != 0:
                continue

            rows.append(
                {
                    "fen": board.fen(),
                    "result": f"{label:.1f}",
                    "ply": str(ply),
                    "game_index": str(total_games),
                    "source": source,
                }
            )

            if cfg.max_positions > 0 and len(rows) >= cfg.max_positions:
                return rows, total_games, kept_games

    return rows, total_games, kept_games


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create Texel tuning CSV from PGN files")
    parser.add_argument("inputs", nargs="+", help="one or more PGN files")
    parser.add_argument("--out", required=True, help="output CSV path")
    parser.add_argument("--skip-plies", type=int, default=12, help="ignore first N plies of each game")
    parser.add_argument("--sample-every", type=int, default=2, help="take one position every K plies")
    parser.add_argument("--max-positions", type=int, default=50000, help="hard cap (0 = no cap)")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    for p in args.inputs:
        if not os.path.exists(p):
            print(f"error: input not found: {p}", file=sys.stderr)
            return 3

    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    cfg = ExportConfig(
        skip_plies=max(0, args.skip_plies),
        sample_every=max(1, args.sample_every),
        max_positions=max(0, args.max_positions),
    )

    rows, total_games, kept_games = collect_rows(args.inputs, cfg)

    with open(args.out, "w", encoding="utf-8", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=["fen", "result", "ply", "game_index", "source"])
        wr.writeheader()
        wr.writerows(rows)

    print("texel dataset prepared")
    print(f"- files: {len(args.inputs)}")
    print(f"- games parsed: {total_games}")
    print(f"- games with WDL result: {kept_games}")
    print(f"- positions exported: {len(rows)}")
    print(f"- output: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
