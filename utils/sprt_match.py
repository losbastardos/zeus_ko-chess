#!/usr/bin/env python3
"""Run a cutechess-cli SPRT match between two UCI engines.

Example:
  python3 utils/sprt_match.py \
    --new ./chess-static \
    --base /run/current-system/sw/bin/stockfish \
    --games 200 --concurrency 2 --tc 10+0.1 \
    --sprt "elo0=0 elo1=8 alpha=0.05 beta=0.05" \
    --pgnout /tmp/sprt.pgn
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from typing import List


def build_cmd(args: argparse.Namespace) -> List[str]:
    cmd: List[str] = ["cutechess-cli"]

    new_ownbook = "true" if args.new_ownbook else "false"
    base_ownbook = "true" if args.base_ownbook else "false"

    cmd += [
        "-engine",
        f"name=NEW",
        f"cmd={args.new}",
        "proto=uci",
        f"option.Hash={args.hash_mb}",
        f"option.Threads={args.new_threads}",
        f"option.OwnBook={new_ownbook}",
        f"option.EvalMode={args.new_eval_mode}",
    ]

    cmd += [
        "-engine",
        f"name=BASE",
        f"cmd={args.base}",
        "proto=uci",
        f"option.Hash={args.hash_mb}",
        f"option.Threads={args.base_threads}",
        f"option.OwnBook={base_ownbook}",
        f"option.EvalMode={args.base_eval_mode}",
    ]

    cmd += ["-each", "proto=uci", f"tc={args.tc}"]
    cmd += ["-concurrency", str(args.concurrency)]
    cmd += ["-games", str(args.games)]
    cmd += ["-repeat"]
    if args.srand is not None:
        cmd += ["-srand", str(args.srand)]

    if args.openings:
        cmd += [
            "-openings",
            f"file={args.openings}",
            f"format={args.openings_format}",
            f"order={args.openings_order}",
            f"plies={args.openings_plies}",
            "start=1",
        ]

    if args.sprt:
        cmd += ["-sprt"] + shlex.split(args.sprt)

    if args.pgnout:
        cmd += ["-pgnout", args.pgnout]

    return cmd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run cutechess SPRT automation")
    parser.add_argument("--new", required=True, help="path to tested engine")
    parser.add_argument("--base", required=True, help="path to baseline engine")
    parser.add_argument("--games", type=int, default=200, help="max number of games")
    parser.add_argument("--concurrency", type=int, default=2, help="parallel game threads")
    parser.add_argument("--tc", default="10+0.1", help="time control for -each tc=")
    parser.add_argument("--hash-mb", type=int, default=64, help="Hash option for both engines")
    parser.add_argument("--new-threads", type=int, default=1, help="Threads option for NEW engine")
    parser.add_argument("--base-threads", type=int, default=1, help="Threads option for BASE engine")
    parser.add_argument("--eval-mode", type=int, default=0, help="EvalMode for both engines (default)")
    parser.add_argument("--new-eval-mode", type=int, default=None, help="EvalMode override for NEW engine")
    parser.add_argument("--base-eval-mode", type=int, default=None, help="EvalMode override for BASE engine")
    parser.add_argument(
        "--ownbook",
        choices=["true", "false"],
        default="false",
        help="OwnBook value for both engines (default: false)",
    )
    parser.add_argument(
        "--new-ownbook",
        choices=["true", "false"],
        default=None,
        help="OwnBook override for NEW engine",
    )
    parser.add_argument(
        "--base-ownbook",
        choices=["true", "false"],
        default=None,
        help="OwnBook override for BASE engine",
    )
    parser.add_argument(
        "--allow-option-asymmetry",
        action="store_true",
        help="allow different NEW/BASE option values (disabled by default)",
    )
    parser.add_argument(
        "--sprt",
        default="elo0=0 elo1=8 alpha=0.05 beta=0.05",
        help="SPRT parameters for cutechess -sprt",
    )
    parser.add_argument(
        "--openings",
        default="",
        help="optional openings file (PGN/EPD) for better coverage",
    )
    parser.add_argument(
        "--openings-format",
        choices=["pgn", "epd"],
        default="pgn",
        help="openings file format",
    )
    parser.add_argument(
        "--openings-order",
        choices=["random", "sequential"],
        default="random",
        help="openings traversal order (random or sequential)",
    )
    parser.add_argument("--openings-plies", type=int, default=8, help="opening plies")
    parser.add_argument(
        "--srand",
        type=int,
        default=None,
        help="fixed cutechess RNG seed for reproducible runs",
    )
    parser.add_argument("--pgnout", default="", help="optional output PGN path")
    parser.add_argument("--dry-run", action="store_true", help="print command and exit")
    args = parser.parse_args()

    args.new_eval_mode = args.eval_mode if args.new_eval_mode is None else args.new_eval_mode
    args.base_eval_mode = args.eval_mode if args.base_eval_mode is None else args.base_eval_mode

    ownbook_default = args.ownbook == "true"
    args.new_ownbook = ownbook_default if args.new_ownbook is None else (args.new_ownbook == "true")
    args.base_ownbook = ownbook_default if args.base_ownbook is None else (args.base_ownbook == "true")

    return args


def validate_inputs(args: argparse.Namespace) -> None:
    if not os.path.exists(args.new):
        raise FileNotFoundError(f"--new engine not found: {args.new}")
    if not os.path.exists(args.base):
        raise FileNotFoundError(f"--base engine not found: {args.base}")
    if args.openings and not os.path.exists(args.openings):
        raise FileNotFoundError(f"--openings file not found: {args.openings}")
    if args.games <= 0:
        raise ValueError("--games must be > 0")
    if args.concurrency <= 0:
        raise ValueError("--concurrency must be > 0")
    if args.new_threads <= 0:
        raise ValueError("--new-threads must be > 0")
    if args.base_threads <= 0:
        raise ValueError("--base-threads must be > 0")
    if args.new_eval_mode < 0 or args.base_eval_mode < 0:
        raise ValueError("EvalMode must be >= 0")

    if not args.allow_option_asymmetry:
        if args.new_threads != args.base_threads:
            raise ValueError("Option asymmetry: Threads differ (use --allow-option-asymmetry to override)")
        if args.new_eval_mode != args.base_eval_mode:
            raise ValueError("Option asymmetry: EvalMode differs (use --allow-option-asymmetry to override)")
        if args.new_ownbook != args.base_ownbook:
            raise ValueError("Option asymmetry: OwnBook differs (use --allow-option-asymmetry to override)")


def main() -> int:
    args = parse_args()
    try:
        validate_inputs(args)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    cmd = build_cmd(args)
    print("options:")
    print(
        f"NEW: Hash={args.hash_mb} Threads={args.new_threads} "
        f"OwnBook={'true' if args.new_ownbook else 'false'} EvalMode={args.new_eval_mode}"
    )
    print(
        f"BASE: Hash={args.hash_mb} Threads={args.base_threads} "
        f"OwnBook={'true' if args.base_ownbook else 'false'} EvalMode={args.base_eval_mode}"
    )
    print("command:")
    print(" ".join(shlex.quote(x) for x in cmd))

    if args.dry_run:
        return 0

    proc = subprocess.run(cmd)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
