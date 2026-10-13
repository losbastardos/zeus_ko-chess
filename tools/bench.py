#!/usr/bin/env python3
"""
UCI NPS benchmark harness pre chess-static.
Pouziva fixnu hlbku, aby bol pocet nodes stabilny; cas je potom cisty rychlostny metr.
Ak nodes driftuju o viac ako 0.5 %, skript oznaci, ze sa zmenilo search spravanie.
"""

import argparse
import csv
import datetime
import os
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass

DEFAULT_EPD = "tests/suites/external/arasan2026.epd"
DEFAULT_HISTORY = "bench_history.csv"
DEFAULT_DEPTH = 10
DEFAULT_LIMIT = 20
DEFAULT_RUNS = 3
NODE_DRIFT_THRESHOLD = 0.005


@dataclass
class BenchResult:
    nodes: int
    seconds: float

    @property
    def nps(self) -> float:
        if self.seconds <= 0:
            return 0.0
        return self.nodes / self.seconds


class UciEngine:
    def __init__(self, engine_path: str, hash_mb: int, threads: int) -> None:
        self.process = subprocess.Popen(
            [engine_path, "--uci"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._cmd("uci")
        self._wait_for("uciok", timeout=30)
        self._cmd(f"setoption name Hash value {hash_mb}")
        self._cmd(f"setoption name Threads value {threads}")
        self._cmd("isready")
        self._wait_for("readyok", timeout=30)

    def _cmd(self, command: str) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(command + "\n")
        self.process.stdin.flush()

    def _wait_for(self, token: str, timeout: float) -> tuple[str, str]:
        assert self.process.stdout is not None
        deadline = time.monotonic() + timeout
        last_info_with_nodes = ""

        while True:
            if time.monotonic() > deadline:
                raise RuntimeError(f"timeout waiting for '{token}'")

            line = self.process.stdout.readline()
            if not line:
                continue

            line = line.strip()
            if line.startswith("info") and " nodes " in f" {line} ":
                last_info_with_nodes = line

            if line.startswith(token):
                return line, last_info_with_nodes

    @staticmethod
    def _extract_nodes(info_line: str) -> int:
        if not info_line:
            return 0
        tokens = info_line.split()
        for idx, token in enumerate(tokens):
            if token == "nodes" and idx + 1 < len(tokens):
                try:
                    return int(tokens[idx + 1])
                except ValueError:
                    return 0
        return 0

    def run_depth(self, fen: str, depth: int) -> int:
        self._cmd("setoption name Clear Hash")
        self._cmd("isready")
        self._wait_for("readyok", timeout=30)

        self._cmd(f"position fen {fen}")
        self._cmd(f"go depth {depth}")
        _, info_line = self._wait_for("bestmove", timeout=300)
        nodes = self._extract_nodes(info_line)
        if nodes <= 0:
            raise RuntimeError("engine nevratil validny 'info ... nodes ...' pred bestmove")
        return nodes

    def close(self) -> None:
        try:
            self._cmd("quit")
        except Exception:
            pass
        self.process.wait(timeout=10)


def parse_epd_positions(epd_path: str, limit: int) -> list[str]:
    """
    Nacita prve N pozicii z EPD/FEN suboru a vrati ich ako UCI-friendly FEN (6 poli).

    - EPD bez polcas/fullmove: "<board> <stm> <castle> <ep> ..." -> doplni "0 1"
    - FEN 6-polovy vstup necha bez zmeny
    """
    fens: list[str] = []
    with open(epd_path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            # EPD operatory (bm/am/id/...) su za ';' - FEN cast je pred prvym ';'.
            fen_part = line.split(";", 1)[0].strip()
            parts = fen_part.split()

            if len(parts) >= 6 and parts[4].isdigit() and parts[5].isdigit():
                fen = " ".join(parts[:6])
            elif len(parts) >= 4:
                fen = " ".join(parts[:4] + ["0", "1"])
            else:
                continue

            fens.append(fen)
            if len(fens) >= limit:
                break

    return fens


def current_commit_short() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            text=True,
            cwd=os.getcwd(),
        ).strip()
    except Exception:
        return "n/a"


def run_single_bench(engine: str, fens: list[str], depth: int, hash_mb: int, threads: int) -> BenchResult:
    uci = UciEngine(engine_path=engine, hash_mb=hash_mb, threads=threads)
    total_nodes = 0
    start = time.perf_counter()

    try:
        for fen in fens:
            total_nodes += uci.run_depth(fen=fen, depth=depth)
    finally:
        uci.close()

    elapsed = time.perf_counter() - start
    return BenchResult(nodes=total_nodes, seconds=elapsed)


def load_history_rows(path: str) -> list[dict[str, str]]:
    if not os.path.exists(path):
        return []

    rows: list[dict[str, str]] = []
    with open(path, "r", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            rows.append(row)
    return rows


def history_reference_nodes(history_rows: list[dict[str, str]], window: int = 5) -> int | None:
    if not history_rows:
        return None

    sample = history_rows[-window:]
    values: list[int] = []
    for row in sample:
        try:
            values.append(int(row["nodes"]))
        except (KeyError, TypeError, ValueError):
            continue

    if not values:
        return None
    return int(statistics.median(values))


def append_history(path: str, depth: int, positions_count: int, median_result: BenchResult, note: str) -> None:
    file_exists = os.path.exists(path)
    with open(path, "a", encoding="utf-8", newline="") as handle:
        fieldnames = ["date", "commit", "depth", "positions", "nodes", "seconds", "nps", "note"]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        if not file_exists:
            writer.writeheader()

        writer.writerow(
            {
                "date": datetime.datetime.now().isoformat(timespec="seconds"),
                "commit": current_commit_short(),
                "depth": depth,
                "positions": positions_count,
                "nodes": median_result.nodes,
                "seconds": f"{median_result.seconds:.3f}",
                "nps": int(median_result.nps),
                "note": note,
            }
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Deterministicky UCI NPS benchmark")
    parser.add_argument("--engine", default="./chess-static", help="Cesta k UCI engine")
    parser.add_argument("--positions", default=DEFAULT_EPD, help="EPD subor s poziciami")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="Pocet pozicii z EPD")
    parser.add_argument("--depth", type=int, default=DEFAULT_DEPTH, help="Fixna search depth")
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS, help="Pocet opakovani")
    parser.add_argument("--hash", type=int, default=64, dest="hash_mb", help="Hash v MB")
    parser.add_argument("--threads", type=int, default=1, help="Pocet vlakien")
    parser.add_argument("--history", default=DEFAULT_HISTORY, help="CSV subor historiou benchmarkov")
    parser.add_argument("--note", default="", help="Volitelna poznamka do historie")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    positions = parse_epd_positions(args.positions, args.limit)
    if not positions:
        print("ERROR: nenasli sa ziadne pozicie", file=sys.stderr)
        return 2

    if args.depth <= 0 or args.limit <= 0 or args.runs <= 0:
        print("ERROR: depth, limit a runs musia byt > 0", file=sys.stderr)
        return 2

    all_runs: list[BenchResult] = []
    for run_idx in range(args.runs):
        result = run_single_bench(
            engine=args.engine,
            fens=positions,
            depth=args.depth,
            hash_mb=args.hash_mb,
            threads=args.threads,
        )
        all_runs.append(result)
        print(
            f"run {run_idx + 1}: nodes={result.nodes:,}  "
            f"time={result.seconds:.3f}s  nps={result.nps:,.0f}"
        )

    by_time = sorted(all_runs, key=lambda item: item.seconds)
    median = by_time[len(by_time) // 2]

    history_rows = load_history_rows(args.history)
    ref_nodes = history_reference_nodes(history_rows)

    os.makedirs(os.path.dirname(args.history) or ".", exist_ok=True)
    append_history(
        path=args.history,
        depth=args.depth,
        positions_count=len(positions),
        median_result=median,
        note=args.note,
    )

    print(
        f"\nMEDIAN: nodes={median.nodes:,}  time={median.seconds:.3f}s  "
        f"NPS={median.nps:,.0f}"
    )

    if history_rows:
        try:
            prev_nps = int(history_rows[-1]["nps"])
            delta_pct = ((median.nps - prev_nps) / prev_nps) * 100 if prev_nps else 0.0
            print(f"vs last: {delta_pct:+.2f}%  ({prev_nps:,} -> {int(median.nps):,})")
        except (KeyError, TypeError, ValueError):
            pass

    if ref_nodes is not None:
        drift = abs(median.nodes - ref_nodes) / ref_nodes if ref_nodes else 0.0
        if drift > NODE_DRIFT_THRESHOLD:
            signed = ((median.nodes - ref_nodes) / ref_nodes) * 100 if ref_nodes else 0.0
            print(
                "WARNING: node count drift "
                f"{signed:+.2f}% vs history median {ref_nodes:,}. "
                "To nie je cista NPS zmena; zmenilo sa search spravanie."
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
