#!/usr/bin/env python3
"""Compare engine tbtest output against syzygy oracle on fixed 3-piece FEN set."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys
from dataclasses import dataclass


TBTEST_RE = re.compile(r"wdl=(-?\d+)\s+dtz=(-?\d+)")
ORACLE_RE = re.compile(r"wdl=(-?\d+)\s+dtz=(-?\d+)")


@dataclass(frozen=True)
class Case:
    name: str
    fen: str


CASES = [
    Case("kqvk_white", "8/8/8/8/8/8/4K3/k6Q w - - 0 1"),
    Case("kqvk_black", "8/8/8/8/8/8/4k3/K6q b - - 0 1"),
    Case("kqvk_losing", "8/8/8/8/8/8/4K3/k6q w - - 0 1"),
    Case("krvk_white", "8/8/8/8/8/8/4K3/k6R w - - 0 1"),
    Case("krvk_black", "8/8/8/8/8/8/4k3/K6r b - - 0 1"),
    Case("krvk_losing", "8/8/8/8/8/8/4K3/k6r w - - 0 1"),
    Case("kbvk_draw", "8/8/8/8/8/8/4K3/k6B w - - 0 1"),
    Case("knvk_draw", "8/8/8/8/8/8/4K3/k6N w - - 0 1"),
    Case("kpvk_push", "8/8/8/8/8/8/P3K3/k7 w - - 0 1"),
    Case("kvpk_hold", "8/8/8/8/8/8/p3k3/K7 b - - 0 1"),
    Case("krvkb_white", "8/8/8/8/8/8/4K2R/k5b1 w - - 0 1"),
    Case("krvkb_black", "8/8/8/8/8/8/4k2r/K5B1 b - - 0 1"),
    Case("krvkn_white", "8/8/8/8/8/8/4K2R/k5n1 w - - 0 1"),
    Case("krvkn_black", "8/8/8/8/8/8/4k2r/K5N1 b - - 0 1"),
    Case("kbbvk_white", "8/8/8/8/8/8/4K1BB/k7 w - - 0 1"),
    Case("kbbvk_black", "8/8/8/8/8/8/4k1bb/K7 b - - 0 1"),
    Case("kbnvk_white", "8/8/8/8/8/8/4K1BN/k7 w - - 0 1"),
    Case("kbnvk_black", "8/8/8/8/8/8/4k1bn/K7 b - - 0 1"),
    # 4-piece pawnful
    Case("kbpvk_white", "8/8/8/8/8/7P/4K3/k6B w - - 0 1"),
    Case("knpvk_white", "8/8/8/8/8/7P/4K3/k6N w - - 0 1"),
    Case("kppvk_white", "8/8/8/8/8/6PP/4K3/k7 w - - 0 1"),
    Case("kqpvk_white", "8/8/8/8/8/7P/4K2Q/k7 w - - 0 1"),
    Case("krpvk_white", "8/8/8/8/8/7P/4K2R/k7 w - - 0 1"),
    Case("kbvkp_black", "8/8/8/8/8/6p1/4K3/k6B w - - 0 1"),
]


def load_cases(path: Path) -> list[Case]:
    cases: list[Case] = []

    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        # Supported forms:
        # 1) name|fen
        # 2) fen
        # 3) fen;wdl;dtz
        if "|" in line:
            name_part, fen_part = line.split("|", 1)
            name = name_part.strip()
            fen = fen_part.strip()
        else:
            name = f"case_{line_no}"
            fen = line.split(";")[0].strip()
        if not fen:
            raise ValueError(f"invalid case line {line_no}: missing fen")

        cases.append(Case(name=name, fen=fen))

    if not cases:
        raise ValueError(f"no valid cases loaded from {path}")

    return cases


def oracle_wdl_to_engine(wdl: int) -> int:
    if wdl > 0:
        return 2
    if wdl < 0:
        return 0
    return 1


def oracle_dtz_class_to_engine(wdl: int) -> int:
    if wdl > 0:
        return 1
    if wdl < 0:
        return 2
    return 0


def run_engine(engine: str, syz_path: str, fen: str, timeout: int) -> tuple[int, int]:
    payload = (
        "uci\n"
        f"setoption name SyzygyPath value {syz_path}\n"
        f"position fen {fen}\n"
        "tbtest\n"
        "quit\n"
    )
    proc = subprocess.run(
        [engine, "--uci"],
        input=payload,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"engine rc={proc.returncode}: {proc.stderr.strip()}")

    for line in proc.stdout.splitlines():
        if "tbtest" in line:
            m = TBTEST_RE.search(line)
            if m:
                return int(m.group(1)), int(m.group(2))
    raise RuntimeError("tbtest line with wdl/dtz not found in engine output")


def run_oracle(python_bin: str, syz_path: str, fen: str, timeout: int) -> tuple[int, int]:
    proc = subprocess.run(
        [
            python_bin,
            "utils/syzygy_oracle.py",
            "--syzygy-path",
            syz_path,
            "--fen",
            fen,
        ],
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"oracle rc={proc.returncode}: {proc.stderr.strip()}")

    m = ORACLE_RE.search(proc.stdout)
    if not m:
        raise RuntimeError("oracle output missing wdl/dtz pair")
    return int(m.group(1)), int(m.group(2))


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Compare tbtest vs syzygy oracle")
    p.add_argument("--engine", default="./chess-static", help="Engine binary path")
    p.add_argument("--syzygy-path", default="tb", help="Path to Syzygy tables")
    p.add_argument("--python", default=sys.executable, help="Python interpreter")
    p.add_argument("--timeout", type=int, default=20, help="Timeout per probe (seconds)")
    p.add_argument(
        "--cases-file",
        default="",
        help="Optional text file with test cases (one per line: 'name|fen' or just 'fen')",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    fails = 0
    cases = CASES

    if args.cases_file:
        try:
            cases = load_cases(Path(args.cases_file))
        except Exception as exc:
            print(f"ERROR: failed to load cases file '{args.cases_file}': {exc}")
            return 2

    print("tb oracle compare")
    print(f"engine={args.engine}")
    print(f"syzygy_path={args.syzygy_path}")
    if args.cases_file:
        print(f"cases_file={args.cases_file}")

    for case in cases:
        try:
            ew, ed = run_engine(args.engine, args.syzygy_path, case.fen, args.timeout)
            ow_raw, od_raw = run_oracle(args.python, args.syzygy_path, case.fen, args.timeout)
        except Exception as exc:
            fails += 1
            print(f"FAIL {case.name}: {exc}")
            continue

        ow = oracle_wdl_to_engine(ow_raw)
        od = oracle_dtz_class_to_engine(ow_raw)

        if ew != ow or ed != od:
            fails += 1
            print(
                f"FAIL {case.name}: engine wdl/dtz={ew}/{ed} oracle_wdl_raw={ow_raw} oracle_dtz_raw={od_raw} expected={ow}/{od} fen={case.fen}"
            )
        else:
            print(
                f"PASS {case.name}: wdl/dtz={ew}/{ed} oracle_wdl_raw={ow_raw} oracle_dtz_raw={od_raw}"
            )

    print(f"summary: failures={fails} cases={len(cases)}")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
