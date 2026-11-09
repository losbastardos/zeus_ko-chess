; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; chess.inc - spolocne konstanty pre vsetky moduly
; ============================================================

; Systemove konstanty
SYS_READ    equ 0
SYS_WRITE   equ 1
SYS_PIPE    equ 22
SYS_CLONE   equ 56
SYS_FORK    equ 57
SYS_WAIT4   equ 61
SYS_POLL    equ 7
SYS_FUTEX   equ 202
SYS_CLOCK_GETTIME equ 228
SYS_EXIT    equ 60
SYS_OPEN    equ 2
SYS_CLOSE   equ 3
STDIN       equ 0
STDOUT      equ 1

CLOCK_REALTIME   equ 0
CLOCK_MONOTONIC  equ 1

; poll() event mask
POLLIN      equ 1

; open() flags
O_WRONLY    equ 1
O_CREAT     equ 64
O_APPEND    equ 1024

; Sachove konstanty
EMPTY       equ 0
PAWN        equ 1
KNIGHT      equ 2
BISHOP      equ 3
ROOK        equ 4
QUEEN       equ 5
KING        equ 6

WHITE       equ 0
BLACK       equ 8

PIECE_MASK  equ 7
COLOR_MASK  equ 8

; Flags tahu (16-bit)
; bits 0-5:   from square
; bits 6-11:  to square
; bits 12-15: flags
FLAG_NORMAL     equ 0
FLAG_PROMO_Q    equ 1
FLAG_PROMO_R    equ 2
FLAG_PROMO_B    equ 3
FLAG_PROMO_N    equ 4
FLAG_ENPASSANT  equ 5
FLAG_CASTLE     equ 6

; Prava rosady
CASTLE_WK   equ 1
CASTLE_WQ   equ 2
CASTLE_BK   equ 4
CASTLE_BQ   equ 8

; Search konstanty
INF         equ 1000000
MATE_SCORE  equ 50000

; Transposition table flags
TT_EXACT    equ 0
TT_LOWER    equ 1
TT_UPPER    equ 2

; Syzygy tablebase vysledky (stub, ziadne zaporne hodnoty)
TB_LOSS      equ 0
TB_DRAW      equ 1
TB_WIN       equ 2
TB_NOT_FOUND equ 255
DTZ_UNSUPPORTED equ 32768

; TB root DTZ ordering: maximalny pocet figurok, kedy sa pri root-e
; kazdy tah probe-n cez tb_probe_dtz a triedi sa vyhra > remiza > prehra
TB_ROOT_MAX_PIECES equ 5
; TB WDL probe v negamax: maximalny pocet figurok pre WDL cutoff
TB_WDL_MAX_PIECES  equ 4