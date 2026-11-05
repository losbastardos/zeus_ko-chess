#!/usr/bin/env python3
"""king_safety_probe.py — sonda zhody evalu engine oproti referencii.

Referencia su SF 18 labele (STS 100 FENov, SF d14, perspektiva STM):
  scratch/sts1_sf14_labels.csv  (stlpce: fen,sf_cp)

Metriky (gap = |engine_cp - ref_cp|, vsetko v centipawnoch):
  mean / median / max gap + Pearson korelacia
Dual kriter PASS: median <= 60 a max <= 180. FAIL nie je alarm,
znamena to len trend — rozhoduje casova rada sond.

Priklady:
  # classic eval (EM0) vs SF:
  python3 tests/tuning/king_safety_probe.py --engine ./chess-static \
      --eval-mode 0 --sf-labels scratch/sts1_sf14_labels.csv
  # NNUE v3 net (EM2, net z chess.ini) vs SF:
  python3 tests/tuning/king_safety_probe.py --engine ./chess-static \
      --eval-mode 2 --sf-labels scratch/sts1_sf14_labels.csv
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
from typing import List, Optional, Tuple

from texel_label_eval import Engine, parse_score


def pearson(xs: List[float], ys: List[float]) -> float:
    n = len(xs)
    if n < 2:
        return 0.0
    mx = sum(xs) / n
    my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    if sxx < 1e-12 or syy < 1e-12:
        return 0.0
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    return sxy / math.sqrt(sxx * syy)


def percentile_median(vals: List[float]) -> float:
    s = sorted(vals)
    n = len(s)
    if n == 0:
        return 0.0
    if n % 2 == 1:
        return s[n // 2]
    return (s[n // 2 - 1] + s[n // 2]) / 2.0


def load_labels(path: str) -> List[Tuple[str, float]]:
    rows: List[Tuple[str, float]] = []
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if "fen" not in (reader.fieldnames or []) or "sf_cp" not in (reader.fieldnames or []):
            raise ValueError(f"{path}: ocakavane stlpce fen,sf_cp")
        for row in reader:
            rows.append((row["fen"], float(row["sf_cp"])))
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description="King safety / eval probe vs SF reference")
    ap.add_argument("--engine", required=True, help="engine binary")
    ap.add_argument("--sf-labels", required=True, help="CSV fen,sf_cp (SF d14 labels)")
    ap.add_argument("--reference", choices=["sf", "em0"], default="sf",
                    help="sf = SF labele (default, kanonicke); em0 = legacy — "
                         "referencia je EvalMode 0 z toho isteho engine")
    ap.add_argument("--eval-mode", type=int, default=0,
                    help="EvalMode pre testovany engine (0=classic, 2=NNUE v3)")
    ap.add_argument("--go", default="depth 1", help="UCI go arguments")
    ap.add_argument("--score-scale", type=float, default=10.0)
    ap.add_argument("--median-limit", type=float, default=60.0)
    ap.add_argument("--max-limit", type=float, default=180.0)
    args = ap.parse_args()

    labels = load_labels(args.sf_labels)
    if not labels:
        print("error: prazdne labele", file=sys.stderr)
        return 2

    # Engine.start pina EvalMode=0. Pre --reference em0 bezi druha instancia
    # ako EM0 baseline; pre --reference sf su referencne hodnoty labely.
    ref = None
    if args.reference == "em0":
        ref = Engine.start(args.engine, args.go, score_scale=args.score_scale)
    test = Engine.start(args.engine, args.go, score_scale=args.score_scale)
    if args.eval_mode != 0 or args.reference == "em0":
        test.send(f"setoption name EvalMode value {args.eval_mode}")
        test.send("isready")
        test.wait_for("readyok")

    gaps: List[float] = []
    eng_vals: List[float] = []
    ref_vals: List[float] = []
    try:
        for i, (fen, sf_cp) in enumerate(labels):
            if args.reference == "em0":
                ref_cp = ref.eval_cp(fen)
            else:
                ref_cp = sf_cp
            val = test.eval_cp(fen)
            eng_vals.append(val)
            ref_vals.append(ref_cp)
            gaps.append(abs(val - ref_cp))
            if (i + 1) % 25 == 0:
                print(f"processed: {i + 1}/{len(labels)}")
    finally:
        if ref is not None:
            ref.close()
        test.close()

    mean_gap = sum(gaps) / len(gaps)
    med_gap = percentile_median(gaps)
    max_gap = max(gaps)
    corr = pearson(eng_vals, ref_vals)

    passed = med_gap <= args.median_limit and max_gap <= args.max_limit
    print(f"n={len(gaps)} mean|gap|={mean_gap:.0f} median|gap|={med_gap:.0f} "
          f"max|gap|={max_gap:.0f} corr={corr:.3f}")
    print(f"criterion: median<={args.median_limit:.0f} max<={args.max_limit:.0f} "
          f"-> {'PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
