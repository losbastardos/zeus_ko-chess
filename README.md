# Šachový engine (x86-64 Linux, NASM)

A high-performance chess engine written in x86-64 NASM assembly for Linux, featuring UCI protocol support, alpha-beta pruning with quiescence search, opening book integration, and both text and graphical (framebuffer/SDL) interfaces.

Textový šachový engine písaný v čistom NASM assembly pre x86-64 Linux.
Stav: UCI (cutechess-ready), text aj grafika (procedurálne figúrky, framebuffer/SDL2),
vlastný opening book, ECO knižnica, Syzygy WDL/DTZ probe (3/4-piece, časť 5-piece),
Lazy SMP, PGN export.

## Čo vie (výber)

- **Search:** negamax + PVS, quiescence, iteratívne prehlbovanie, aspiration,
  TT, null-move (zugzwang guard), LMR, ProbCut, singular extension, razoring,
  futility/RFP/LMP, SEE, history heuristiky (killer/countermove/capture/
  continuation), mate distance pruning, check extension, nodes-based TM.
- **Eval:** tapered MG/EG (PST + štruktúra + mobility + king safety + outposty),
  prepínateľné NNUE — `EvalMode 0/1/2` (klasika / lineárny / 1 skrytá vrstva,
  formáty v1-v3, HalfKP loader).
- **TB:** vlastný Syzygy loader (mmap, pairs decode), WDL/DTZ sondu, root DTZ
  ordering, oracle-validované triedy.
- **Protokoly:** UCI (Hash/OwnBook/Ponder/Threads/MoveOverhead/EvalMode/
  SyzygyPath/SyzygyProbeDepth), diagnostika `tbtest`, `suite`, `bench`, `perft`.

Nie všetko je vhodné na verejné popisovanie; zvyšok je v kóde a v
`docs/superpowers/`.

## Odkiaľ sú metódy (teoretické zdroje)

- Search heuristiky (LMR, null-move, ProbCut, singular ext., futility...):
  prehľad a literatúru zhromažďuje [Chess Programming Wiki](https://www.chessprogramming.org/Main_Page),
  konkrétne heuristiky podľa mena; referenčná implementácia
  [Stockfish](https://github.com/official-stockfish/Stockfish) (search.cpp).
- NNUE: formát a tréningová metóda podľa
  [Graf / «NNUE»](https://github.com/nodchip/Stockfish) (nodchip branch),
  HalfKP feature definície tamtiež; engine-side konvencie kompatibilné s
  python-chess inference (oracle `utils/syzygy_oracle.py` + training tooling
  v `tests/tuning/`).
- Texel / coordinate-descent ladenie váh: metóda Texela
  (CPW: [Texel's Tuning Method](https://www.chessprogramming.org/Texel%27s_Tuning_Method)).
- Syzygy TB: formát tabuliek a probe sémantika podľa pôvodného arbitra
  (`probe.c` z Fathom / Ronald de Man), validácia cez
  [python-chess](https://python-chess.readthedocs.io/) syzygy modul.
- SPRT testovanie zmien: [Sequential Probability Ratio Test](https://en.wikipedia.org/wiki/Sequential_probability_ratio_test)
  ako používa [Fishtest](https://github.com/glinscott/fishtest); Elo/LOS odhady
  z binárnych výsledkov štandardným spôsobom (elocalc konvencie).
- Test infra: [cutechess-cli](https://github.com/cutechess/cutechess) gauntlety,
  opening knižnica LumbrasGigaBase; perft/legality referencie python-chess.

## Screenshoty

Textový mód s bočným panelom (história ťahov, zajaté figúrky, knižné ťahy):

![Textový mód](screenshots/text_mode.png)

Grafický SDL mód:

![SDL mód](screenshots/sdl_mode.png)

## Smer (priebežne)

- Sila: NNUE iterácie, ladenie search konštánt, validované výhradne cez
  SPRT + gauntlety (žiadne merge bez nich).
- Rýchlosť: profilovanie search/eval hot spots.
- TB: rozširovanie 5-piece coverage, korektnosť decode cez oracle.
- Infra: prehlbovanie test matice, benchmark tracking.

## Kompilácia

```bash
./build.sh
```

alebo manuálne (odporúčam `make`, ktoré to spraví za teba):

```bash
make
```

Binárka `./chess` obsahuje všetky backendy naraz (text, framebuffer aj SDL),
SDL (`libSDL2`) sa linkuje dynamicky.

Na NixOS, ak nemáš `nasm` v PATH, `./build.sh` ho automaticky získa cez `nix-shell`.

## Spustenie

```bash
./chess
```

Zadávaj ťahy v algebraickej notácii, napríklad `e2e4`, `g1f3`.
Príkaz `flip` prepne orientáciu výpisu šachovnice.
Príkaz `new` spustí novú hru, `go` nechá engine zahrať jeden ťah za aktuálnu stranu.
Príkaz `gfx` prepne do grafického režimu (framebuffer `/dev/fb0` alebo SDL okno,
podľa `chess.ini` a dostupnosti), `text` vráti späť do terminálu.
Príkaz `uci` prepne do UCI režimu pre pripojenie k GUI.
Ukonči program príkazom `exit` alebo `quit`.

V `chess.ini` môžeš nastaviť aj `syzygy=` na cestu k TB tabuľkám (prázdne = vypnuté).

V textovom móde sa vpravo od šachovnice zobrazuje panel s históriou ťahov,
zajatými figúrkami a knižnými ťahmi pre aktuálnu pozíciu (ak sú v `book.book`).

## Použitie v cutechess-cli

Engine podporuje UCI, takže po builde ho vieš priamo použiť v cutechess-cli.

Užitočné diagnostické UCI helper príkazy:
- `eval` vypíše static eval pre aktuálnu pozíciu.
- `evaldiff` porovná two-path evaluáciu (list-path vs scan-path) bez searchu a vypíše prvý odlišný komponent.
- `evalstate` vypíše stav NNUE akumulátora (valid/match/inc/ref).
- `halfkpdump` vypíše HalfKP indexy v diff-friendly formáte; perspektívy sú pevne `p0 = strana na ťahu (STM)`, `p1 = súper (OPP)`.

- Ak máš `./chess`, funguje ako UCI engine, ale je dynamicky linkovaný (SDL knižnice musia byť dostupné).
- Ak máš `./chess-static`, je to odporúčaný variant pre benchmarky, self-play a CI (plne statický textový build).

Príklad rýchleho 2-engine zápasu (10+0.1, striedanie farieb):

```bash
cutechess-cli \
	-engine name=zeusA cmd=./chess-static \
	-engine name=zeusB cmd=./chess-static \
	-each proto=uci tc=10+0.1 option.Threads=1 option.Hash=64 option.OwnBook=false \
	-games 20 -repeat
```

Príklad s opening PGN:

```bash
cutechess-cli \
	-engine name=zeusA cmd=./chess-static \
	-engine name=zeusB cmd=./chess-static \
	-each proto=uci tc=10+0.1 option.Threads=1 option.Hash=64 option.OwnBook=false \
	-openings file=utils/LumbrasGigaBase_OTB_1990-1999.pgn format=pgn order=random \
	-games 200 -repeat -pgnout scratch/cutechess_run.pgn
```

Poznámka:
- Pre porovnávanie dvoch revízií je najistejší postup pripraviť dve binárky s rôznym názvom (napr. `scratch/chess-baseline` a `scratch/chess-candidate`) a tie priamo použiť v `cmd=`.

## Reprezentácia

- `board[64]` – index `0 = a1`, `63 = h8`
- Figúra na políčku: bity `0-2` typ, bit `3` farba
- Ťah: 16-bitové číslo `from(6) | to(6) | flags(4)`

Poznámka: interné testovacie a debug workflow sú presunuté do lokálnej internej dokumentácie mimo verejný repozitár.

## Licencia

Tento projekt je licencovaný pod MIT licenciou. Detaily sú v súbore [LICENSE](LICENSE).

Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>.
