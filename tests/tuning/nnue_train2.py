#!/usr/bin/env python3
"""NNUE trainer - phase 2: one-hidden-layer net (numpy).

Features (STM-relative, HalfKP-lite):
  non-king: (color_rel 0/1) x (type P,N,B,R,Q -> 5) x (rel_sq 64) = 640
  kings:    (color_rel 0/1) x (rel_sq 64)                      = 128
  total F = 768

Net: eval_cp = W2 . CReLU(W1^T x + b1) + b2
  CReLU(z) = clip(z, 0, 255) - quantization-friendly ReLU
Training:
    --target result: logistic on game result, eval_cp/scale as logit; L2.
    --target cp: MSE na eval_cp (STM-perspective), vhodne pre cp-label retrain; L2.
Export net.nnue v2:
  magic "NNUE" u32, version u32 = 2
  H u32, shift1 u32 (log2 of W1 output scale), shift2 u32
  b1: H x int32 ; W1: F x H int16 (row-major: feature-major)
  b2: int32 ; W2: H x int16
Inference (asm mirrors this):
  acc[j] = sum_i x[i]*W1[i][j] + b1[j]      (int32)
  h[j]   = clip(acc[j] >> shift1, 0, 255)
  eval   = (sum_j h[j]*W2[j] + b2) >> shift2 (cp)

Usage:
  python3 tests/tuning/nnue_train2.py --dataset tests/reports/texel_dataset.csv \
      [--dataset tests/reports/selfplay.csv ...] --out net2.nnue --epochs 60
"""

from __future__ import annotations

import argparse
import csv
import math
import struct
import sys

import numpy as np

try:
    import chess
except Exception as exc:  # pragma: no cover
    print(f"error: python-chess required ({exc})", file=sys.stderr)
    raise SystemExit(2)

PIECES = [chess.PAWN, chess.KNIGHT, chess.BISHOP, chess.ROOK, chess.QUEEN]
F_NONKING = 2 * 5 * 64          # 640
F_KING = 2 * 64                 # 128
F = F_NONKING + F_KING          # 768
MAGIC = b"NNUE"
VERSION = 2
PHASE_W = {chess.PAWN: 0, chess.KNIGHT: 1, chess.BISHOP: 1,
           chess.ROOK: 2, chess.QUEEN: 4, chess.KING: 0}
PHASE_MAX = 24


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="NNUE phase-2 trainer (1 hidden layer)")
    p.add_argument("--dataset", action="append", default=[],
                   help="Texel CSV (can repeat); default texel_dataset.csv")
    p.add_argument("--out", default="net2.nnue")
    p.add_argument("--hidden", type=int, default=96)
    p.add_argument("--epochs", type=int, default=60)
    p.add_argument("--lr", type=float, default=0.005)
    p.add_argument("--l2", type=float, default=1e-5)
    p.add_argument("--scale", type=float, default=233.0)
    p.add_argument("--batch", type=int, default=4096)
    p.add_argument("--seed", type=int, default=20260917)
    p.add_argument("--report", default="tests/reports/nnue_train2.txt")
    p.add_argument("--max-positions", type=int, default=0)
    p.add_argument("--valid-ratio", type=float, default=0.04,
                   help="fraction of rows for validation split (0 disables)")
    p.add_argument("--valid-max", type=int, default=20000,
                   help="max validation rows after ratio split (0=no cap)")
    p.add_argument("--patience", type=int, default=0,
                   help="early-stop patience in epochs on validation metric (0=off)")
    p.add_argument("--gate-pass", type=float, default=0.30,
                   help="PASS threshold for mse/variance ratio")
    p.add_argument("--gate-warn", type=float, default=0.50,
                   help="WARN upper threshold for mse/variance ratio")
    p.add_argument("--fail-fast-ratio", type=float, default=1.0,
                   help="early fail if epoch-1 val mse/variance exceeds this threshold (0=off)")
    p.add_argument("--target", choices=["result", "cp"], default="result",
                   help="result=logloss na game result, cp=MSE na eval_cp")
    p.add_argument("--cp-clip", type=float, default=2000.0,
                   help="clip cieloveho eval_cp pri --target cp (0=bez clipu)")
    p.add_argument("--cp-label-perspective", choices=["stm", "white"], default="stm",
                   help="perspektiva eval_cp v datasete: stm (UCI score cp) alebo white")
    return p.parse_args()


def build_features(board: chess.Board) -> np.ndarray:
    x = np.zeros(F, dtype=np.float32)
    stm_white = board.turn == chess.WHITE
    for sq in chess.SQUARES:
        pc = board.piece_at(sq)
        if pc is None:
            continue
        rsq = sq if stm_white else (sq ^ 56)
        own = 0 if pc.color == board.turn else 1
        if pc.piece_type == chess.KING:
            x[F_NONKING + own * 64 + rsq] = 1.0
        else:
            pt = PIECES.index(pc.piece_type)
            x[(own * 5 + pt) * 64 + rsq] = 1.0
    return x


def load_rows(paths, max_pos: int, target: str, cp_clip: float, cp_perspective: str):
    rows = []
    for path in paths:
        with open(path, "r", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                try:
                    fen = r["fen"]
                except Exception:
                    continue
                stm_black = fen.split()[1] == "b"
                if target == "cp":
                    try:
                        val = float(r["eval_cp"])
                    except Exception:
                        continue
                    # Trening cp targetu je STM-relativny. UCI `score cp` je
                    # standardne tiez z pohladu strany na tahu, preto defaultne
                    # NEROBIME ziadny flip. Legacy datasety s bielou perspektivou
                    # podporujeme explicitne cez --cp-label-perspective white.
                    if cp_perspective == "white" and stm_black:
                        val = -val
                    if cp_clip > 0:
                        val = max(-cp_clip, min(cp_clip, val))
                    rows.append((fen, val))
                else:
                    try:
                        val = float(r["result"])
                    except Exception:
                        continue
                    # Label v Texel CSV je z pohladu BIELEHO (1.0 = vyhra bieleho),
                    # ale build_features koduje farby relativne voci strane na tahu.
                    # Pre pozicie, kde taha cierny, treba label preklopit.
                    if stm_black:
                        val = 1.0 - val
                    rows.append((fen, val))
    if max_pos and len(rows) > max_pos:
        rows = rows[:max_pos]
    return rows


def main() -> int:
    args = parse_args()
    if not args.dataset:
        args.dataset = ["tests/reports/texel_dataset.csv"]
    rng = np.random.default_rng(args.seed)
    H = args.hidden

    rows = load_rows(args.dataset, args.max_positions, args.target, args.cp_clip,
                     args.cp_label_perspective)
    n = len(rows)
    if n == 0:
        print("error: empty dataset after parsing/filtering", file=sys.stderr)
        return 2
    print(f"dataset: {n} positions (H={H})", flush=True)

    X = np.empty((n, F), dtype=np.float32)
    y = np.empty(n, dtype=np.float32)
    for i, (fen, res) in enumerate(rows):
        X[i] = build_features(chess.Board(fen))
        y[i] = res

    idx_all = rng.permutation(n)
    valid_n = 0
    if args.valid_ratio > 0.0 and n >= 2:
        valid_n = int(n * args.valid_ratio)
        if valid_n <= 0:
            valid_n = 1
        if args.valid_max > 0:
            valid_n = min(valid_n, args.valid_max)
        valid_n = min(valid_n, n - 1)
    valid_idx = idx_all[:valid_n]
    train_idx = idx_all[valid_n:]
    n_train = int(train_idx.shape[0])
    n_valid = int(valid_idx.shape[0])
    print(f"split: train={n_train} valid={n_valid}", flush=True)

    # inicializacia: b1 kladne (jednotky zacinaju aktivne v CReLU pasme),
    # W1 vacsie aby pre-aktivacie zily v rozumnom rozsahu (~jednotky cp)
    W1 = rng.normal(0.0, 0.05, size=(F, H)).astype(np.float32)
    b1 = np.full(H, 0.5, dtype=np.float32)
    W2 = rng.normal(0.0, 0.02, size=H).astype(np.float32)
    b2 = np.float32(0.0)
    scale = np.float32(args.scale)

    bs = args.batch

    def eval_metric(indices: np.ndarray) -> float:
        if indices.size == 0:
            return float("nan")
        total = 0.0
        count = int(indices.shape[0])
        for s in range(0, count, bs):
            bid = indices[s:s + bs]
            xb = X[bid]
            yb = y[bid]
            z1 = xb @ W1 + b1
            h = np.clip(z1, 0.0, 255.0)
            ev = h @ W2 + b2
            if args.target == "cp":
                diff = ev - yb
                total += float((diff * diff).sum())
            else:
                z = np.clip(ev / scale, -40, 40)
                p = 1.0 / (1.0 + np.exp(-z))
                p = np.clip(p, 1e-12, 1 - 1e-12)
                total += float(-(yb * np.log(p) + (1 - yb) * np.log(1 - p)).sum())
        return total / count

    # Adam state
    mw1 = np.zeros_like(W1); vw1 = np.zeros_like(W1)
    mb1 = np.zeros_like(b1); vb1 = np.zeros_like(b1)
    mw2 = np.zeros_like(W2); vw2 = np.zeros_like(W2)
    mb2 = np.float32(0.0); vb2 = np.float32(0.0)
    b1m, b2m = 0.9, 0.999
    eps = 1e-8
    step = 0
    best_val = float("inf")
    best_val_epoch = 0
    best_snapshot = None
    stale_epochs = 0
    metric = float("nan")
    for epoch in range(args.epochs):
        order = train_idx[rng.permutation(n_train)]
        metric = 0.0
        for s in range(0, n_train, bs):
            idx = order[s:s + bs]
            xb = X[idx]
            yb = y[idx]
            m = xb.shape[0]
            step += 1
            # forward
            z1 = xb @ W1 + b1                    # (m,H)
            h = np.clip(z1, 0.0, 255.0)          # inference clip [0,255]
            ev = h @ W2 + b2                     # (m,)
            if args.target == "cp":
                # Priamy cp ciel: hladime eval v centipawnoch.
                diff = ev - yb
                metric += float((diff * diff).sum())
                d = diff / (scale * scale)       # (m,)
            else:
                z = np.clip(ev / scale, -40, 40)
                p = 1.0 / (1.0 + np.exp(-z))
                p = np.clip(p, 1e-12, 1 - 1e-12)
                metric += float(-(yb * np.log(p) + (1 - yb) * np.log(1 - p)).sum())
                d = (p - yb) / scale             # (m,)
            dW2 = h.T @ d / m + args.l2 * W2
            db2 = float(d.sum() / m)
            dh = np.outer(d, W2)                 # (m,H)
            dz1 = dh * (z1 > 0)                  # relu'
            dW1 = xb.T @ dz1 / m + args.l2 * W1
            db1 = dz1.sum(axis=0) / m
            # Adam updates
            mw1 = b1m * mw1 + (1 - b1m) * dW1
            vw1 = b2m * vw1 + (1 - b2m) * dW1 * dW1
            W1 -= args.lr * (mw1 / (1 - b1m ** step)) / (np.sqrt(vw1 / (1 - b2m ** step)) + eps)
            mb1 = b1m * mb1 + (1 - b1m) * db1
            vb1 = b2m * vb1 + (1 - b2m) * db1 * db1
            b1 -= args.lr * (mb1 / (1 - b1m ** step)) / (np.sqrt(vb1 / (1 - b2m ** step)) + eps)
            mw2 = b1m * mw2 + (1 - b1m) * dW2
            vw2 = b2m * vw2 + (1 - b2m) * dW2 * dW2
            W2 -= args.lr * (mw2 / (1 - b1m ** step)) / (np.sqrt(vw2 / (1 - b2m ** step)) + eps)
            mb2 = b1m * mb2 + (1 - b1m) * db2
            vb2 = b2m * vb2 + (1 - b2m) * db2 * db2
            b2 -= args.lr * (mb2 / (1 - b1m ** step)) / (math.sqrt(vb2 / (1 - b2m ** step)) + eps)
        metric /= n_train
        val_metric = float("nan")
        if n_valid > 0:
            val_metric = eval_metric(valid_idx)
            if val_metric < best_val:
                best_val = val_metric
                best_val_epoch = epoch + 1
                best_snapshot = (W1.copy(), b1.copy(), W2.copy(), np.float32(b2))
                stale_epochs = 0
            else:
                stale_epochs += 1
        if epoch == 0 or (epoch + 1) % 5 == 0:
            name = "mse_cp" if args.target == "cp" else "logloss"
            if n_valid > 0:
                print(f"epoch {epoch+1}: train_{name}={metric:.5f} val_{name}={val_metric:.5f}", flush=True)
            else:
                print(f"epoch {epoch+1}: {name}={metric:.5f}", flush=True)
        if args.target == "cp" and n_valid > 0 and (epoch + 1) == 1 and args.fail_fast_ratio > 0.0:
            var1 = float(np.var(y[valid_idx], ddof=0))
            ratio1 = (val_metric / var1) if var1 > 0 else float("inf")
            if ratio1 > args.fail_fast_ratio:
                print(f"fail_fast: epoch=1 val_ratio={ratio1:.6f} threshold={args.fail_fast_ratio:.6f}", flush=True)
                best_val = val_metric
                best_val_epoch = 1
                best_snapshot = (W1.copy(), b1.copy(), W2.copy(), np.float32(b2))
                break
        if args.patience > 0 and n_valid > 0 and stale_epochs >= args.patience:
            print(f"early_stop: epoch={epoch+1} best_val_epoch={best_val_epoch} best_val={best_val:.5f}", flush=True)
            break

    if best_snapshot is not None:
        W1, b1, W2, b2 = best_snapshot

    final_train_metric = eval_metric(train_idx)
    final_val_metric = eval_metric(valid_idx) if n_valid > 0 else float("nan")
    selected_metric = final_val_metric if n_valid > 0 else final_train_metric

    gate_status = "N/A"
    gate_var = float("nan")
    gate_ratio = float("nan")
    if args.target == "cp":
        gate_y = y[valid_idx] if n_valid > 0 else y[train_idx]
        gate_var = float(np.var(gate_y, ddof=0))
        if gate_var > 0:
            gate_ratio = selected_metric / gate_var
            if gate_ratio < args.gate_pass:
                gate_status = "PASS"
            elif gate_ratio <= args.gate_warn:
                gate_status = "WARN"
            else:
                gate_status = "FAIL"
        else:
            gate_status = "FAIL"

    if n_valid > 0:
        print(f"best_val_epoch={best_val_epoch} best_val={(best_val if best_val_epoch > 0 else float('nan')):.6f}", flush=True)
    if args.target == "cp":
        split_name = "val" if n_valid > 0 else "train"
        print(f"gate[{split_name}]: mse={selected_metric:.6f} variance={gate_var:.6f} ratio={gate_ratio:.6f} status={gate_status}", flush=True)

    # Kvantizacia: jednotny fixed-point scaling S = 2^shift pre vahy aj biasy.
    # asm inference: acc = sum x*W1q + b1q ; h = clip(acc>>shift1, 0, 255)
    #                eval_cp = (sum h*W2q + b2q) >> shift2
    # Pozor: vahy a biasy MUSIA mat rovnaku skalu (S), inak sa funknet
    # zdeformuje o konstantny faktor (starsi export x128/x2048 so shiftom 11
    # stisol prispevok vah 16x a vysledna siet bola prakticky konstantna).
    # shift=5 (S=32): W1 ~ +-15 float -> +-480 int16 (bez clipu), h*W2q
    # sa zmesti do int32 s rezervou.
    shift1 = 5
    shift2 = 5
    S = float(1 << shift1)
    W1q = np.clip(np.round(W1 * S), -32768, 32767).astype(np.int16)
    b1q = np.round(b1 * S).astype(np.int32)
    W2q = np.clip(np.round(W2 * S), -32768, 32767).astype(np.int16)
    b2q = int(np.round(float(b2) * S))

    with open(args.out, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<I", VERSION))
        f.write(struct.pack("<I", H))
        f.write(struct.pack("<I", shift1))
        f.write(struct.pack("<I", shift2))
        f.write(b1q.tobytes())
        f.write(W1q.tobytes())
        f.write(struct.pack("<i", b2q))
        f.write(W2q.tobytes())
    size = 20 + b1q.nbytes + W1q.nbytes + 4 + W2q.nbytes
    print(f"written: {args.out} ({size} bytes)")

    with open(args.report, "w", encoding="utf-8") as f:
        f.write(f"nnue_train2 H={H}\npositions={n}\nepochs={args.epochs}\n")
        f.write(f"target={args.target}\n")
        f.write(f"train_rows={n_train}\n")
        f.write(f"valid_rows={n_valid}\n")
        f.write(f"best_val_epoch={best_val_epoch}\n")
        if args.target == "cp":
            f.write(f"final_train_mse_cp={final_train_metric:.6f}\n")
            if n_valid > 0:
                f.write(f"final_val_mse_cp={final_val_metric:.6f}\n")
            split_name = "val" if n_valid > 0 else "train"
            f.write(f"gate_split={split_name}\n")
            f.write(f"gate_variance_cp={gate_var:.6f}\n")
            f.write(f"gate_mse_cp={selected_metric:.6f}\n")
            f.write(f"gate_ratio={gate_ratio:.6f}\n")
            f.write(f"gate_status={gate_status}\n")
        else:
            f.write(f"final_train_logloss={final_train_metric:.6f}\n")
            if n_valid > 0:
                f.write(f"final_val_logloss={final_val_metric:.6f}\n")
    print(f"report: {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
