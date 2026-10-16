#!/usr/bin/env python3
"""HalfKP v3 trainer (Faza 1 sanity, trainer-side only).

Architektura: 2x256 vetvy (STM + OPP), sparse HalfKP features.
Gate:
- ratio < gate_pass: PASS
- gate_pass <= ratio <= gate_warn: WARN (stop, analyza)
- ratio > gate_warn: FAIL (pipeline bug / stop)
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

import numpy as np

MAGIC_U32 = 0x45554E4E
VERSION = 3
ARCH = 1
FLAGS = 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="HalfKP v3 trainer (2x256)")
    p.add_argument("--npz", required=True, help="prepared NPZ from halfkp_prepare_cp.py")
    p.add_argument("--out", default="scratch/net3_sanity.nnue")
    p.add_argument("--report", default="tests/reports/nnue_train3_halfkp_50k.txt")
    p.add_argument("--curve", default="tests/reports/nnue_train3_halfkp_50k_curve.tsv")
    p.add_argument("--hidden", type=int, default=256)
    p.add_argument("--epochs", type=int, default=80)
    p.add_argument("--batch", type=int, default=4096)
    p.add_argument("--lr", type=float, default=1e-2)
    p.add_argument("--l2", type=float, default=1e-5)
    p.add_argument("--seed", type=int, default=20261014)
    p.add_argument("--valid-ratio", type=float, default=0.2)
    p.add_argument("--valid-max", type=int, default=10000)
    p.add_argument("--patience", type=int, default=15)
    p.add_argument("--fail-fast-ratio", type=float, default=1.0)
    p.add_argument("--gate-pass", type=float, default=0.30)
    p.add_argument("--gate-warn", type=float, default=0.50)
    p.add_argument("--scale", type=float, default=233.0)
    p.add_argument("--shift-acc", type=int, default=5)
    p.add_argument("--shift-out", type=int, default=5)
    p.add_argument("--diag-out", default="", help="optional diagnostics output file")
    p.add_argument("--diag-split", choices=["val", "train", "all"], default="val",
                   help="which split to use for saturation diagnostics")
    p.add_argument("--probe-every", type=int, default=5,
                   help="print W1/grad probes every N epochs (0 disables periodic probes)")
    p.add_argument("--probe-out", default="",
                   help="optional TSV file for periodic probe metrics")
    p.add_argument("--checkpoint-every", type=int, default=0,
                   help="export checkpoint+diag every N epochs (0 disables)")
    p.add_argument("--checkpoint-prefix", default="",
                   help="path prefix for periodic checkpoint artifacts")
    return p.parse_args()


def forward_sparse(W: np.ndarray, b: np.ndarray, idx: np.ndarray, cnt: np.ndarray) -> np.ndarray:
    m = idx.shape[0]
    z = np.repeat(b[None, :], m, axis=0)
    for i in range(m):
        n = int(cnt[i])
        if n > 0:
            z[i] += W[idx[i, :n]].sum(axis=0)
    return z


def grad_w1_sparse(W_shape, idx: np.ndarray, cnt: np.ndarray, dz: np.ndarray, l2: float, W_ref: np.ndarray) -> np.ndarray:
    g = np.zeros(W_shape, dtype=np.float32)
    m = idx.shape[0]
    for i in range(m):
        n = int(cnt[i])
        if n > 0:
            np.add.at(g, idx[i, :n], dz[i])
    g /= float(max(1, m))
    if l2 > 0:
        g += l2 * W_ref
    return g


def adam_update(param, grad, m, v, t, lr, b1=0.9, b2=0.999, eps=1e-8):
    m[:] = b1 * m + (1.0 - b1) * grad
    v[:] = b2 * v + (1.0 - b2) * (grad * grad)
    mhat = m / (1.0 - b1**t)
    vhat = v / (1.0 - b2**t)
    param[:] = param - lr * (mhat / (np.sqrt(vhat) + eps))


def eval_mse(indices, idx_stm, idx_opp, cnt_stm, cnt_opp, y, W1s, W1o, b1s, b1o, W2s, W2o, b2):
    if indices.size == 0:
        return float("nan")
    total = 0.0
    bs = 4096
    for s in range(0, indices.size, bs):
        bid = indices[s : s + bs]
        zs = forward_sparse(W1s, b1s, idx_stm[bid], cnt_stm[bid])
        zo = forward_sparse(W1o, b1o, idx_opp[bid], cnt_opp[bid])
        hs = np.clip(zs, 0.0, 255.0)
        ho = np.clip(zo, 0.0, 255.0)
        ev = hs @ W2s + ho @ W2o + b2
        d = ev - y[bid]
        total += float((d * d).sum())
    return total / float(indices.size)


def saturation_diag(indices, idx_stm, idx_opp, cnt_stm, cnt_opp, W1s, W1o, b1s, b1o,
                    clip_hi: float = 255.0):
    if indices.size == 0:
        return {
            "samples": 0,
            "sat_low_pct": float("nan"),
            "sat_high_pct": float("nan"),
            "sat_any_pct": float("nan"),
        }

    total = 0
    low = 0
    high = 0
    bs = 2048
    for s in range(0, indices.size, bs):
        bid = indices[s : s + bs]
        zs = forward_sparse(W1s, b1s, idx_stm[bid], cnt_stm[bid])
        zo = forward_sparse(W1o, b1o, idx_opp[bid], cnt_opp[bid])
        both = np.concatenate((zs, zo), axis=1)
        low += int((both <= 0.0).sum())
        high += int((both >= clip_hi).sum())
        total += int(both.size)

    sat_low = 100.0 * low / total
    sat_high = 100.0 * high / total
    sat_any = 100.0 * (low + high) / total
    return {
        "samples": int(indices.size),
        "sat_low_pct": sat_low,
        "sat_high_pct": sat_high,
        "sat_any_pct": sat_any,
    }


def export_v3(path: str, F: int, H: int, shift_acc: int, shift_out: int,
              W1s: np.ndarray, W1o: np.ndarray, b1s: np.ndarray, b1o: np.ndarray,
              W2s: np.ndarray, W2o: np.ndarray, b2: float):
    # Quant podľa zmrazeneho formatu decisions: W1 i8, b1/W2 i16, b2 i32.
    # W1 + b1 musia mat spolocnu skalu (Sacc), ktoru loader nasledne
    # odskaluje cez shift_acc. Skalu volime dynamicky z realnej distribucie W1.
    Sacc = float(1 << shift_acc)
    Sout = float(1 << shift_out)

    W1s_q = np.clip(np.round(W1s * Sacc), -128, 127).astype(np.int8)
    W1o_q = np.clip(np.round(W1o * Sacc), -128, 127).astype(np.int8)
    b1s_q = np.clip(np.round(b1s * Sacc), -32768, 32767).astype(np.int16)
    b1o_q = np.clip(np.round(b1o * Sacc), -32768, 32767).astype(np.int16)
    W2s_q = np.clip(np.round(W2s * Sout), -32768, 32767).astype(np.int16)
    W2o_q = np.clip(np.round(W2o * Sout), -32768, 32767).astype(np.int16)
    b2_q = int(np.round(float(b2) * Sout))

    header = struct.pack(
        "<8I",
        MAGIC_U32,
        VERSION,
        ARCH,
        FLAGS,
        F,
        H,
        shift_acc,
        shift_out,
    )

    with open(path, "wb") as f:
        f.write(header)
        f.write(b1s_q.tobytes(order="C"))
        f.write(b1o_q.tobytes(order="C"))
        f.write(W1s_q.tobytes(order="C"))
        f.write(W1o_q.tobytes(order="C"))
        f.write(struct.pack("<i", b2_q))
        f.write(W2s_q.tobytes(order="C"))
        f.write(W2o_q.tobytes(order="C"))


def write_diag_file(path: str, split: str, diag: dict, best_epoch: int,
                    shift_acc: int, shift_out: int,
                    w1_absmax_q: int, w1_nonzero_pct: float,
                    grad_w1_l2: float, grad_w2_l2: float) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write("halfkp_v3_diag\n")
        f.write(f"split={split}\n")
        f.write(f"samples={diag['samples']}\n")
        f.write(f"best_epoch={best_epoch}\n")
        f.write(f"shift_acc={shift_acc}\n")
        f.write(f"shift_out={shift_out}\n")
        f.write(f"w1_absmax_q={w1_absmax_q}\n")
        f.write(f"w1_nonzero_pct={w1_nonzero_pct:.6f}\n")
        f.write(f"sat_low_pct={diag['sat_low_pct']:.6f}\n")
        f.write(f"sat_high_pct={diag['sat_high_pct']:.6f}\n")
        f.write(f"sat_any_pct={diag['sat_any_pct']:.6f}\n")
        f.write(f"w1_absmax={diag['w1_absmax']:.6f}\n")
        f.write(f"w2_absmax={diag['w2_absmax']:.6f}\n")
        f.write(f"grad_w1_l2={grad_w1_l2:.6f}\n")
        f.write(f"grad_w2_l2={grad_w2_l2:.6f}\n")


def pick_shift_acc(W1s: np.ndarray, W1o: np.ndarray, b1s: np.ndarray, b1o: np.ndarray,
                   min_absmax_q: int = 100, target_absmax_q: int = 120,
                   max_shift: int = 15) -> int:
    w1_absmax = float(max(np.abs(W1s).max(), np.abs(W1o).max()))
    if w1_absmax <= 0.0:
        raise RuntimeError("W1 absmax is zero; cannot quantize v3 network")

    # Primarny ciel: vyuzit i8 rozsah bez pretecenia.
    shift = int(math.floor(math.log2(target_absmax_q / w1_absmax)))
    shift = max(0, min(shift, max_shift))

    # Ak absmax po zaokruhleni ostane prilis nizky, zvysime shift.
    while shift < max_shift:
        sacc = float(1 << shift)
        w1s_q = np.clip(np.round(W1s * sacc), -128, 127).astype(np.int8)
        w1o_q = np.clip(np.round(W1o * sacc), -128, 127).astype(np.int8)
        absmax_q = int(max(np.abs(w1s_q).max(), np.abs(w1o_q).max()))
        if absmax_q >= min_absmax_q:
            break
        shift += 1

    # Bezpecnost pre b1 i16.
    while shift > 0:
        sacc = float(1 << shift)
        b1_abs = float(max(np.abs(b1s).max(), np.abs(b1o).max()))
        if b1_abs * sacc <= 32767.0:
            break
        shift -= 1

    return shift



def main() -> int:
    args = parse_args()
    rng = np.random.default_rng(args.seed)

    blob = np.load(args.npz)
    idx_stm = blob["idx_stm"]
    idx_opp = blob["idx_opp"]
    cnt_stm = blob["cnt_stm"]
    cnt_opp = blob["cnt_opp"]
    y = blob["y"].astype(np.float32)
    F = int(blob["F"])
    n = int(blob["n"])
    H = int(args.hidden)

    idx_all = rng.permutation(n)
    valid_n = int(n * args.valid_ratio) if args.valid_ratio > 0 else 0
    if valid_n > 0 and args.valid_max > 0:
        valid_n = min(valid_n, args.valid_max)
    valid_n = max(1, min(valid_n, n - 1)) if n >= 2 and valid_n > 0 else 0
    valid_idx = idx_all[:valid_n]
    train_idx = idx_all[valid_n:]

    n_train = int(train_idx.shape[0])
    n_valid = int(valid_idx.shape[0])

    if args.diag_split == "all":
        diag_idx = idx_all
    elif args.diag_split == "train":
        diag_idx = train_idx
    else:
        diag_idx = valid_idx

    print(f"dataset: n={n} F={F} H={H}")
    print(f"split: train={n_train} valid={n_valid}")

    W1s = rng.normal(0.0, 0.05, size=(F, H)).astype(np.float32)
    W1o = rng.normal(0.0, 0.05, size=(F, H)).astype(np.float32)
    b1s = np.full(H, 0.5, dtype=np.float32)
    b1o = np.full(H, 0.5, dtype=np.float32)
    W2s = rng.normal(0.0, 0.02, size=H).astype(np.float32)
    W2o = rng.normal(0.0, 0.02, size=H).astype(np.float32)
    b2 = np.float32(0.0)

    mW1s = np.zeros_like(W1s); vW1s = np.zeros_like(W1s)
    mW1o = np.zeros_like(W1o); vW1o = np.zeros_like(W1o)
    mb1s = np.zeros_like(b1s); vb1s = np.zeros_like(b1s)
    mb1o = np.zeros_like(b1o); vb1o = np.zeros_like(b1o)
    mW2s = np.zeros_like(W2s); vW2s = np.zeros_like(W2s)
    mW2o = np.zeros_like(W2o); vW2o = np.zeros_like(W2o)
    mb2 = np.float32(0.0); vb2 = np.float32(0.0)

    best_val = float("inf")
    best_epoch = 0
    best_snapshot = None
    stale = 0
    step = 0

    curve_rows = ["epoch\ttrain_mse\tval_mse\tval_ratio"]
    probe_rows = ["epoch\tw1_absmax\tgrad_w1_l2\tgrad_w2_l2\tratio"]

    for epoch in range(args.epochs):
        order = train_idx[rng.permutation(n_train)]
        train_sum = 0.0
        seen = 0
        grad_w1_l2_sum = 0.0
        grad_w2_l2_sum = 0.0
        grad_batches = 0

        for s in range(0, n_train, args.batch):
            bid = order[s : s + args.batch]
            m = bid.shape[0]
            step += 1

            zs = forward_sparse(W1s, b1s, idx_stm[bid], cnt_stm[bid])
            zo = forward_sparse(W1o, b1o, idx_opp[bid], cnt_opp[bid])
            hs = np.clip(zs, 0.0, 255.0)
            ho = np.clip(zo, 0.0, 255.0)

            ev = hs @ W2s + ho @ W2o + b2
            diff = ev - y[bid]
            train_sum += float((diff * diff).sum())
            seen += int(m)

            d = diff / (args.scale * args.scale)
            dW2s = (hs.T @ d) / m + args.l2 * W2s
            dW2o = (ho.T @ d) / m + args.l2 * W2o
            db2 = float(d.mean())

            dhs = np.outer(d, W2s)
            dho = np.outer(d, W2o)
            dzs = dhs * (zs > 0)
            dzo = dho * (zo > 0)

            db1s = dzs.mean(axis=0)
            db1o = dzo.mean(axis=0)
            dW1s = grad_w1_sparse(W1s.shape, idx_stm[bid], cnt_stm[bid], dzs, args.l2, W1s)
            dW1o = grad_w1_sparse(W1o.shape, idx_opp[bid], cnt_opp[bid], dzo, args.l2, W1o)

            grad_w1_l2_sum += math.sqrt(float((dW1s * dW1s).sum() + (dW1o * dW1o).sum()))
            grad_w2_l2_sum += math.sqrt(float((dW2s * dW2s).sum() + (dW2o * dW2o).sum()))
            grad_batches += 1

            adam_update(W1s, dW1s, mW1s, vW1s, step, args.lr)
            adam_update(W1o, dW1o, mW1o, vW1o, step, args.lr)
            adam_update(b1s, db1s, mb1s, vb1s, step, args.lr)
            adam_update(b1o, db1o, mb1o, vb1o, step, args.lr)
            adam_update(W2s, dW2s, mW2s, vW2s, step, args.lr)
            adam_update(W2o, dW2o, mW2o, vW2o, step, args.lr)
            mb2 = 0.9 * mb2 + 0.1 * db2
            vb2 = 0.999 * vb2 + 0.001 * (db2 * db2)
            b2 -= args.lr * (mb2 / (1.0 - 0.9**step)) / (math.sqrt(vb2 / (1.0 - 0.999**step)) + 1e-8)

        train_mse = train_sum / float(max(1, seen))
        val_mse = eval_mse(valid_idx, idx_stm, idx_opp, cnt_stm, cnt_opp, y, W1s, W1o, b1s, b1o, W2s, W2o, b2) if n_valid > 0 else float("nan")
        var_val = float(np.var(y[valid_idx], ddof=0)) if n_valid > 0 else float(np.var(y[train_idx], ddof=0))
        ratio = (val_mse / var_val) if n_valid > 0 and var_val > 0 else ((train_mse / var_val) if var_val > 0 else float("inf"))
        w1_absmax_epoch = float(max(np.abs(W1s).max(), np.abs(W1o).max()))
        grad_w1_l2 = grad_w1_l2_sum / float(max(1, grad_batches))
        grad_w2_l2 = grad_w2_l2_sum / float(max(1, grad_batches))

        curve_rows.append(f"{epoch+1}\t{train_mse:.6f}\t{val_mse:.6f}\t{ratio:.6f}")
        probe_rows.append(f"{epoch+1}\t{w1_absmax_epoch:.6f}\t{grad_w1_l2:.6f}\t{grad_w2_l2:.6f}\t{ratio:.6f}")
        if epoch == 0 or (epoch + 1) % 5 == 0:
            print(f"epoch {epoch+1}: train_mse={train_mse:.5f} val_mse={val_mse:.5f} ratio={ratio:.6f}", flush=True)
        if args.probe_every > 0 and ((epoch + 1) % args.probe_every == 0 or epoch == 0):
            print(
                f"probe {epoch+1}: w1_absmax={w1_absmax_epoch:.6f} "
                f"grad_w1_l2={grad_w1_l2:.6f} grad_w2_l2={grad_w2_l2:.6f}",
                flush=True,
            )

        if args.checkpoint_every > 0 and args.checkpoint_prefix and (epoch + 1) % args.checkpoint_every == 0:
            ckpt_prefix = f"{args.checkpoint_prefix}_epoch{epoch+1:03d}"
            ckpt_nnue = f"{ckpt_prefix}.nnue"
            ckpt_diag = f"{ckpt_prefix}.diag.txt"
            ckpt_shift_acc = pick_shift_acc(W1s, W1o, b1s, b1o)
            ckpt_sacc = float(1 << ckpt_shift_acc)
            ckpt_w1s_q = np.clip(np.round(W1s * ckpt_sacc), -128, 127).astype(np.int8)
            ckpt_w1o_q = np.clip(np.round(W1o * ckpt_sacc), -128, 127).astype(np.int8)
            ckpt_w1_absmax_q = int(max(np.abs(ckpt_w1s_q).max(), np.abs(ckpt_w1o_q).max()))
            ckpt_w1_nonzero_pct = 100.0 * float(np.count_nonzero(ckpt_w1s_q) + np.count_nonzero(ckpt_w1o_q)) / float(ckpt_w1s_q.size + ckpt_w1o_q.size)
            ckpt_diag_stats = saturation_diag(diag_idx, idx_stm, idx_opp, cnt_stm, cnt_opp, W1s, W1o, b1s, b1o)
            ckpt_diag_stats["w1_absmax"] = w1_absmax_epoch
            ckpt_diag_stats["w2_absmax"] = float(max(np.abs(W2s).max(), np.abs(W2o).max()))
            export_v3(ckpt_nnue, F, H, ckpt_shift_acc, args.shift_out, W1s, W1o, b1s, b1o, W2s, W2o, b2)
            write_diag_file(
                ckpt_diag,
                args.diag_split,
                ckpt_diag_stats,
                epoch + 1,
                ckpt_shift_acc,
                args.shift_out,
                ckpt_w1_absmax_q,
                ckpt_w1_nonzero_pct,
                grad_w1_l2,
                grad_w2_l2,
            )
            print(
                f"checkpoint {epoch+1}: {ckpt_nnue} diag={ckpt_diag} "
                f"w1_absmax={w1_absmax_epoch:.6f} w1_absmax_q={ckpt_w1_absmax_q} "
                f"w1_nonzero%={ckpt_w1_nonzero_pct:.3f}",
                flush=True,
            )

        if n_valid > 0 and val_mse < best_val:
            best_val = val_mse
            best_epoch = epoch + 1
            best_snapshot = (
                W1s.copy(), W1o.copy(), b1s.copy(), b1o.copy(), W2s.copy(), W2o.copy(), np.float32(b2)
            )
            stale = 0
        else:
            stale += 1

        if (epoch + 1) == 1 and args.fail_fast_ratio > 0 and ratio > args.fail_fast_ratio:
            print(f"fail_fast: epoch=1 ratio={ratio:.6f} threshold={args.fail_fast_ratio:.6f}", flush=True)
            break

        if args.patience > 0 and stale >= args.patience:
            print(f"early_stop: epoch={epoch+1} best_epoch={best_epoch} best_val={best_val:.6f}", flush=True)
            break

    if best_snapshot is not None:
        W1s, W1o, b1s, b1o, W2s, W2o, b2 = best_snapshot

    diag = saturation_diag(diag_idx, idx_stm, idx_opp, cnt_stm, cnt_opp, W1s, W1o, b1s, b1o)
    diag["w1_absmax"] = float(max(np.abs(W1s).max(), np.abs(W1o).max()))
    diag["w2_absmax"] = float(max(np.abs(W2s).max(), np.abs(W2o).max()))
    diag["best_epoch"] = int(best_epoch)

    train_mse = eval_mse(train_idx, idx_stm, idx_opp, cnt_stm, cnt_opp, y, W1s, W1o, b1s, b1o, W2s, W2o, b2)
    val_mse = eval_mse(valid_idx, idx_stm, idx_opp, cnt_stm, cnt_opp, y, W1s, W1o, b1s, b1o, W2s, W2o, b2) if n_valid > 0 else float("nan")
    gate_var = float(np.var(y[valid_idx], ddof=0)) if n_valid > 0 else float(np.var(y[train_idx], ddof=0))
    selected = val_mse if n_valid > 0 else train_mse
    ratio = (selected / gate_var) if gate_var > 0 else float("inf")

    if ratio < args.gate_pass:
        gate_status = "PASS"
    elif ratio <= args.gate_warn:
        gate_status = "WARN"
    else:
        gate_status = "FAIL"

    # Shift pre W1/b1 berieme z realnej distribucie vah, nie natvrdo.
    shift_acc = pick_shift_acc(W1s, W1o, b1s, b1o)

    sacc = float(1 << shift_acc)
    w1s_q_chk = np.clip(np.round(W1s * sacc), -128, 127).astype(np.int8)
    w1o_q_chk = np.clip(np.round(W1o * sacc), -128, 127).astype(np.int8)
    w1_absmax_q = int(max(np.abs(w1s_q_chk).max(), np.abs(w1o_q_chk).max()))
    w1_nonzero_pct = 100.0 * float(np.count_nonzero(w1s_q_chk) + np.count_nonzero(w1o_q_chk)) / float(w1s_q_chk.size + w1o_q_chk.size)

    # Fail-fast guard: nech export nikdy ticho nevygeneruje mrtvu vrstvu W1.
    if w1_nonzero_pct <= 50.0:
        raise RuntimeError(f"Export fail: W1 nonzero% too low ({w1_nonzero_pct:.3f} <= 50.0)")
    if w1_absmax_q < 100:
        raise RuntimeError(f"Export fail: W1 absmax_q too low ({w1_absmax_q} < 100)")

    export_v3(args.out, F, H, shift_acc, args.shift_out, W1s, W1o, b1s, b1o, W2s, W2o, b2)

    Path(args.curve).write_text("\n".join(curve_rows) + "\n", encoding="utf-8")
    if args.probe_out:
        Path(args.probe_out).write_text("\n".join(probe_rows) + "\n", encoding="utf-8")
    with open(args.report, "w", encoding="utf-8") as f:
        f.write("halfkp_v3_2x256_sanity\n")
        f.write(f"npz={args.npz}\n")
        f.write(f"out={args.out}\n")
        f.write(f"train_rows={n_train}\n")
        f.write(f"valid_rows={n_valid}\n")
        f.write(f"best_val_epoch={best_epoch}\n")
        f.write(f"train_mse={train_mse:.6f}\n")
        f.write(f"val_mse={val_mse:.6f}\n")
        f.write(f"gate_variance={gate_var:.6f}\n")
        f.write(f"gate_ratio={ratio:.6f}\n")
        f.write(f"gate_status={gate_status}\n")
        f.write(f"shift_acc={shift_acc}\n")
        f.write(f"shift_out={args.shift_out}\n")
        f.write(f"w1_absmax_q={w1_absmax_q}\n")
        f.write(f"w1_nonzero_pct={w1_nonzero_pct:.6f}\n")
        f.write(f"curve={args.curve}\n")
        f.write(f"diag_split={args.diag_split}\n")
        f.write(f"diag_samples={diag['samples']}\n")
        f.write(f"sat_low_pct={diag['sat_low_pct']:.6f}\n")
        f.write(f"sat_high_pct={diag['sat_high_pct']:.6f}\n")
        f.write(f"sat_any_pct={diag['sat_any_pct']:.6f}\n")
        f.write(f"w1_absmax={diag['w1_absmax']:.6f}\n")
        f.write(f"w2_absmax={diag['w2_absmax']:.6f}\n")
        f.write(f"probe_every={args.probe_every}\n")
        if args.probe_out:
            f.write(f"probe={args.probe_out}\n")

    if args.diag_out:
        final_grad_w1_l2 = grad_w1_l2 if 'grad_w1_l2' in locals() else float('nan')
        final_grad_w2_l2 = grad_w2_l2 if 'grad_w2_l2' in locals() else float('nan')
        write_diag_file(
            args.diag_out,
            args.diag_split,
            diag,
            diag['best_epoch'],
            shift_acc,
            args.shift_out,
            w1_absmax_q,
            w1_nonzero_pct,
            final_grad_w1_l2,
            final_grad_w2_l2,
        )

    print(f"written: {args.out}")
    print(f"report: {args.report}")
    print(f"curve: {args.curve}")
    print(f"export: shift_acc={shift_acc} shift_out={args.shift_out} w1_absmax_q={w1_absmax_q} w1_nonzero%={w1_nonzero_pct:.3f}")
    print(
        f"diag[{args.diag_split}]: sat_low={diag['sat_low_pct']:.3f}% "
        f"sat_high={diag['sat_high_pct']:.3f}% sat_any={diag['sat_any_pct']:.3f}% "
        f"|w1|max={diag['w1_absmax']:.3f} |w2|max={diag['w2_absmax']:.3f}"
    )
    if args.diag_out:
        print(f"diag file: {args.diag_out}")
    print(f"gate: ratio={ratio:.6f} status={gate_status}")

    return 0 if gate_status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
