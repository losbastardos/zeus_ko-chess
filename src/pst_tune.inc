; ============================================================
; pst_tune.inc - PST zakladne tabulky + scale konstanty pre tuning
;
; Scale konstanty: 64 = 1.0 (neutral). Runtime PST sa pocita v
; pst_init: runtime[sq] = base[sq] * SCALE / 64 (sar 6).
; Scale su `equ` -> tunovatelne cez tests/tuning/coordinate_descent.py.
; ============================================================

; --- scale konstanty (64 = 100 %) ---
PST_PAWN_MG_SCALE    equ 77
PST_PAWN_EG_SCALE    equ 51
PST_KNIGHT_MG_SCALE  equ 64
PST_KNIGHT_EG_SCALE  equ 64
PST_BISHOP_MG_SCALE  equ 64
PST_BISHOP_EG_SCALE  equ 64
PST_ROOK_MG_SCALE    equ 64
PST_ROOK_EG_SCALE    equ 64
PST_QUEEN_MG_SCALE   equ 64
PST_QUEEN_EG_SCALE   equ 64
PST_KING_MG_SCALE    equ 64
PST_KING_EG_SCALE    equ 64

; --- zakladne tabulky (verbatim z eval.asm, Michniewski hodnoty) ---
section .rodata

pst_base_empty:  times 64 db 0

pst_base_pawn_mg:
    db   0,  0,  0,  0,  0,  0,  0,  0
    db  50, 50, 50, 50, 50, 50, 50, 50
    db  10, 10, 20, 30, 30, 20, 10, 10
    db   5,  5, 10, 25, 25, 10,  5,  5
    db   0,  0,  0, 20, 20,  0,  0,  0
    db   5, -5,-10,  0,  0,-10, -5,  5
    db   5, 10, 10,-20,-20, 10, 10,  5
    db   0,  0,  0,  0,  0,  0,  0,  0

pst_base_pawn_eg:
    db   0,  0,  0,  0,  0,  0,  0,  0
    db  60, 60, 60, 60, 60, 60, 60, 60
    db  20, 20, 25, 30, 30, 25, 20, 20
    db  10, 10, 15, 25, 25, 15, 10, 10
    db   5,  5, 10, 20, 20, 10,  5,  5
    db   0,  0,  5,  5,  5,  5,  0,  0
    db   5,  5,  0,  0,  0,  0,  5,  5
    db   0,  0,  0,  0,  0,  0,  0,  0

pst_base_knight_mg:
    db -50,-40,-30,-30,-30,-30,-40,-50
    db -40,-20,  0,  0,  0,  0,-20,-40
    db -30,  0, 10, 15, 15, 10,  0,-30
    db -30,  5, 15, 20, 20, 15,  5,-30
    db -30,  0, 15, 20, 20, 15,  0,-30
    db -30,  5, 10, 15, 15, 10,  5,-30
    db -40,-20,  0,  5,  5,  0,-20,-40
    db -50,-40,-30,-30,-30,-30,-40,-50

pst_base_knight_eg:
    db -50,-40,-30,-30,-30,-30,-40,-50
    db -40,-20,  0,  0,  0,  0,-20,-40
    db -30,  0, 10, 15, 15, 10,  0,-30
    db -30,  5, 15, 20, 20, 15,  5,-30
    db -30,  0, 15, 20, 20, 15,  0,-30
    db -30,  5, 10, 15, 15, 10,  5,-30
    db -40,-20,  0,  5,  5,  0,-20,-40
    db -50,-40,-30,-30,-30,-30,-40,-50

pst_base_bishop_mg:
    db -20,-10,-10,-10,-10,-10,-10,-20
    db -10,  0,  0,  0,  0,  0,  0,-10
    db -10,  0,  5, 10, 10,  5,  0,-10
    db -10,  5,  5, 10, 10,  5,  5,-10
    db -10,  0, 10, 10, 10, 10,  0,-10
    db -10, 10, 10, 10, 10, 10, 10,-10
    db -10,  5,  0,  0,  0,  0,  5,-10
    db -20,-10,-10,-10,-10,-10,-10,-20

pst_base_bishop_eg:
    db -20,-10,-10,-10,-10,-10,-10,-20
    db -10,  0,  0,  0,  0,  0,  0,-10
    db -10,  0,  5, 10, 10,  5,  0,-10
    db -10,  5,  5, 10, 10,  5,  5,-10
    db -10,  0, 10, 10, 10, 10,  0,-10
    db -10, 10, 10, 10, 10, 10, 10,-10
    db -10,  5,  0,  0,  0,  0,  5,-10
    db -20,-10,-10,-10,-10,-10,-10,-20

pst_base_rook_mg:
    db   0,  0,  0,  0,  0,  0,  0,  0
    db   5, 10, 10, 10, 10, 10, 10,  5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db   0,  0,  0,  5,  5,  0,  0,  0

pst_base_rook_eg:
    db   0,  0,  0,  0,  0,  0,  0,  0
    db   5, 10, 10, 10, 10, 10, 10,  5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db  -5,  0,  0,  0,  0,  0,  0, -5
    db   0,  0,  0,  5,  5,  0,  0,  0

pst_base_queen_mg:
    db -20,-10,-10, -5, -5,-10,-10,-20
    db -10,  0,  0,  0,  0,  0,  0,-10
    db -10,  0,  5,  5,  5,  5,  0,-10
    db  -5,  0,  5,  5,  5,  5,  0, -5
    db   0,  0,  5,  5,  5,  5,  0, -5
    db -10,  5,  5,  5,  5,  5,  0,-10
    db -10,  0,  5,  0,  0,  0,  0,-10
    db -20,-10,-10, -5, -5,-10,-10,-20

pst_base_queen_eg:
    db -20,-10,-10, -5, -5,-10,-10,-20
    db -10,  0,  0,  0,  0,  0,  0,-10
    db -10,  0,  5,  5,  5,  5,  0,-10
    db  -5,  0,  5,  5,  5,  5,  0, -5
    db   0,  0,  5,  5,  5,  5,  0, -5
    db -10,  5,  5,  5,  5,  5,  0,-10
    db -10,  0,  5,  0,  0,  0,  0,-10
    db -20,-10,-10, -5, -5,-10,-10,-20

pst_base_king_mg:
    db -30,-40,-40,-50,-50,-40,-40,-30
    db -30,-40,-40,-50,-50,-40,-40,-30
    db -30,-40,-40,-50,-50,-40,-40,-30
    db -30,-40,-40,-50,-50,-40,-40,-30
    db -20,-30,-30,-40,-40,-30,-30,-20
    db -10,-20,-20,-20,-20,-20,-20,-10
    db  20, 20,  0,  0,  0,  0, 20, 20
    db  20, 30, 10,  0,  0, 10, 30, 20

pst_base_king_eg:
    db -20,-10,-10,-10,-10,-10,-10,-20
    db -10,  0,  5,  5,  5,  5,  0,-10
    db -10,  5, 15, 15, 15, 15,  5,-10
    db -10,  5, 15, 25, 25, 15,  5,-10
    db -10,  5, 15, 25, 25, 15,  5,-10
    db -10,  5, 15, 15, 15, 15,  5,-10
    db -10,  0,  5,  5,  5,  5,  0,-10
    db -20,-10,-10,-10,-10,-10,-10,-20

; pointer tabulky na zakladne (index = typ figury 0..6)
pst_base_ptrs_mg:
    dq pst_base_empty
    dq pst_base_pawn_mg
    dq pst_base_knight_mg
    dq pst_base_bishop_mg
    dq pst_base_rook_mg
    dq pst_base_queen_mg
    dq pst_base_king_mg

pst_base_ptrs_eg:
    dq pst_base_empty
    dq pst_base_pawn_eg
    dq pst_base_knight_eg
    dq pst_base_bishop_eg
    dq pst_base_rook_eg
    dq pst_base_queen_eg
    dq pst_base_king_eg

; scale tabulky pre pst_init (index = typ figury 1..6)
pst_scale_mg:
    dd 0
    dd PST_PAWN_MG_SCALE
    dd PST_KNIGHT_MG_SCALE
    dd PST_BISHOP_MG_SCALE
    dd PST_ROOK_MG_SCALE
    dd PST_QUEEN_MG_SCALE
    dd PST_KING_MG_SCALE

pst_scale_eg:
    dd 0
    dd PST_PAWN_EG_SCALE
    dd PST_KNIGHT_EG_SCALE
    dd PST_BISHOP_EG_SCALE
    dd PST_ROOK_EG_SCALE
    dd PST_QUEEN_EG_SCALE
    dd PST_KING_EG_SCALE
