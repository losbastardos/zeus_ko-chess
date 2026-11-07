; ============================================================
; eval_tune.inc - tunable eval weights for systematicky tuning
; ============================================================

; bonusy/penale (centipwny)
BISHOP_PAIR    equ 43
DOUBLED_PEN    equ 12
ISOLATED_PEN   equ 15
PASSED_BASE    equ 11
PASSED_STEP    equ 25
; realizovatelnost passera: skala = (kd*KINGDIST + blk*BLOCK) / (7*KINGDIST + 4*BLOCK)
; kd  = chebyshev vzdialenost nepriatelskeho krala od promotion sq passera
;       (square rule, 0..7) — cim dalej, tym realizovatelnejsi passer
; blk = podiel volnych policok pred pesiacom na jeho file (0..4 stvrtiny)
PASSED_KINGDIST_SCALE equ 32
PASSED_BLOCK_SCALE    equ 16
CONNECTED_PP_BASE equ 8
CONNECTED_PP_STEP equ 1
ROOK_OPEN      equ 25
ROOK_SEMI      equ 12
ROOK_SEVENTH   equ 25
ROOK_BEHIND_PP equ 18    ; veza za prekonajucim pesiakom
TEMPO_BONUS    equ 28

; mobility: bonus za dosiahnutelne policko (N/B/R/Q), MG/EG
; indexy: 0=prazdne,1=pesiak,2=jazdec,3=strelec,4=veza,5=dama,6=kral
mob_w_mg:   db 0, 0, 5, 5, 3, 1, 0
mob_w_eg:   db 0, 0, 5, 5, 5, 3, 0

; baseline mobility (pod tento pocet je figura stiesnena -> penal)
mob_base_mg: db 0, 0, 4, 7, 7, 14, 0
mob_base_eg: db 0, 0, 4, 7, 8, 14, 0

; king tropism: vaha za figuru blizko krala (distance <= 2)
; indexy 0..6: prazdne,pesiak,jazdec,strelec,veza,dama,kral
tropism_weights: db 0, 0, 2, 2, 3, 5, 0
TROPISM_SCALE  equ 4    ; multiplikator penalty

; king safety (iba MG)
SHIELD_PAWN    equ 12   ; pesiak v suprade pred kralom
KINGOPEN_PEN   equ 35   ; otvoreny file pri kralovi (ziadny pesiak)
KINGSEMI_PEN   equ 18   ; semi-otvoreny vlastnymi (vlastny chyba)
CASTLE_SHELTER_BONUS equ 8   ; pesiak na f/g/h pred rošádovaným kráľom
CASTLE_SHELTER_MISS  equ 12  ; chýbajúci pesiak v castled shelteri

; jazdec na outposte (MG/EG), centralne file 2..5 viac
OUTPOST_MG     equ 15
OUTPOST_EG     equ 8
OUTPOST_C_MG   equ 25
OUTPOST_C_EG   equ 10

; strelec na outposte (iba MG), konzervativne
B_OUTPOST_MG     equ 12
B_OUTPOST_EG     equ 0
B_OUTPOST_C_MG   equ 15
B_OUTPOST_C_EG   equ 0