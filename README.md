# Šachový engine (x86-64 Linux, NASM)

A high-performance chess engine written in x86-64 NASM assembly for Linux, featuring UCI protocol support, alpha-beta pruning with quiescence search, opening book integration, and both text and graphical (framebuffer/SDL) interfaces.

Textový šachový engine písaný v čistom NASM assembly pre x86-64 Linux.
Aktuálny stav: stabilná UCI vetva, text aj grafika (framebuffer/SDL), opening book,
Syzygy podpora a priebežné ladenie sily vyhľadávania/evaluácie.

## Screenshoty

Textový mód s bočným panelom (história ťahov, zajaté figúrky, knižné ťahy):

![Textový mód](screenshots/text_mode.png)

Grafický SDL mód:

![SDL mód](screenshots/sdl_mode.png)

## TODO (priebežne)

- Stabilizovať search heuristiky cez reprodukovateľný benchmark + SPRT workflow.
- Priebežne retunovať eval/NNUE bez regresií v gate testoch.
- Rozšíriť a udržiavať test sady (regresia, suite, TB smoke/verify).
- Udržiavať dokumentáciu a test postupy v súlade s aktuálnym stavom engina.

NNUE diagnostika (2026-10-06) je uzavretá: sieť v `EvalMode=2` je nekvalitná v king-danger režime (konvergentný signál zo sond 4/4, PGN mate kolapsov a scale auditu), pričom rýchle search-side zásahy (post-scale, all-off, null-off, futility-off) nepriniesli praktické zlepšenie; ďalší krok je iba retrain s cp labelmi a väčšou kapacitou.

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

---

Copyright (c) 2026 Marek Suchý <marek.suchy@gmail.com>. Všetky práva vyhradené.
