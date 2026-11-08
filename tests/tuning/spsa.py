#!/usr/bin/env python3
"""SPSA (Simultaneous Perturbation Stochastic Approximation) tuner pre
search konstanty engine — fishtest-style optimalizacia cez hry.

Cyklus k = 1..K (standardne SPSA exponenty gamma=0.101, alpha=0.602):
  Delta_k    z {+1,-1}^p nahodne (Jedna perturbacia pre vsetky parametre)
  c_k        = c / k^0.101
  theta+     = clamp(theta + c_k * Delta_k), theta- = clamp(theta - c_k * Delta_k)
  build(theta+), build(theta-)  -> 2 binarky, zapas N hier na stranu
  score+     = (vyhry+ + 0.5*remizy)/total z pohladu theta+ (score- = 1 - score+)
  g_k[i]     = (score+ - score-) / (2 * c_k * Delta_k[i])
  theta      = clamp(theta - a_k * g_k), a_k = a / k^0.602

Build: konstanty su `equ`/`%define` v src/search/00_header.asm (nie -D
preprocessor workflow), preto sa hodnota prepise priamo v subore a buildne
sa `make chess-static`. Pozor na header-deps bug v Makefile: obj/search.o
nesleduje src/search/*.asm, preto sa pred kazdym buildom maze obj/search.o.
Pri chybe/interrupte sa header obnovi z .bak zalohy (try/finally).

Match runner: cutechess-cli (default, --match-runner cutechess) alebo
zabudovany UCI self-play driver (--match-runner selfplay) pre stroje bez
cutechess-cli; pouziva python-chess rovnakym idiomom ako selfplay_dataset.py.
Auto-detekcia: bez cutechess-cli sa pouzije selfplay.

Na zaver: finalny build z theta_final, SPRT gate cez utils/sprt_match.py
proti baseline (master build), vystup do tests/reports/spsa_rN.md + .json.

Pouzitie:
  python3 tests/tuning/spsa.py --rounds 20 --games-per-side 30 \
      --params "LMR_INDEX_MIN:3:9:5,LMR_BASE_REDUCTION:0:3:1" \
      --tc 5+0.05 --seed 20261108 \
      --openings utils/LumbrasGigaBase_OTB_0001-1899.pgn

Smoke (rychly end-to-end check, bez SPRT gate):
  python3 tests/tuning/spsa.py --rounds 1 --games-per-side 2 --skip-sprt
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import re
import select
import shlex
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

GAMMA = 0.101  # ck = c / k^gamma (standard SPSA)
ALPHA = 0.602  # ak = a / k^alpha (standard SPSA)

HEADER_DEFAULT = "src/search/00_header.asm"
ENGINE_TARGET_DEFAULT = "chess-static"

# Cielove parametre: vsetky su pomenovane konstanty v src/search/00_header.asm
# editovatelne cez regex (ziadna inline logika). RFP margin (imul 120) a
# null-move R (sub rdi, 3) su inline konstanty v 40_negamax_a.asm — podla
# dohody sa skipuju; namiesto nich RAZOR_MARGIN a FUTILITY_MARGIN (equ).
DEFAULT_PARAMS = (
    "LMR_INDEX_MIN:3:9:5,"
    "LMR_DEPTH_MIN:2:5:3,"
    "LMR_BASE_REDUCTION:0:3:1,"
    "LMR_EXTRA_NON_IMPROVING:0:1:1,"
    "RAZOR_MARGIN:100:400:250,"
    "FUTILITY_MARGIN:50:300:150"
)

MOVE_OVERHEAD_MS = 100  # zhodne s defaultom v utils/sprt_match.py
ENGINE_OPTIONS = [
    "setoption name Threads value 1",
    "setoption name Hash value 16",
    "setoption name OwnBook value false",
    f"setoption name MoveOverhead value {MOVE_OVERHEAD_MS}",
]


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


def parse_tc(tc: str) -> tuple[int, int]:
    """'5+0.05' -> (5000, 50) ms; '10+0.1' -> (10000, 100)."""
    m = re.fullmatch(r"(\d+(?:\.\d+)?)\+(\d+(?:\.\d+)?)", tc.strip())
    if not m:
        raise ValueError(f"tc '{tc}': ocakavany format napr. 5+0.05")
    return (round(float(m.group(1)) * 1000), round(float(m.group(2)) * 1000))


def rewrite_header(path: str, values: dict[str, int]) -> None:
    """Prepise hodnoty konstant v 00_header.asm. Podporovane formy:
    '%define NAME <int>' (LMR_*; %ifndef-guardovane) a 'NAME equ <int>'.
    Fail-hard: kazdy parameter musi mat prave jednu nahradu, inak raise —
    chybne meno konstanty nesmie ticho prejst."""
    text = Path(path).read_text(encoding="utf-8")
    # split/join cez '\n' = round-trip safe (aj pre trailing newline)
    lines = text.split("\n")
    pats = {n: (re.compile(rf"^(%define\s+{re.escape(n)}\s+)(\d+)(.*)$"),
                re.compile(rf"^({re.escape(n)}\s+equ\s+)(\d+)(.*)$"))
            for n in values}
    applied: set[str] = set()
    out = []
    for line in lines:
        new_line = line
        for name, (dp, ep) in pats.items():
            if name in applied:
                continue
            m = dp.match(line) or ep.match(line)
            if m:
                new_line = f"{m.group(1)}{values[name]}{m.group(3)}"
                applied.add(name)
        out.append(new_line)
    if missing := [n for n in values if n not in applied]:
        raise RuntimeError(
            f"konstanty {missing} sa nenasli v {path} "
            "(ocakavany format: '%define NAME <int>' alebo 'NAME equ <int>')"
        )
    Path(path).write_text("\n".join(out), encoding="utf-8")


def build_engine(repo: str, target: str) -> None:
    # Header-deps bug: obj/search.o nesleduje src/search/*.asm includovane
    # cez src/search.asm — bez mazania obj by sa zmena konstant neprejavila.
    cmd = f"rm -f obj/search.o && make {shlex.quote(target)}"
    proc = subprocess.run(cmd, shell=True, cwd=repo, capture_output=True, text=True)
    if proc.returncode != 0 or not os.path.exists(os.path.join(repo, target)):
        tail = "\n".join((proc.stdout + proc.stderr).splitlines()[-25:])
        raise RuntimeError(f"build zlyhal: {cmd}\n{tail}")


class UciEngine:
    """Min UCI wrapper — rovnaky idiom ako selfplay_dataset.py."""

    def __init__(self, path: str, cwd: str):
        self.proc = subprocess.Popen(
            [os.path.abspath(path), "--uci"], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
            cwd=cwd,
        )
        self.send("uci")
        self.wait_for("uciok")
        self.send("isready")
        self.wait_for("readyok")

    def send(self, line: str) -> None:
        assert self.proc.stdin
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def readline(self, timeout_s: float | None = None) -> str:
        assert self.proc.stdout
        if timeout_s is not None:
            r, _, _ = select.select([self.proc.stdout], [], [], timeout_s)
            if not r:
                raise TimeoutError("timeout cakania na vystup engine")
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("engine zatvoril stdout")
        return line.strip()

    def wait_for(self, token: str, max_lines: int = 100000) -> None:
        for _ in range(max_lines):
            if self.readline() == token:
                return
        raise RuntimeError(f"timeout cakania na {token}")

    def bestmove(self, position_cmd: str, go_cmd: str, timeout_s: float) -> str:
        self.send(position_cmd)
        self.send(go_cmd)
        while True:
            line = self.readline(timeout_s)
            if line.startswith("bestmove"):
                return line.split()[1]

    def eval_cp(self, fen: str, depth: int):
        """score cp z pohladu strany na tahu, alebo None pri mate."""
        self.send(f"position fen {fen}")
        self.send(f"go depth {depth}")
        cp = None
        while True:
            line = self.readline(60)
            if line.startswith("info depth ") and " score cp " in line:
                try:
                    cp = int(line.split(" score cp ")[1].split()[0])
                except Exception:
                    cp = None
            if line.startswith("info depth ") and " score mate " in line:
                cp = 10000 if int(line.split(" score mate ")[1].split()[0]) > 0 else -10000
            if line.startswith("bestmove"):
                break
        return cp

    def close(self) -> None:
        try:
            self.send("quit")
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def play_game_selfplay(plus_path: str, minus_path: str, plus_is_white: bool,
                       base_ms: int, inc_ms: int, max_plies: int, repo: str):
    """Jedna hra plus-build vs minus-build. Vrati vysledok z pohladu plus:
    1.0 vyhra / 0.5 remiza / 0.0 prehra; forfeit nelegalneho tahu/casu = 0.0.
    Hodiny: rovnaky alloc model ako engine (uci_alloc_time: t/30 + inc,
    min 50ms, minus MoveOverhead, floor 10ms); driver strhava merany cas.
    Adjudikacia ako v selfplay_dataset.py: |eval|>=600 dva po sebe (depth 6,
    kazdych 8 ply od ply 24), 75-move/fivefold -> remiza, max_plies -> remiza.
    """
    import chess

    white: UciEngine | None = None
    black: UciEngine | None = None
    try:
        white = UciEngine(plus_path if plus_is_white else minus_path, repo)
        black = UciEngine(minus_path if plus_is_white else plus_path, repo)
        for eng in (white, black):
            for opt in ENGINE_OPTIONS:
                eng.send(opt)

        board = chess.Board()
        moves_uci: list[str] = []
        clocks = {chess.WHITE: float(base_ms), chess.BLACK: float(base_ms)}
        adjud_hits = 0

        for ply in range(max_plies):
            if board.is_game_over(claim_draw=False):
                break
            stm = board.turn
            eng = white if stm == chess.WHITE else black
            pos_cmd = "position startpos"
            if moves_uci:
                pos_cmd += " moves " + " ".join(moves_uci)
            # budget: zrkadli uci_alloc_time (informativne pre timeout guard)
            budget = max(int(clocks[stm]) // 30 + inc_ms - MOVE_OVERHEAD_MS, 10)
            wt = int(clocks[chess.WHITE])
            bt = int(clocks[chess.BLACK])
            go_cmd = f"go wtime {wt} btime {bt} winc {inc_ms} binc {inc_ms}"
            t0 = time.monotonic()
            try:
                mv = eng.bestmove(pos_cmd, go_cmd, timeout_s=max(60.0, budget / 1000 * 5 + 15))
            except (TimeoutError, RuntimeError):
                return 1.0 if not plus_is_white else 0.0  # forfeit strany na tahu
            elapsed_ms = (time.monotonic() - t0) * 1000
            clocks[stm] -= elapsed_ms
            if clocks[stm] < -1000:
                # casove forfeit: vyhra supera
                plus_won_clock = (stm == chess.BLACK) == plus_is_white
                return 1.0 if plus_won_clock else 0.0
            if mv in ("0000", "(none)"):
                break
            try:
                move = chess.Move.from_uci(mv)
                if move not in board.legal_moves:
                    raise ValueError(mv)
            except Exception:
                # nelegalny tah = forfeit strany na tahu
                plus_won_illegal = (stm == chess.BLACK) == plus_is_white
                return 1.0 if plus_won_illegal else 0.0
            board.push(move)
            moves_uci.append(mv)

            if board.is_checkmate():
                # side to move is mated
                white_won = stm == chess.BLACK
                return 1.0 if (white_won == plus_is_white) else 0.0
            if board.is_stalemate() or board.is_insufficient_material():
                return 0.5
            if board.is_seventyfive_moves() or board.is_fivefold_repetition():
                return 0.5

            if ply % 8 == 7 and ply >= 24:
                ev = white.eval_cp(board.fen(), 6)
                if ev is not None and abs(ev) >= 600:
                    adjud_hits += 1
                    if adjud_hits >= 2:
                        stm_is_white = board.turn == chess.WHITE
                        white_cp = ev if stm_is_white else -ev
                        white_won = white_cp > 0
                        return 1.0 if (white_won == plus_is_white) else 0.0
                else:
                    adjud_hits = 0
        return 0.5
    finally:
        for eng in (white, black):
            if eng is not None:
                eng.close()


def score_from_pgn(pgn_text: str, plus_name: str = "PLUS") -> tuple[float, int]:
    """Z cutechess -pgnout spocita score plus-buildu. Vrati (score_plus, games)."""
    wins = draws = games = 0
    for chunk in re.split(r'\n(?=\[Event ")', pgn_text):
        m_w = re.search(r'\[White "([^"]+)"\]', chunk)
        m_b = re.search(r'\[Black "([^"]+)"\]', chunk)
        m_r = re.search(r'\[Result "([^"]+)"\]', chunk)
        if not (m_w and m_b and m_r):
            continue
        res = m_r.group(1)
        if res not in ("1-0", "0-1", "1/2-1/2"):
            continue
        games += 1
        plus_white = m_w.group(1) == plus_name
        if res == "1/2-1/2":
            draws += 1
        elif (res == "1-0") == plus_white:
            wins += 1
    if games == 0:
        raise RuntimeError("z cutechess pgn sa nepodarilo spocitat ziadnu hru")
    return (wins + 0.5 * draws) / games, games


def run_match_cutechess(plus: str, minus: str, games_per_side: int, tc: str,
                        concurrency: int, seed: int, openings: str,
                        pgnout: str, repo: str, log) -> float:
    engines = []
    for name, path in (("PLUS", plus), ("MINUS", minus)):
        engines += [
            "-engine", f"name={name}", f"cmd={os.path.abspath(path)}",
            "proto=uci", "option.Threads=1", "option.Hash=16",
            "option.OwnBook=false", f"option.MoveOverhead={MOVE_OVERHEAD_MS}",
        ]
    cmd = ["cutechess-cli"] + engines
    cmd += ["-each", "proto=uci", f"tc={tc}"]
    cmd += ["-concurrency", str(concurrency)]
    cmd += ["-games", str(2 * games_per_side), "-repeat", "-srand", str(seed)]
    if openings:
        fmt = "epd" if openings.endswith(".epd") else "pgn"
        cmd += ["-openings", f"file={openings}", f"format={fmt}",
                "order=random", "plies=8", "start=1"]
    # adjudikacia zhodna s utils/sprt_match.py
    cmd += shlex.split("-resign movecount=4 score=600 "
                       "-draw movenumber=20 movecount=4 score=20")
    cmd += ["-pgnout", pgnout]
    log("cutechess: " + " ".join(shlex.quote(x) for x in cmd))
    proc = subprocess.run(cmd, cwd=repo, capture_output=True, text=True)
    (Path(pgnout).parent / (Path(pgnout).stem + ".cutechess.log")).write_text(
        proc.stdout + proc.stderr, encoding="utf-8")
    if proc.returncode != 0:
        raise RuntimeError(f"cutechess-cli zlyhal (rc={proc.returncode}); "
                           f"log: {pgnout}.cutechess.log")
    score_plus, games = score_from_pgn(Path(pgnout).read_text(encoding="utf-8"))
    log(f"cutechess: games={games} score+={score_plus:.3f}")
    return score_plus


def run_match_selfplay(plus: str, minus: str, games_per_side: int, tc: str,
                       concurrency: int, seed: int, repo: str, log) -> float:
    try:
        import chess  # noqa: F401
    except ImportError as exc:
        raise RuntimeError("selfplay runner vyzaduje python-chess") from exc
    base_ms, inc_ms = parse_tc(tc)
    total = 2 * games_per_side

    def one(i: int) -> float:
        # striedanie farieb: kazdy build hra N hier ako biely
        return play_game_selfplay(plus, minus, plus_is_white=(i % 2 == 0),
                                  base_ms=base_ms, inc_ms=inc_ms,
                                  max_plies=240, repo=repo)

    results: list[float] = []
    with ThreadPoolExecutor(max_workers=max(1, concurrency)) as pool:
        for r in pool.map(one, range(total)):
            results.append(r)
            log(f"selfplay: game {len(results)}/{total} score+_cum="
                f"{sum(results) / len(results):.3f}")
    if not results:
        raise RuntimeError("selfplay: ziadne hry")
    score_plus = sum(results) / len(results)
    log(f"selfplay: games={len(results)} score+={score_plus:.3f} (seed={seed})")
    return score_plus


def run_match(runner: str, plus: str, minus: str, games_per_side: int, tc: str,
              concurrency: int, seed: int, openings: str, tag: str,
              workdir: str, repo: str, log) -> float:
    if runner == "cutechess":
        return run_match_cutechess(plus, minus, games_per_side, tc, concurrency,
                                   seed, openings,
                                   os.path.join(workdir, f"{tag}.pgn"), repo, log)
    return run_match_selfplay(plus, minus, games_per_side, tc, concurrency,
                              seed, repo, log)


def log_line(msg: str, logfile: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(logfile, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def clamp(v: float, lo: int, hi: int) -> float:
    return min(float(hi), max(float(lo), v))


def next_run_index(report_dir: str) -> int:
    os.makedirs(report_dir, exist_ok=True)
    best = 0
    for name in os.listdir(report_dir):
        m = re.fullmatch(r"spsa_r(\d+)\.json", name)
        if m:
            best = max(best, int(m.group(1)))
    return best + 1


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="SPSA tuner pre search konstanty (fishtest-style)")
    p.add_argument("--rounds", type=int, default=20, help="SPSA cyklov K (default 20)")
    p.add_argument("--games-per-side", type=int, default=30,
                   help="hier na stranu v zapase theta+ vs theta- (default 30)")
    p.add_argument("--params", default=DEFAULT_PARAMS,
                   help="format meno:min:max:default, oddelene ciarkami")
    p.add_argument("--tc", default="5+0.05", help="time control, napr. 5+0.05")
    p.add_argument("--seed", type=int, default=20261108)
    p.add_argument("--concurrency", type=int,
                   default=max(1, (os.cpu_count() or 2) // 2),
                   help="parallelne hry (default jadra/2)")
    p.add_argument("--a", type=float, default=8.0,
                   help="SPSA a (krok ak = a/k^0.602; ~velkost posunu theta)")
    p.add_argument("--c", type=float, default=1.0,
                   help="SPSA c (perturbacia ck = c/k^0.101; min 1 pre int)")
    p.add_argument("--match-runner", choices=["auto", "cutechess", "selfplay"],
                   default="auto",
                   help="auto: cutechess-cli ak je v PATH, inak selfplay")
    p.add_argument("--openings", default="",
                   help="PGN/EPD subor zahier pre cutechess runner (default: startpos)")
    p.add_argument("--header", default=HEADER_DEFAULT,
                   help="zdrojovy subor s konstantami (default src/search/00_header.asm)")
    p.add_argument("--engine-target", default=ENGINE_TARGET_DEFAULT,
                   help="make target binarky (default chess-static)")
    p.add_argument("--report-dir", default="tests/reports")
    p.add_argument("--sprt-games", type=int, default=200)
    p.add_argument("--sprt", default="elo0=0 elo1=8 alpha=0.05 beta=0.05")
    p.add_argument("--skip-sprt", action="store_true",
                   help="preskocit finalny SPRT gate (smoke)")
    p.add_argument("--dry-run", action="store_true",
                   help="vypise rozlozene CLI + detekovany runner a skonci")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    repo = os.getcwd()
    params = parse_params(args.params)
    parse_tc(args.tc)  # validacia skorej, pred akymkolvek buildom

    runner = args.match_runner
    if runner == "auto":
        runner = "cutechess" if shutil.which("cutechess-cli") else "selfplay"

    if args.dry_run:
        print(f"runner={runner}")
        print(f"params={[(x.name, x.lo, x.hi, x.default) for x in params]}")
        print(f"rounds={args.rounds} games_per_side={args.games_per_side} "
              f"tc={args.tc} seed={args.seed} concurrency={args.concurrency}")
        return 0

    if not os.path.exists(os.path.join(repo, args.header)):
        print(f"error: header subor nenajdeny: {args.header}", file=sys.stderr)
        return 2
    if runner == "cutechess" and not shutil.which("cutechess-cli"):
        print("error: --match-runner cutechess, ale cutechess-cli nie je v PATH",
              file=sys.stderr)
        return 2
    if args.openings and not os.path.exists(args.openings):
        print(f"error: --openings nenajdeny: {args.openings}", file=sys.stderr)
        return 2

    run_idx = next_run_index(args.report_dir)
    workdir = os.path.join(args.report_dir, f"spsa_r{run_idx}", "work")
    os.makedirs(workdir, exist_ok=True)
    logfile = os.path.join(args.report_dir, f"spsa_r{run_idx}.log")

    log = lambda msg: log_line(msg, logfile)  # noqa: E731
    log(f"SPSA run r{run_idx}: params={args.params}")
    log(f"tc={args.tc} rounds={args.rounds} games_per_side={args.games_per_side} "
        f"concurrency={args.concurrency} seed={args.seed} a={args.a} c={args.c} "
        f"runner={runner}")

    header = os.path.join(repo, args.header)
    backup = os.path.join(workdir, "00_header.asm.bak")
    shutil.copyfile(header, backup)

    rng = random.Random(args.seed)
    theta = {x.name: float(x.default) for x in params}
    history: list[dict] = []
    base_engine = os.path.join(workdir, "base_engine")
    sprt: dict = {"skipped": bool(args.skip_sprt)}
    success = False

    try:
        log("baseline (master) build ...")
        build_engine(repo, args.engine_target)
        shutil.copy2(os.path.join(repo, args.engine_target), base_engine)

        for k in range(1, args.rounds + 1):
            ck = args.c / k ** GAMMA
            ak = args.a / k ** ALPHA
            delta = {x.name: rng.choice((-1, 1)) for x in params}
            plus_vals = {x.name: int(round(clamp(
                theta[x.name] + ck * delta[x.name], x.lo, x.hi))) for x in params}
            minus_vals = {x.name: int(round(clamp(
                theta[x.name] - ck * delta[x.name], x.lo, x.hi))) for x in params}

            log(f"cyklus k={k}: ck={ck:.4f} ak={ak:.4f} delta={delta}")
            log(f"  theta+={plus_vals}")
            log(f"  theta-={minus_vals}")

            rewrite_header(header, plus_vals)
            build_engine(repo, args.engine_target)
            plus_bin = os.path.join(workdir, f"plus_k{k}")
            shutil.copy2(os.path.join(repo, args.engine_target), plus_bin)

            rewrite_header(header, minus_vals)
            build_engine(repo, args.engine_target)
            minus_bin = os.path.join(workdir, f"minus_k{k}")
            shutil.copy2(os.path.join(repo, args.engine_target), minus_bin)

            t0 = time.time()
            score_plus = run_match(
                runner, plus_bin, minus_bin, args.games_per_side, args.tc,
                args.concurrency, args.seed + k, args.openings,
                f"cycle_k{k}", workdir, repo, log)
            score_minus = 1.0 - score_plus
            dt = time.time() - t0

            grad = {x.name: (score_plus - score_minus) / (2 * ck * delta[x.name])
                    for x in params}
            theta = {x.name: clamp(theta[x.name] - ak * grad[x.name], x.lo, x.hi)
                     for x in params}

            grad_s = ", ".join(f"{n}={g:+.4f}" for n, g in grad.items())
            theta_s = ", ".join(f"{n}={v:.2f}" for n, v in theta.items())
            log(f"  k={k}: score+={score_plus:.3f} score-={score_minus:.3f} "
                f"({dt:.0f}s)")
            log(f"  k={k}: g=[{grad_s}]")
            log(f"  k={k}: theta=[{theta_s}]")
            history.append({
                "k": k, "ck": ck, "ak": ak, "delta": delta,
                "theta_plus": plus_vals, "theta_minus": minus_vals,
                "score_plus": score_plus, "score_minus": score_minus,
                "grad": grad,
                "theta_after": {n: round(v, 4) for n, v in theta.items()},
                "match_seconds": round(dt, 1),
            })

        final_vals = {x.name: int(round(clamp(theta[x.name], x.lo, x.hi)))
                      for x in params}
        log(f"final theta={final_vals}")

        rewrite_header(header, final_vals)
        build_engine(repo, args.engine_target)
        candidate = os.path.join(workdir, "candidate")
        shutil.copy2(os.path.join(repo, args.engine_target), candidate)
        log(f"finalny build OK: {candidate}")

        if not args.skip_sprt:
            sprt_pgn = os.path.join(workdir, "sprt_final.pgn")
            cmd = [sys.executable, os.path.join("utils", "sprt_match.py"),
                   "--new", candidate, "--base", base_engine,
                   "--games", str(args.sprt_games),
                   "--concurrency", str(args.concurrency),
                   "--tc", args.tc, "--sprt", args.sprt,
                   "--pgnout", sprt_pgn]
            log("SPRT gate: " + " ".join(shlex.quote(x) for x in cmd))
            proc = subprocess.run(cmd, cwd=repo, capture_output=True, text=True)
            out = proc.stdout + proc.stderr
            verdict = "UNKNOWN"
            m = re.search(r"(H[01]\s+(accepted|rejected)|SPRT.*(passed|failed|accept|reject))", out)
            if m:
                verdict = m.group(0)
            sprt = {"skipped": False, "cmd": cmd, "rc": proc.returncode,
                    "verdict": verdict, "tail": out[-2000:]}
            log(f"SPRT gate: rc={proc.returncode} verdict={verdict}")
        else:
            log("SPRT gate preskoceny (--skip-sprt)")

        success = True
    finally:
        # restore header vzdy (chyba, KeyboardInterrupt, aj normalny koniec)
        if os.path.exists(backup):
            shutil.copyfile(backup, header)
            log(f"header obnoveny z {backup}")
        if success:
            # obnov aj worktree binarku na master (source uz je restored);
            # zaroven overi, ze build s povodnymi konstantami prechadza
            try:
                build_engine(repo, args.engine_target)
                log("master rebuild po restore OK")
            except Exception as exc:
                log(f"WARN: master rebuild po restore zlyhal: {exc}")

    report_md = os.path.join(args.report_dir, f"spsa_r{run_idx}.md")
    report_json = os.path.join(args.report_dir, f"spsa_r{run_idx}.json")
    changed = {x.name: final_vals[x.name] - x.default for x in params}
    recommended = [x for x in params if changed[x.name] != 0]

    md = []
    md.append(f"# SPSA run r{run_idx} — {datetime.now().isoformat(timespec='seconds')}")
    md.append("")
    md.append(f"- seed: `{args.seed}`, runner: `{runner}`, tc: `{args.tc}`")
    md.append(f"- rounds: {args.rounds}, games/side/cycle: {args.games_per_side}, "
              f"concurrency: {args.concurrency}")
    md.append(f"- SPSA: a={args.a}, c={args.c}, gamma={GAMMA}, alpha={ALPHA}")
    md.append("")
    md.append("## Parametre")
    md.append("")
    md.append("| parameter | min | max | default | final | delta |")
    md.append("|---|---|---|---|---|---|")
    for x in params:
        md.append(f"| {x.name} | {x.lo} | {x.hi} | {x.default} | "
                  f"{final_vals[x.name]} | {changed[x.name]:+d} |")
    md.append("")
    if recommended:
        md.append("## Odporucane zmeny (do `src/search/00_header.asm`)")
        md.append("")
        md.append("```sh")
        for x in recommended:
            if x.name.startswith("LMR_"):
                pat = f"%define +{x.name} +)[0-9]+"
            else:
                pat = f"{x.name} +equ +)[0-9]+"
            md.append(f"sed -i -E 's/^({pat}/\\1{final_vals[x.name]}/' "
                      "src/search/00_header.asm")
        md.append("rm -f obj/search.o && make chess-static")
        md.append("```")
        md.append("")
        md.append("Pozor: `LMR_EXTRA_NON_IMPROVING` ma vyznam 0/1 "
                  "(`%if ... = 1` v 41_negamax_b.asm) — hodnoty >1 sa chovaju ako 0.")
    else:
        md.append("## Odporucane zmeny")
        md.append("")
        md.append("Ziadne — SPSA skoncilo na default hodnotach.")
    md.append("")
    md.append("## Cykly")
    md.append("")
    md.append("| k | ck | ak | score+ | theta po kroku |")
    md.append("|---|---|---|---|---|")
    for h in history:
        theta_s = " ".join(f"{n}={v:g}" for n, v in h["theta_after"].items())
        md.append(f"| {h['k']} | {h['ck']:.3f} | {h['ak']:.3f} | "
                  f"{h['score_plus']:.3f} | {theta_s} |")
    md.append("")
    md.append("## SPRT gate (final vs master)")
    md.append("")
    if sprt.get("skipped"):
        md.append("Preskoceny (`--skip-sprt`).")
    else:
        md.append(f"- rc: {sprt.get('rc')}")
        md.append(f"- verdict: `{sprt.get('verdict')}`")
        md.append("```")
        md.append(sprt.get("tail", "").strip())
        md.append("```")
    md.append("")
    md.append(f"Detail log: `tests/reports/spsa_r{run_idx}.log`, "
              f"binarky: `tests/reports/spsa_r{run_idx}/work/`")
    md.append("")
    Path(report_md).write_text("\n".join(md), encoding="utf-8")

    payload = {
        "run": run_idx,
        "date": datetime.now().isoformat(timespec="seconds"),
        "seed": args.seed,
        "runner": runner,
        "tc": args.tc,
        "rounds": args.rounds,
        "games_per_side": args.games_per_side,
        "concurrency": args.concurrency,
        "a": args.a, "c": args.c, "gamma": GAMMA, "alpha": ALPHA,
        "params": {x.name: {"min": x.lo, "max": x.hi, "default": x.default,
                            "final": final_vals[x.name], "delta": changed[x.name]}
                   for x in params},
        "cycles": history,
        "sprt": sprt,
        "report_md": report_md,
    }
    Path(report_json).write_text(json.dumps(payload, indent=2), encoding="utf-8")
    log(f"report: {report_md}")
    log(f"report: {report_json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
