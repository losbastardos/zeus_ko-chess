#!/usr/bin/env python3
"""sf_label.py — SF 18 labelovanie Texel CSV eval_cp (STM perspektiva).

Labeluje kazdu poziciu `go depth 12` a berie posledny score cp pred
bestmove (STM konvencia — zhodna s texel_label_eval.py). Vystupny CSV
ma stlpec eval_cp; audit mean/std na vzorke 1000 kontroluje jednotky
(ocakavany label std 200-350 cp pre silne pozicie, nie menej).

Paralelizacia: --shards N rozdeli vstup na N kusov a spusti N stockfish
procesov naraz (1 vlakno na proces); vystupy sa spoja do jedneho CSV.

Pouzitie:
  python3 tests/tuning/sf_label.py --sf /usr/local/bin/stockfish \
    --input scratch/texel_2m_mix.csv --out scratch/texel_2m_labeled.csv \
    --depth 12 --shards 8
"""

from __future__ import annotations

import argparse
import csv
import os
import subprocess
import sys
from typing import List, Optional


MATE_CP = 32000


class SFEngine:
    def __init__(self, path: str, depth: int):
        self.depth = depth
        self.proc = subprocess.Popen(
            [path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        self.send("uci")
        self.wait_for("uciok")
        self.send("setoption name Threads value 1")
        self.send("setoption name Hash value 64")
        self.send("isready")
        self.wait_for("readyok")

    def send(self, line: str) -> None:
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def readline(self) -> str:
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("SF stdout closed")
        return line.strip()

    def wait_for(self, token: str, max_lines: int = 100) -> None:
        for _ in range(max_lines):
            if self.readline() == token:
                return
        raise RuntimeError(f"SF did not emit {token}")

    def eval_cp(self, fen: str) -> int:
        self.send(f"position fen {fen}")
        self.send(f"go depth {self.depth}")
        score: Optional[int] = None
        while True:
            line = self.readline()
            if line.startswith("info "):
                parsed = parse_score(line)
                if parsed is not None:
                    score = parsed
            elif line.startswith("bestmove"):
                break
        if score is None:
            raise RuntimeError("no score before bestmove")
        return score

    def close(self) -> None:
        try:
            self.send("quit")
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()


def parse_score(info_line: str) -> Optional[int]:
    toks = info_line.split()
    for i in range(len(toks) - 2):
        if toks[i] == "score" and toks[i + 1] == "cp":
            try:
                return int(toks[i + 2])
            except ValueError:
                return None
        if toks[i] == "score" and toks[i + 1] == "mate":
            try:
                mate = int(toks[i + 2])
            except ValueError:
                return None
            return MATE_CP - min(1000, mate) if mate > 0 else (
                -MATE_CP - max(-1000, mate) if mate < 0 else 0)
    return None


def label_shard(sf_path: str, depth: int, rows: List[dict],
                fields: List[str], out_path: str, shard_id: int) -> int:
    eng = SFEngine(sf_path, depth)
    done = 0
    try:
        with open(out_path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields + ["eval_cp"])
            w.writeheader()
            for row in rows:
                try:
                    cp = eng.eval_cp(row["fen"])
                except Exception as exc:
                    print(f"shard{shard_id}: eval fail fen={row['fen']}: {exc}",
                          file=sys.stderr)
                    continue
                row = dict(row)
                row["eval_cp"] = str(cp)
                w.writerow(row)
                done += 1
                if done % 5000 == 0:
                    print(f"shard{shard_id}: {done}/{len(rows)}", flush=True)
    finally:
        eng.close()
    return done


def main() -> int:
    ap = argparse.ArgumentParser(description="SF labeling of Texel CSV")
    ap.add_argument("--sf", required=True, help="stockfish binary")
    ap.add_argument("--input", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--depth", type=int, default=12)
    ap.add_argument("--shards", type=int, default=1)
    ap.add_argument("--audit-sample", type=int, default=1000)
    args = ap.parse_args()

    with open(args.input, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        fields = list(reader.fieldnames or [])
    if not rows:
        print("error: empty input", file=sys.stderr)
        return 2
    if "eval_cp" in fields:
        fields.remove("eval_cp")

    n = len(rows)
    size = (n + args.shards - 1) // args.shards
    procs = []
    tmp_paths = []
    env = dict(os.environ, SF_PATH=args.sf, SF_DEPTH=str(args.depth),
               SF_SHARD_WORKER="1")
    for s in range(args.shards):
        chunk = rows[s * size:(s + 1) * size]
        if not chunk:
            continue
        tmp = f"{args.out}.shard{s}"
        tmp_paths.append((s, tmp))
        p = subprocess.Popen(
            [sys.executable, __file__, "--sf", args.sf,
             "--input", "-", "--out", tmp,
             "--depth", str(args.depth), "--shards", "1",
             "--audit-sample", "0"],
            stdin=subprocess.PIPE, env=env, text=True)
        import json
        p.stdin.write(json.dumps({"rows": chunk, "fields": fields}))
        p.stdin.close()
        procs.append(p)

    for p in procs:
        p.wait()

    merged = 0
    with open(args.out, "w", newline="") as out:
        w = None
        for _, tmp in tmp_paths:
            with open(tmp, "r", encoding="utf-8", newline="") as f:
                reader = csv.DictReader(f)
                if w is None:
                    w = csv.DictWriter(out, fieldnames=reader.fieldnames)
                    w.writeheader()
                for row in reader:
                    w.writerow(row)
                    merged += 1
            os.remove(tmp)
    print(f"sf_label done: {merged}/{n} -> {args.out}")

    if args.audit_sample > 0 and merged > 0:
        import random
        rng = random.Random(7)
        with open(args.out, "r", encoding="utf-8", newline="") as f:
            vals = [abs(float(r["eval_cp"]))
                    for r in rng.sample(list(csv.DictReader(f)),
                                        min(args.audit_sample, merged))]
        mean = sum(vals) / len(vals)
        var = sum((x - mean) ** 2 for x in vals) / len(vals)
        std = var ** 0.5
        print(f"audit: sample={len(vals)} |cp| mean={mean:.1f} std={std:.1f} "
              f"min={min(vals):.0f} max={max(vals):.0f}")
        if std < 200.0 or std > 350.0:
            print("warning: audit std outside 200-350 cp band", file=sys.stderr)
    return 0


def shard_worker() -> int:
    import json
    payload = json.load(sys.stdin)
    # argparse-compatible minimal path: env override for sf/depth
    sf = os.environ["SF_PATH"]
    depth = int(os.environ.get("SF_DEPTH", "12"))
    return label_shard(sf, depth, payload["rows"], payload["fields"],
                       sys.argv[sys.argv.index("--out") + 1], 0)


if __name__ == "__main__":
    if os.environ.get("SF_SHARD_WORKER") == "1":
        raise SystemExit(shard_worker())
    raise SystemExit(main())
