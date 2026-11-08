#!/usr/bin/env python3
"""Outcome-Texel (Geddis) optimizer nad eval_tune.inc konstantami.

Loss: game-outcome cross-entropy — pre eval e (white perspective) je
p = sigmoid(e / scale) a loss = -mean[ r*log p + (1-r)*log(1-p) ].
Scale ~400 cp (standard). NIE cp-MSE.

Rozdiel oproti coordinate_descent.py (greedy per-weight, paired-z, kazdy
krok = rebuild + labeling celej subsetu): tu je plny gradient descent cez
vsetky parametre naraz, s labelingom len konstantny pocet krat na zaciatku:

  1. Batch labeling: raz sa nalabeluje cely vzorok (--sample) pri default
     parametroch. Engine: texel_label_eval.Engine (EM0 pin, classic eval),
     go depth 1. Engine vracia score cp z perspektivy strany na tahu →
     flip na white-perspective podla 2. polozky FENu (result v CSV je
     vzdy z pohladu bieleho).
  2. Linearna aproximacia evalu podla parametrov: pre kazdy parameter sa
     na malom vzorke (--grad-sample, default 20 pozicii) numericky odhadne
     d(eval)/d(param) cez ±1 zmenu (2 buildy + 2 male labelingu na
     parameter). Labeling je drahy, preto sa derivacie zmrazia a GD iteruje
     cisto v pamati. Model:
       k < G (grad vzorka):  eval_k ~= eval0_k + sum_i J[i][k] * Delta_i
                             (per-position derivacie, presne olabelovane)
       k >= G (ostatne):     eval_k ~= eval0_k + sum_i m_i * Delta_i
                             (m_i = mean J zo vzorky, uniform shift)
  3. Gradient descent s normalizovanym krokom: pociatocny krok --lr je
     fracia typickej velkosti parametra (backtracking halvenie kym loss
     neklesne), clamp Delta do [min-default, max-default]. Loss aj gradient
     sa pocitaju na VSETKICH olabelovanych poziciach naraz (nie per-param
     greedy ako coordinate_descent).

Vystup: odporucene zmeny parametrov + odhad outcome loss pred/po.
  --verify: odporucene hodnoty sa aplikuju, rebuildne sa a zmeria SKUTOCNY
            loss (re-label celej vzorky) — overi kvalitu linearizacie.
  --apply:  odporucene hodnoty zostanu v eval_tune.inc.
  default:  subor sa po dobehnuti obnovi (tool je read-only odporucac).

Pouzitie (VPS, texel_2m_mix.csv):
  python3 tests/tuning/outcome_texel.py \
      --csv scratch/texel_2m_mix.csv \
      --params "BISHOP_PAIR:20:60:43,DOUBLED_PEN:4:20:12,ISOLATED_PEN:5:25:15,ROOK_OPEN:10:40:25,TEMPO_BONUS:10:40:28" \
      --sample 20000 --iters 100 --scale 400 --verify

Smoke:
  python3 tests/tuning/outcome_texel.py --csv <maly_test.csv> \
      --params "BISHOP_PAIR:20:60:43,DOUBLED_PEN:4:20:12,ISOLATED_PEN:5:25:15,ROOK_OPEN:10:40:25,TEMPO_BONUS:10:40:28" \
      --sample 500 --iters 10 --verify
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import random
import re
import subprocess
import sys
from dataclasses import dataclass

from texel_label_eval import Engine

EQ_RE = re.compile(r"^(\s*)([A-Za-z_][A-Za-z0-9_]*)(\s+equ\s+)(-?[0-9]+)(.*)$")


@dataclass
class Param:
    name: str
    lo: int
    hi: int
    default: int


def parse_params(spec: str) -> list[Param]:
    params = []
    seen = set()
    for item in spec.split(","):
        item = item.strip()
        if not item:
            continue
        parts = item.split(":")
        if len(parts) != 4:
            raise ValueError(f"params item '{item}': ocakavany format meno:min:max:default")
        name = parts[0].strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            raise ValueError(f"params item '{item}': zle meno '{name}'")
        if name in seen:
            raise ValueError(f"params item '{item}': duplicitne meno '{name}'")
        try:
            lo, hi, default = (int(parts[1]), int(parts[2]), int(parts[3]))
        except ValueError:
            raise ValueError(f"params item '{item}': min/max/default musia byt cele cisla")
        if lo > hi:
            raise ValueError(f"params item '{item}': min > max")
        if not (lo <= default <= hi):
            raise ValueError(f"params item '{item}': default mimo rozsahu [min,max]")
        seen.add(name)
        params.append(Param(name, lo, hi, default))
    if not params:
        raise ValueError("--params nesmie byt prazdny")
    return params


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Outcome-Texel (Geddis) optimizer over eval_tune.inc")
    p.add_argument("--csv", default="tests/reports/texel_dataset.csv",
                   help="CSV s fen,result (result 0/0.5/1 z pohladu bieleho)")
    p.add_argument("--params", required=True, help="MENO:min:max:default,...")
    p.add_argument("--sample", type=int, default=20000, help="pozicie pre outcome loss")
    p.add_argument("--iters", type=int, default=100)
    p.add_argument("--scale", type=float, default=400.0, help="sigmoid scale v cp (standard 400)")
    p.add_argument("--grad-sample", type=int, default=20, help="pozicie na numericku derivaciu/param")
    p.add_argument("--lr", type=float, default=0.25,
                   help="pociatocny GD krok ako fracia typickeho parametra (backtracking halvenie)")
    p.add_argument("--clip-cp", type=float, default=2000.0, help="clip |eval_cp| pred sigmoidom (0=vyp)")
    p.add_argument("--seed", type=int, default=20261108)
    p.add_argument("--eval-tune", default="src/eval_tune.inc")
    p.add_argument("--build-cmd", default="make chess-static")
    p.add_argument("--engine", default="./chess-static")
    p.add_argument("--go", default="depth 1")
    p.add_argument("--report", default="tests/reports/outcome_texel.csv", help="iteracna historia GD")
    p.add_argument("--recs", default="tests/reports/outcome_texel_recs.csv", help="odporucene zmeny")
    p.add_argument("--log", default="tests/reports/outcome_texel.log")
    p.add_argument("--verify", action="store_true", help="zmeraj skutocny loss odporucanych hodnot (rebuild + re-label)")
    p.add_argument("--apply", action="store_true", help="ponechaj odporucene hodnoty v eval_tune.inc")
    return p.parse_args()


def log(msg: str, path: str) -> None:
    line = f"[{subprocess.check_output(['date', '+%H:%M:%S']).decode().strip()}] {msg}"
    print(line, flush=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def run(cmd: str) -> int:
    return subprocess.run(cmd, shell=True).returncode


def load_weights(path: str):
    weights = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            m = EQ_RE.match(line.rstrip("\n"))
            if m:
                weights[m.group(2)] = int(m.group(4))
    return weights


def write_weights(path: str, weights) -> None:
    lines = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            m = EQ_RE.match(line.rstrip("\n"))
            if m and m.group(2) in weights:
                nl = "\n" if line.endswith("\n") else ""
                lines.append(f"{m.group(1)}{m.group(2)}{m.group(3)}{weights[m.group(2)]}{m.group(5)}{nl}")
            else:
                lines.append(line)
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)


def load_rows(path: str, n: int, seed: int):
    """Nacita CSV, overi fen/result, zamiesa (seed) a vrati prvych n riadkov."""
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if not {"fen", "result"}.issubset(set(reader.fieldnames or [])):
            raise ValueError(f"{path}: chybaju stlpce fen/result")
        rows = []
        for r in reader:
            try:
                res = float(r["result"])
            except (TypeError, ValueError):
                continue
            if res not in (0.0, 0.5, 1.0):
                continue
            rows.append((r["fen"], res))
    random.Random(seed).shuffle(rows)
    return rows[:n]


def label_white(engine_path: str, go: str, fens) -> list[float]:
    """Labeling cez Engine (EM0 pin). Vrati eval_cp z white perspective."""
    eng = Engine.start(engine_path, go)
    out = []
    try:
        for fen in fens:
            ev = eng.eval_cp(fen)
            stm_white = fen.split()[1] == "w"
            out.append(ev if stm_white else -ev)
    finally:
        eng.close()
    return out


def clip_eval(ev: float, clip_cp: float) -> float:
    if clip_cp > 0:
        return max(-clip_cp, min(clip_cp, ev))
    return ev


def loss_and_probs(eval_white, results, scale: float, clip_cp: float):
    eps = 1e-12
    total = 0.0
    probs = []
    for ev, r in zip(eval_white, results):
        x = clip_eval(ev, clip_cp) / scale
        x = max(-40.0, min(40.0, x))
        pr = 1.0 / (1.0 + math.exp(-x))
        pr = min(1.0 - eps, max(eps, pr))
        probs.append(pr)
        total += -(r * math.log(pr) + (1.0 - r) * math.log(1.0 - pr))
    return total / max(1, len(results)), probs


def loss_and_grad(e0, results, j_in, derivs, delta, g: int, scale: float, clip_cp: float):
    """Outcome loss + gradient na linearnom modeli.

    Pozicie k < g: per-position linearna aproximacia
      eval_k ~ e0_k + sum_i j_in[i][k] * delta_i   (presne olabelovane +-1)
    Pozicie k >= g: skalarny mean derivacie (uniform shift)
      eval_k ~ e0_k + sum_i derivs[i] * delta_i
    Gradient: dL/ddelta_i = mean_k [(p_k - r_k) * d eval_k/d delta_i] / scale
    Vrati (loss, grad list, resid_in list pre k < g).
    """
    eps = 1e-12
    n = len(results)
    p = len(derivs)
    shift_out = sum(m * d for m, d in zip(derivs, delta))
    total = 0.0
    resid_out = 0.0
    for k in range(g, n):
        x = clip_eval(e0[k] + shift_out, clip_cp) / scale
        x = max(-40.0, min(40.0, x))
        pr = 1.0 / (1.0 + math.exp(-x))
        pr = min(1.0 - eps, max(eps, pr))
        r = results[k]
        total += -(r * math.log(pr) + (1.0 - r) * math.log(1.0 - pr))
        resid_out += pr - r

    resid_in = []
    for k in range(g):
        ev = e0[k]
        for i in range(p):
            d = delta[i]
            if d != 0.0:
                ev += j_in[i][k] * d
        x = clip_eval(ev, clip_cp) / scale
        x = max(-40.0, min(40.0, x))
        pr = 1.0 / (1.0 + math.exp(-x))
        pr = min(1.0 - eps, max(eps, pr))
        r = results[k]
        total += -(r * math.log(pr) + (1.0 - r) * math.log(1.0 - pr))
        resid_in.append(pr - r)

    grad = []
    for i in range(p):
        s = derivs[i] * resid_out
        jcol = j_in[i]
        for k in range(g):
            s += resid_in[k] * jcol[k]
        grad.append(s / (scale * n))
    return total / max(1, n), grad, resid_in


def build_or_die(build_cmd: str, log_path: str) -> None:
    if run(build_cmd + " >/dev/null 2>&1") != 0:
        log("ERROR: build failed", log_path)
        raise RuntimeError("build failed")


def main() -> int:
    args = parse_args()
    params = parse_params(args.params)

    weights = load_weights(args.eval_tune)
    missing = [p.name for p in params if p.name not in weights]
    if missing:
        print(f"error: parametre neexistuju v {args.eval_tune}: {missing}", file=sys.stderr)
        return 2

    rows = load_rows(args.csv, args.sample, args.seed)
    if len(rows) < max(10, args.grad_sample):
        print(f"error: {args.csv}: malo pozicii ({len(rows)})", file=sys.stderr)
        return 2
    fens = [f for f, _ in rows]
    results = [r for _, r in rows]
    log(f"start: {len(params)} params, sample={len(rows)}, iters={args.iters}, "
        f"scale={args.scale}, grad_sample={args.grad_sample}", args.log)

    original = open(args.eval_tune, "r", encoding="utf-8").read()
    file_values = {p.name: weights_before_default(p, original) for p in params}

    work_fens = fens[: args.grad_sample]
    iter_rows = []
    apply_values = None
    try:
        # 1) baseline: parametre na default, build, batch labeling vsetkych pozicii
        for p in params:
            weights[p.name] = p.default
        write_weights(args.eval_tune, weights)
        build_or_die(args.build_cmd, args.log)
        log("baseline labeling (all positions)...", args.log)
        e0 = label_white(args.engine, args.go, fens)
        base_loss, _ = loss_and_probs(e0, results, args.scale, args.clip_cp)
        log(f"baseline outcome loss = {base_loss:.6f}", args.log)

        # 2) numericke derivacie: +-1 na parameter, male labelingy na rovnakom vzorke;
        #    per-position J pre k < G, skalarny mean (uniform shift) pre zvysok
        j_in = []
        derivs = []
        for p in params:
            plus = min(p.hi, p.default + 1)
            minus = max(p.lo, p.default - 1)
            e_plus = e_minus = None
            if plus != p.default:
                weights[p.name] = plus
                write_weights(args.eval_tune, weights)
                build_or_die(args.build_cmd, args.log)
                e_plus = label_white(args.engine, args.go, work_fens)
                log(f"grad {p.name}: +1 -> {plus} labeled", args.log)
            if minus != p.default:
                weights[p.name] = minus
                write_weights(args.eval_tune, weights)
                build_or_die(args.build_cmd, args.log)
                e_minus = label_white(args.engine, args.go, work_fens)
                log(f"grad {p.name}: -1 -> {minus} labeled", args.log)
            weights[p.name] = p.default
            per_pos = []
            for k in range(len(work_fens)):
                if e_plus is not None and e_minus is not None:
                    per_pos.append((e_plus[k] - e_minus[k]) / (plus - minus))
                elif e_plus is not None:
                    per_pos.append((e_plus[k] - e0[k]) / (plus - p.default))
                elif e_minus is not None:
                    per_pos.append((e0[k] - e_minus[k]) / (p.default - minus))
                else:
                    per_pos.append(0.0)
            j_in.append(per_pos)
            m = sum(per_pos) / len(per_pos)
            derivs.append(m)
            mag = max(abs(v) for v in per_pos)
            log(f"grad {p.name}: mean d eval/dp = {m:+.4f} cp/1 (max |per-pos| {mag:.2f}, "
                f"aktivne {sum(1 for v in per_pos if abs(v) > 1e-9)}/{len(per_pos)})", args.log)

        # 3) gradient descent na linearizovanom modeli (cisto v pamati)
        n = len(results)
        g = len(work_fens)
        typ = sum(abs(p.default) for p in params) / len(params)
        delta = [0.0] * len(params)
        best = list(delta)
        best_loss = base_loss
        cur_loss = base_loss
        for it in range(1, args.iters + 1):
            _, grad, _ = loss_and_grad(e0, results, j_in, derivs, delta, g,
                                       args.scale, args.clip_cp)
            gnorm = math.sqrt(sum(x * x for x in grad))
            if gnorm < 1e-15:
                log(f"iter {it}: zero gradient, stop", args.log)
                break

            accepted = False
            step = args.lr * typ / gnorm
            cand = None
            cand_loss = None
            move = 0.0
            for _ in range(14):
                trial = [max(p.lo - p.default, min(p.hi - p.default, d - step * x))
                         for d, x, p in zip(delta, grad, params)]
                trial_loss, _, _ = loss_and_grad(e0, results, j_in, derivs, trial, g,
                                                 args.scale, args.clip_cp)
                if trial_loss < cur_loss - 1e-10:
                    accepted = True
                    cand = trial
                    cand_loss = trial_loss
                    move = max(abs(t - d) for t, d in zip(trial, delta))
                    break
                step *= 0.5
            if not accepted:
                log(f"iter {it}: no improvement (step exhausted), stop", args.log)
                break
            delta = cand
            cur_loss = cand_loss
            if cur_loss < best_loss:
                best_loss = cand_loss
                best = list(delta)
            log(f"iter {it}: loss={cur_loss:.8f} move={move:.3f} gnorm={gnorm:.3e} "
                f"max|d|={max(abs(x) for x in delta):.2f}", args.log)
            iter_rows.append({"iter": it, "loss": f"{cur_loss:.8f}", "move": f"{move:.3f}",
                              "grad_norm": f"{gnorm:.3e}",
                              **{f"d_{p.name}": f"{d:.3f}" for d, p in zip(delta, params)}})

        recs = []
        for p, d in zip(params, best):
            new_val = max(p.lo, min(p.hi, int(round(p.default + d))))
            recs.append((p, file_values[p.name], new_val))
        log(f"predicted outcome loss: {base_loss:.6f} -> {best_loss:.6f} "
            f"(linearizovany odhad)", args.log)
        for p, cur, new_val in recs:
            log(f"rec {p.name}: file={cur} default={p.default} -> {new_val} "
                f"(delta {new_val - p.default:+d}, rozsah [{p.lo},{p.hi}])", args.log)

        # 4) optional verify: skutocny loss odporucanych hodnot
        verified = None
        if args.verify:
            rec_weights = dict(weights)
            for p, _, new_val in recs:
                rec_weights[p.name] = new_val
            write_weights(args.eval_tune, rec_weights)
            build_or_die(args.build_cmd, args.log)
            log("verify: re-label vsetkych pozicii s odporucanymi hodnotami...", args.log)
            e_ver = label_white(args.engine, args.go, fens)
            verified, _ = loss_and_probs(e_ver, results, args.scale, args.clip_cp)
            log(f"verified outcome loss = {verified:.6f} (baseline {base_loss:.6f})", args.log)

        # 5) reporty
        os.makedirs(os.path.dirname(args.report) or ".", exist_ok=True)
        with open(args.report, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["iter", "loss", "move", "grad_norm"] +
                               [f"d_{p.name}" for p in params])
            w.writeheader()
            w.writerows(iter_rows)
        with open(args.recs, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(["name", "file_value", "default", "recommended", "delta",
                        "loss_before", "loss_after_pred"])
            for p, cur, new_val in recs:
                w.writerow([p.name, cur, p.default, new_val, new_val - p.default,
                            f"{base_loss:.6f}", f"{best_loss:.6f}"])

        print("\n=== outcome_texel summary ===")
        print(f"positions : {n} (grad sample {len(work_fens)})")
        print(f"loss pred : {base_loss:.6f}")
        print(f"loss po   : {best_loss:.6f} (linearizovany odhad)"
              + (f" | verified {verified:.6f}" if verified is not None else ""))
        print("odporucene zmeny:")
        for p, cur, new_val in recs:
            mark = "" if cur == new_val else "   <-- zmena"
            print(f"  {p.name:22s} file={cur:5d} -> {new_val:5d} (delta {new_val - cur:+d}){mark}")
        print(f"report: {args.report}")
        print(f"recs  : {args.recs}")
        if args.apply:
            apply_values = {p.name: new_val for p, _, new_val in recs}
        return 0
    finally:
        with open(args.eval_tune, "w", encoding="utf-8") as f:
            f.write(original)
        if apply_values:
            keep = load_weights(args.eval_tune)
            keep.update(apply_values)
            write_weights(args.eval_tune, keep)
            log(f"applied recommended values: {apply_values}", args.log)
        # rebuild s obnovenymi (alebo apply-ovanymi) hodnotami, aby binarka sedela so zdrojom
        run(args.build_cmd + " >/dev/null 2>&1")


def weights_before_default(p: Param, original: str) -> int:
    """Povodna (file) hodnota parametra pred behom."""
    m = re.search(rf"^\s*{re.escape(p.name)}\s+equ\s+(-?[0-9]+)", original, re.M)
    return int(m.group(1)) if m else p.default


if __name__ == "__main__":
    sys.exit(main())
