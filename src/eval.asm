; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; eval.asm - tapered evaluacia (MG/EG interpolacia)
; ============================================================

%include "chess.inc"
%include "eval_tune.inc"
%include "pst_tune.inc"

%ifndef ENABLE_PL_INFRA
%define ENABLE_PL_INFRA 1
%endif

DEFAULT REL

section .data

global evaluate, eval_dbg_mg, eval_dbg_eg, eval_dbg_phase, eval_dbg_wk, eval_dbg_bk, eval_dbg_trop_w, eval_dbg_trop_b
global eval_dbg_lp_lists_base, eval_dbg_lp_counts_base, eval_dbg_lp_counts, eval_dbg_lp_first
global material_mg, material_eg, phase_weights
eval_dbg_mg: dd 0
eval_dbg_eg: dd 0
eval_dbg_phase: dd 0
eval_dbg_wk: dd 0
eval_dbg_bk: dd 0
eval_dbg_trop_w: dd 0
eval_dbg_trop_b: dd 0
eval_dbg_lp_lists_base: dq 0
eval_dbg_lp_counts_base: dq 0
eval_dbg_lp_counts: times 12 db 0
eval_dbg_lp_first: times 12 db 255

; ============================================================
; Passed pesiak masky — vystup pawn structure sekcie evaluate
; (pouzivaju connected passed + rook behind PP bonusy)
; ============================================================
section .bss
passed_w:        resq 1          ; maska bielych passed pesiacov
passed_b:        resq 1
section .data

; MG material = povodne hodnoty; EG: pesiaci viac, leziece menej
material_mg:
    dd 0            ; EMPTY
    dd 100          ; PAWN
    dd 320          ; KNIGHT
    dd 330          ; BISHOP
    dd 500          ; ROOK
    dd 900          ; QUEEN
    dd 20000        ; KING

material_eg:
    dd 0            ; EMPTY
    dd 120          ; PAWN
    dd 300          ; KNIGHT
    dd 310          ; BISHOP
    dd 520          ; ROOK
    dd 940          ; QUEEN
    dd 20000        ; KING

; vaha fazy podla typu figury (non-pawn material; max 24 = 4N+4B+4R+2Q... 2*(1+1+2+4))
phase_weights:
    db 0            ; EMPTY
    db 0            ; PAWN
    db 1            ; KNIGHT
    db 1            ; BISHOP
    db 2            ; ROOK
    db 4            ; QUEEN
    db 0            ; KING

; runtime PST tabulky (naplni pst_init z pst_tune.inc zakladov * scale,
; alebo nnue_load z net.nnue; layout [own 7x64][enemy 7x64] per faza)
section .bss
global pst_runtime_mg, pst_runtime_eg
pst_runtime_mg: resb 64*14
pst_runtime_eg: resb 64*14

section .data
global pst_ptrs_mg, pst_ptrs_eg
; index: 0..6 = own (EMPTY..KING), 7..13 = enemy (EMPTY..KING)
pst_ptrs_mg:
    dq pst_runtime_mg + 0*64
    dq pst_runtime_mg + 1*64
    dq pst_runtime_mg + 2*64
    dq pst_runtime_mg + 3*64
    dq pst_runtime_mg + 4*64
    dq pst_runtime_mg + 5*64
    dq pst_runtime_mg + 6*64
    dq pst_runtime_mg + 7*64
    dq pst_runtime_mg + 8*64
    dq pst_runtime_mg + 9*64
    dq pst_runtime_mg + 10*64
    dq pst_runtime_mg + 11*64
    dq pst_runtime_mg + 12*64
    dq pst_runtime_mg + 13*64

pst_ptrs_eg:
    dq pst_runtime_eg + 0*64
    dq pst_runtime_eg + 1*64
    dq pst_runtime_eg + 2*64
    dq pst_runtime_eg + 3*64
    dq pst_runtime_eg + 4*64
    dq pst_runtime_eg + 5*64
    dq pst_runtime_eg + 6*64
    dq pst_runtime_eg + 7*64
    dq pst_runtime_eg + 8*64
    dq pst_runtime_eg + 9*64
    dq pst_runtime_eg + 10*64
    dq pst_runtime_eg + 11*64
    dq pst_runtime_eg + 12*64
    dq pst_runtime_eg + 13*64

; masky stlpcov (bit f, f+8, ...) pre pawn structure / open files
file_masks:
    dq 0x0101010101010101
    dq 0x0202020202020202
    dq 0x0404040404040404
    dq 0x0808080808080808
    dq 0x1010101010101010
    dq 0x2020202020202020
    dq 0x4040404040404040
    dq 0x8080808080808080

; rank r: bity policok s VYSSIM rankom (r+1..7) - blockery pesiaca
hi_rank_masks:
    dq 0xFFFFFFFFFFFFFF00
    dq 0xFFFFFFFFFFFF0000
    dq 0xFFFFFFFFFF000000
    dq 0xFFFFFFFF00000000
    dq 0xFFFFFF0000000000
    dq 0xFFFF000000000000
    dq 0xFF00000000000000
    dq 0

; rank r: bity policok s NIZSIM rankom (0..r-1)
lo_rank_masks:
    dq 0
    dq 0xFF
    dq 0xFFFF
    dq 0xFFFFFF
    dq 0xFFFFFFFF
    dq 0xFFFFFFFFFF
    dq 0xFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFF



section .text

extern board
extern side, eval_mode, fullmove
extern nnue2_eval, nnue2_ready
extern prof_evals
extern moved_piece, captured_piece, promo_pieces
extern bb_pieces, bb_side, bb_occ
extern bb_knight_attacks
extern bb_attacks_bishop, bb_attacks_rook, bb_attacks_queen
extern pl_lists, pl_counts, pl_dirty

; ============================================================
; MOB_BLOCK slot_off, typ, atk, outpost - mobilita jedneho typu figury
;   slot_off: offset (B) od [rbp-120] base = &bb_pieces[color*6 + 1]
;   typ:      KNIGHT/BISHOP/ROOK/QUEEN (vlozi sa do r14d)
;   atk:      0 = bb_knight_attacks tabulka, 1 = bb_attacks_bishop,
;             2 = bb_attacks_rook, 3 = bb_attacks_queen
;   outpost:  1 = vyhodnotit outpost bonus (konstanty KNIGHT vs BISHOP)
; Register set pasu (nastaveny pred blokom v .mobility):
;   [rbp-112] = vlastna maska (vylucenie vlastnych policok),
;   [rbp-120] = base slotov, r13d = farba (0/8), r15d = MG acc,
;   [rbp-48] = EG acc, rbx = board base;
;   lokalne: r12 = sq, [rbp-96] = iteracna maska
; Pocty su ekvivalentne povodnemu mailbox MOB_WALK countingu:
; prazdne + super policka, vlastna figura blokuje (aj seba).
; ============================================================
%macro MOB_BLOCK 4
    mov r14d, %2
    mov rax, [rbp - 120]
    mov rdx, [rax + %1]
    mov [rbp - 96], rdx         ; iteracna maska (prezije scoring clobbery)
%%loop:
    mov rdi, [rbp - 96]
    test rdi, rdi
    jz %%done
    bsf r12, rdi
    btr qword [rbp - 96], r12
%if %4
    call eval_knight_outpost
    test eax, eax
    jz %%op_done
%if %3 == 0
    mov eax, OUTPOST_MG
    mov edx, OUTPOST_EG
%else
    mov eax, B_OUTPOST_MG
    mov edx, B_OUTPOST_EG
%endif
    mov esi, r12d
    and esi, 7
    cmp esi, 2
    jb %%op_score
    cmp esi, 5
    jbe %%op_c
    jmp %%op_score
%%op_c:
%if %3 == 0
    mov eax, OUTPOST_C_MG
    mov edx, OUTPOST_C_EG
%else
    mov eax, B_OUTPOST_C_MG
    mov edx, B_OUTPOST_C_EG
%endif
%%op_score:
    test r13d, r13d
    jz %%op_w
    sub r15d, eax
    sub dword [rbp - 48], edx
    jmp %%op_done
%%op_w:
    add r15d, eax
    add dword [rbp - 48], edx
%%op_done:
%endif
    ; utoky figury; ciele = attacks & ~vlastna
%if %3 == 0
    lea rax, [bb_knight_attacks]
    mov rcx, [rax + r12*8]
%else
    mov eax, r12d
    mov rdx, [bb_occ]
  %if %3 == 1
    call bb_attacks_bishop
  %elif %3 == 2
    call bb_attacks_rook
  %else
    call bb_attacks_queen
  %endif
    mov rcx, rax
%endif
    mov rdx, [rbp - 112]
    not rdx
    and rcx, rdx
    popcnt rcx, rcx
    ; MG mobility: w * (count - baseline)
    mov eax, ecx
    lea rsi, [mob_base_mg]
    movzx edi, byte [rsi + r14]
    sub eax, edi
    lea rsi, [mob_w_mg]
    movzx edi, byte [rsi + r14]
    imul eax, edi
    ; EG mobility: w * (count - baseline)
    mov edx, ecx
    lea rsi, [mob_base_eg]
    movzx edi, byte [rsi + r14]
    sub edx, edi
    lea rsi, [mob_w_eg]
    movzx edi, byte [rsi + r14]
    imul edx, edi
    test r13d, r13d
    jz %%mob_w
    sub r15d, eax
    sub dword [rbp - 48], edx
    jmp %%loop
%%mob_w:
    add r15d, eax
    add dword [rbp - 48], edx
    jmp %%loop
%%done:
%endmacro

; ============================================================
; eval_knight_outpost - jazdec na outposte?
; Vstup:  r12 = sq, r13d = farba jazdca (0/8)
; Vystup: eax = 1 (outpost: rank 4-6, brany vlastnym pesiacom,
;                  bez utoku nepriatelskeho pesiaca), inak 0
; Clobber: rax, rcx, rdx, rsi, rdi, r8
; ============================================================
eval_knight_outpost:
    mov eax, r12d
    shr eax, 3              ; rank
    test r13d, r13d
    jnz .rank_b
    cmp eax, 3              ; biely rank 4-6 (idx 3-5)
    jb .no
    cmp eax, 5
    ja .no
    jmp .rank_ok
.rank_b:
    cmp eax, 2              ; cierny rank 3-5 (idx 2-4, mirror)
    jb .no
    cmp eax, 4
    ja .no
.rank_ok:
    mov r8d, r12d
    and r8d, 7              ; f
    lea rsi, [board]
    ; --- brany vlastnym pesiacom ---
    ; biely: pesiac na sq-7 (f>=1), sq-9 (f<=6)
    ; cierny: pesiac na sq+7 (f<=6), sq+9 (f>=1)
    test r13d, r13d
    jnz .def_b
    test r8d, r8d
    jz .def_w9
    lea ecx, [r12 - 7]
    movzx edx, byte [rsi + rcx]
    cmp edx, PAWN | WHITE
    je .defended
.def_w9:
    cmp r8d, 7
    je .no
    lea ecx, [r12 - 9]
    movzx edx, byte [rsi + rcx]
    cmp edx, PAWN | WHITE
    jne .no
    jmp .defended
.def_b:
    cmp r8d, 7
    je .def_b9
    lea ecx, [r12 + 7]
    movzx edx, byte [rsi + rcx]
    cmp edx, PAWN | BLACK
    je .defended
.def_b9:
    test r8d, r8d
    jz .no
    lea ecx, [r12 + 9]
    movzx edx, byte [rsi + rcx]
    cmp edx, PAWN | BLACK
    jne .no
.defended:
    ; --- nie je napadnutelny nepriatelskymi pesiacmi ---
    ; biely: cierni pesiaci na sq+7 (f<=6), sq+9 (f>=1)
    ; cierny: bieli pesiaci na sq-7 (f>=1), sq-9 (f<=6)
    test r13d, r13d
    jnz .atk_b
    cmp r8d, 7
    je .atk_w9
    lea ecx, [r12 + 7]
    movzx edx, byte [rsi + rcx]
    cmp edx, PAWN | BLACK
    je .no
.atk_w9:
    test r8d, r8d
    jz .yes
    lea ecx, [r12 + 9]
    movzx edx, byte [rsi + rcx]
    cmp edx, PAWN | BLACK
    je .no
    jmp .yes
.atk_b:
    test r8d, r8d
    jz .atk_b9
    lea ecx, [r12 - 7]
    movzx edx, byte [rsi + rcx]
    cmp edx, PAWN | WHITE
    je .no
.atk_b9:
    cmp r8d, 7
    je .yes
    lea ecx, [r12 - 9]
    movzx edx, byte [rsi + rcx]
    cmp edx, PAWN | WHITE
    je .no
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; ============================================================
; INKREMENTALNY EVAL CACHE
; ============================================================

; ============================================================
; evaluate - vrati skore z pohladu bieleho (tapered MG/EG)
; Vystup: eax = skore
; Fazy: phase = suma vah non-pawn materialu (max 24);
;       skore = (mg*phase + eg*(24-phase)) / 24
; ============================================================
evaluate:
    inc qword [prof_evals]
    push rbp
    mov rbp, rsp
    sub rsp, 128
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rsi
    push rdi

    ; NNUE faza 2: priama evaluacia 1-skrytou-vrstvou sietou
    cmp byte [eval_mode], 2
    jne .classic_eval
    cmp byte [nnue2_ready], 1
    jne .classic_eval
    call nnue2_eval
    ; nnue2_eval vracia skore z pohladu strany na tahu (STM),
    ; evaluate vsak drzi kontrakt skore z pohladu bieleho.
    movzx ecx, byte [side]
    test ecx, ecx
    jz .nnue_white_pov
    neg eax

.nnue_white_pov:
    ; low-confidence fallback: v openingu pri velmi plochom NNUE skore
    ; (< 0.96 pešiaka) pouzi classic eval, aby sa rozlisili planove tahy.
    mov edx, eax
    movzx ecx, word [fullmove]
    cmp ecx, 20
    ja .nnue_use
    mov ecx, edx
    test ecx, ecx
    jns .nnue_abs_ready
    neg ecx
.nnue_abs_ready:
    cmp ecx, 96
    jle .classic_eval
.nnue_use:
    mov eax, edx

    ; nevyrošádovaný kral na e-file (s rookom stale na h-file):
    ; jemny, ale citelny post-korekčný malus pre NNUE hodnotenie.
    lea rbx, [board]
    movzx ecx, byte [rbx + 4]       ; e1
    cmp ecx, KING | WHITE
    jne .nnue_w_e2
    movzx ecx, byte [rbx + 7]       ; h1
    cmp ecx, ROOK | WHITE
    jne .nnue_w_e2
    sub eax, 64
.nnue_w_e2:
    movzx ecx, byte [rbx + 12]      ; e2
    cmp ecx, KING | WHITE
    jne .nnue_b_e8
    movzx ecx, byte [rbx + 7]       ; h1
    cmp ecx, ROOK | WHITE
    jne .nnue_b_e8
    sub eax, 48

.nnue_b_e8:
    movzx ecx, byte [rbx + 60]      ; e8
    cmp ecx, KING | BLACK
    jne .nnue_b_e7
    movzx ecx, byte [rbx + 63]      ; h8
    cmp ecx, ROOK | BLACK
    jne .nnue_b_e7
    add eax, 64
.nnue_b_e7:
    movzx ecx, byte [rbx + 52]      ; e7
    cmp ecx, KING | BLACK
    jne .nnue_kf_fix
    movzx ecx, byte [rbx + 63]      ; h8
    cmp ecx, ROOK | BLACK
    jne .nnue_kf_fix
    add eax, 48

    ; jemna korekcia: netrestat realnu rošádu, ale penalizovat
    ; manualny krok Kf1/Kf8 s rookom stale na h-file.
.nnue_kf_fix:
    movzx ecx, byte [rbx + 5]       ; f1
    cmp ecx, KING | WHITE
    jne .nnue_b_fix
    movzx ecx, byte [rbx + 7]       ; h1
    cmp ecx, ROOK | WHITE
    jne .nnue_b_fix
    sub eax, 24

.nnue_b_fix:
    movzx ecx, byte [rbx + 61]      ; f8
    cmp ecx, KING | BLACK
    jne .nnue_done
    movzx ecx, byte [rbx + 63]      ; h8
    cmp ecx, ROOK | BLACK
    jne .nnue_done
    add eax, 24

.nnue_done:
    jmp .neg_done_early

.classic_eval:
    ; lokaly:
    ; [rbp-8]  = maska bielych pesiacov
    ; [rbp-16] = maska ciernych pesiacov
    ; [rbp-24..-17] = pocty bielych pesiacov per file
    ; [rbp-32..-25] = pocty ciernych pesiacov per file
    ; [rbp-36] = pocet bielych strelcov (dword)
    ; [rbp-40] = pocet ciernych strelcov (dword)
    ; [rbp-48] = EG akumulator (dword)
    ; [rbp-56] = faza hry (dword, max 24)
    ; [rbp-64] = policko bieleho krala (dword)
    ; [rbp-68] = policko cierneho krala (dword)
    ; [rbp-72] = king attack score pre bieleho (utok na cierneho krala) (dword)
    ; [rbp-76] = king attack score pre cierneho (utok na bieleho krala) (dword)
    ; [rbp-100] = baseline r15 pri prepocitavani pawn struct (dword)
    ; [rbp-112] = vlastna maska strany (mobility), [rbp-120] = base
    ;   bb_pieces slotov, [rbp-128] = color idx (mobility)
    xor eax, eax
    mov [rbp - 8], rax
    mov [rbp - 16], rax
    mov [rbp - 24], rax
    mov [rbp - 32], rax
    mov [rbp - 40], rax
    mov [rbp - 48], rax
    mov [rbp - 56], rax
    mov [rbp - 64], rax
    mov [rbp - 68], rax
    mov dword [rbp - 72], 0
    mov dword [rbp - 76], 0

.scan_start:
    xor r15d, r15d          ; MG akumulator
%if ENABLE_PL_INFRA = 1
    cmp byte [pl_dirty], 0
    jne .scan_board
    lea rax, [pl_lists]
    mov [eval_dbg_lp_lists_base], rax
    lea rax, [pl_counts]
    mov [eval_dbg_lp_counts_base], rax
    xor r10d, r10d          ; piece index 0..11

.scan_piece_kind:
    cmp r10d, 12
    jge .scan_done
    movzx r11d, byte [pl_counts + r10]
    mov byte [eval_dbg_lp_counts + r10], r11b
    mov byte [eval_dbg_lp_first + r10], 255
    test r11d, r11d
    jz .scan_next_kind
    mov dword [rbp - 104], r11d
    mov r8, r10
    shl r8, 4
    lea rax, [pl_lists]
    add r8, rax
    mov [rbp - 120], r8
    mov dword [rbp - 80], 0 ; index v zozname

.scan_piece_entry:
    mov eax, dword [rbp - 80]
    cmp eax, dword [rbp - 104]
    jge .scan_next_kind
    mov r8, [rbp - 120]
    movzx r12d, byte [r8 + rax]
    test eax, eax
    jne .scan_after_first_dbg
    mov byte [eval_dbg_lp_first + r10], r12b
.scan_after_first_dbg:
    mov r14d, r10d
    cmp r14d, 6
    jb .scan_piece_white
    sub r14d, 6
    mov r13d, BLACK
    jmp .scan_piece_type
.scan_piece_white:
    xor r13d, r13d
.scan_piece_type:
    inc r14d
    jmp .piece_eval

.scan_piece_continue:
    inc dword [rbp - 80]
    jmp .scan_piece_entry

.scan_next_kind:
    inc r10d
    jmp .scan_piece_kind

.scan_board:
%endif
    xor r12, r12            ; index policka

.next_square:
    lea rsi, [board]
    movzx r13d, byte [rsi + r12]
    test r13d, r13d
    jz .skip_board

    mov r14d, r13d
    and r14d, PIECE_MASK    ; typ figury
    and r13d, COLOR_MASK    ; farba (0 alebo BLACK=8)

.piece_eval:

    ; --- MG/EG hodnota ---
    ; phase-1 own/enemy PST lookup ma zmysel len pre eval_mode 1 (trenovane
    ; STM-relativne tabulky z net.nnue). eval_mode 2 sem vstupuje len cez
    ; low-confidence fallback a ten ma byt classic eval — pri default tabulkach
    ; z pst_init (own == enemy) STM-relativny mirror prehodil PST prispevky
    ; medzi farbami pre cierneho STM (P0: EM2 hlbka 2+ v otvarani).
    cmp byte [eval_mode], 1
    je .nnue_lookup
    ; classic: mirror podla absolutnej farby, jedna tabulka na typ
    lea rdi, [material_mg]
    mov eax, dword [rdi + r14*4]
    lea rdi, [pst_ptrs_mg]
    mov rdi, [rdi + r14*8]
    mov rbx, r12
    test r13d, r13d
    jz .mg_index
    xor rbx, 56             ; mirror pre cierne
.mg_index:
    movsx edx, byte [rdi + rbx]
    add eax, edx            ; eax = MG hodnota figury

    ; --- EG hodnota (rovnaky mirror index v rbx) ---
    lea rdi, [material_eg]
    mov edx, dword [rdi + r14*4]
    lea rdi, [pst_ptrs_eg]
    mov rdi, [rdi + r14*8]
    movsx edi, byte [rdi + rbx]
    add edx, edi            ; edx = EG hodnota figury
    jmp .pst_done

.nnue_lookup:
    ; NNUE: own/enemy blok + rel. square z pohladu STM
    ; r14 = typ, r13d = farba (0/8), r12 = policko
    mov eax, r13d
    shr eax, 3              ; color_idx 0/1
    movzx edx, byte [side]
    xor eax, edx            ; 0 = own farba, 1 = enemy
    mov ecx, eax
    shl ecx, 3
    sub ecx, eax            ; color_rel*7
    add ecx, r14d           ; index do pst_ptrs (0..13)
    mov ebx, r12d
    test eax, eax
    jz .nnue_index
    xor ebx, 56             ; enemy figurky: mirror z pohladu STM
.nnue_index:
    lea rdi, [pst_ptrs_mg]
    mov rdi, [rdi + rcx*8]
    movsx edx, byte [rdi + rbx]
    lea rdi, [material_mg]
    mov eax, dword [rdi + r14*4]
    add eax, edx

    lea rdi, [material_eg]
    mov edx, dword [rdi + r14*4]
    lea rdi, [pst_ptrs_eg]
    mov rdi, [rdi + rcx*8]
    movsx edi, byte [rdi + rbx]
    add edx, edi
.pst_done:

    ; --- akumulacia (biely +, cierny -) ---
    test r13d, r13d
    jz .add_white
    sub r15d, eax
    sub dword [rbp - 48], edx
    jmp .phase_add
.add_white:
    add r15d, eax
    add dword [rbp - 48], edx

.phase_add:
    ; prispevok k faze (non-pawn material)
    lea rdi, [phase_weights]
    movzx eax, byte [rdi + r14]
    add dword [rbp - 56], eax

    ; policka kralov pre king safety
    cmp r14d, KING
    jne .collect
    test r13d, r13d
    jnz .king_b_sq
    mov [rbp - 64], r12d
    jmp .collect
.king_b_sq:
    mov [rbp - 68], r12d

.collect:
    ; zber dat pre bishop pair (pawn masky/file counts sa beru priamo
    ; z bitboardov po skene — pozri .pawn_from_bb)
    cmp r14d, PAWN
    je .piece_eval_done
    cmp r14d, BISHOP
    jne .piece_eval_done
.col_bishop:
    cmp r14d, BISHOP
    jne .piece_eval_done
    test r13d, r13d
    jnz .col_black_bishop
    inc dword [rbp - 36]
    jmp .piece_eval_done
.col_black_bishop:
    inc dword [rbp - 40]

.piece_eval_done:
%if ENABLE_PL_INFRA = 1
    cmp byte [pl_dirty], 0
    je .scan_piece_continue
%endif

.skip_board:
    inc r12
    cmp r12, 64
    jl .next_square

.scan_done:

    ; ---- pawn masky + file counts priamo z bitboardov ----
    ; (bitboard stav je primarny a po kazdom make/unmake synchronizovany)
    lea rax, [bb_pieces]
    mov rdx, [rax]              ; bb_pieces[biela*6 + P-1]
    mov [rbp - 8], rdx
    mov rdx, [rax + 6*8]        ; bb_pieces[cierna*6 + P-1]
    mov [rbp - 16], rdx
    lea rsi, [file_masks]
    xor ecx, ecx
.pawn_fc_loop:
    mov rdi, [rsi + rcx*8]
    mov rax, rdi
    and rax, [rbp - 8]
    popcnt rax, rax
    mov [rbp - 24 + rcx], al
    mov rax, rdi
    and rax, [rbp - 16]
    popcnt rax, rax
    mov [rbp - 32 + rcx], al
    inc ecx
    cmp ecx, 8
    jl .pawn_fc_loop

.mobility:
    ; ================= MOBILITY + OUTPOSTY (bitboard) =================
    ; pocet cielov N/B/R/Q = popcount(utoky(sq, bb_occ) & ~vlastna);
    ; vaha za policko podla typu, MG/EG. Bit-ekvivalent povodneho
    ; mailbox MOB_WALK countingu (prazdne + super policka, vlastne
    ; figury blokuju).
    lea rbx, [board]
    mov qword [rbp - 128], 0     ; color idx 0=biela, 1=cierna
.mob_color:
    mov r12, [rbp - 128]
    mov r13d, r12d
    shl r13d, 3                  ; farba 0/8
    lea rax, [bb_side]
    mov rax, [rax + r12*8]
    mov [rbp - 112], rax         ; vlastna maska
    lea rax, [r12 + r12*2]
    shl rax, 4                   ; color*48
    lea rdx, [bb_pieces]
    add rax, rdx
    add rax, 8                   ; base = &bb_pieces[color*6 + 1] (jazdec)
    mov [rbp - 120], rax

    MOB_BLOCK 0,  KNIGHT, 0, 1
    MOB_BLOCK 8,  BISHOP, 1, 1
    MOB_BLOCK 16, ROOK,   2, 0
    MOB_BLOCK 24, QUEEN,  3, 0

    inc qword [rbp - 128]
    cmp qword [rbp - 128], 2
    jl .mob_color

    ; ================= KING SAFETY (iba MG) =================
    ; plati na vlastnej polovici (biely rank 0-3, cierny 4-7):
    ; - suprada pesiacov 1-2 ranky pred kralom: +SHIELD_PAWN za kazdeho
    ; - file krala +/- susedne: otvoreny -KINGOPEN_PEN, semi -KINGSEMI_PEN
    ; --- biely kral ---
    mov r12d, [rbp - 64]
    mov eax, r12d
    shr eax, 3
    cmp eax, 3
    ja .ks_w_done               ; kral za centralizovany: bez bonusu
    lea ecx, [r12 + 8]
    cmp ecx, 64
    jae .ks_w_files
    movzx edx, byte [rbx + rcx]
    cmp edx, PAWN | WHITE
    jne .ks_w_sh2
    add r15d, SHIELD_PAWN
.ks_w_sh2:
    add ecx, 8
    cmp ecx, 64
    jae .ks_w_files
    movzx edx, byte [rbx + rcx]
    cmp edx, PAWN | WHITE
    jne .ks_w_files
    add r15d, SHIELD_PAWN
.ks_w_files:
    mov r8d, r12d
    and r8d, 7                  ; file krala
    lea r9d, [r8 - 1]
    cmp r9d, 0
    jge .ks_w_fx0
    xor r9d, r9d
.ks_w_fx0:
    mov r10d, r8d
    add r10d, 1
    cmp r10d, 7
    jle .ks_w_fx_loop
    mov r10d, 7
.ks_w_fx_loop:
    cmp r9d, r10d
    jg .ks_w_done
    movzx eax, byte [rbp - 24 + r9]    ; biele pesiacie na file
    movzx edx, byte [rbp - 32 + r9]    ; cierne pesiacie na file
    lea ecx, [rax + rdx]
    test ecx, ecx
    jnz .ks_w_semi
    sub r15d, KINGOPEN_PEN
    jmp .ks_w_fx_next
.ks_w_semi:
    test eax, eax
    jnz .ks_w_fx_next
    sub r15d, KINGSEMI_PEN
.ks_w_fx_next:
    inc r9d
    jmp .ks_w_fx_loop
.ks_w_done:

    ; --- cierny kral ---
    mov r12d, [rbp - 68]
    mov eax, r12d
    shr eax, 3
    cmp eax, 4
    jb .ks_b_done               ; kral prilis vysoko/centralizovany: skip
    lea ecx, [r12 - 8]
    jmp .ks_b_sh1
.ks_b_sh1:
    test ecx, ecx
    js .ks_b_files
    movzx edx, byte [rbx + rcx]
    cmp edx, PAWN | BLACK
    jne .ks_b_sh2
    sub r15d, SHIELD_PAWN
.ks_b_sh2:
    sub ecx, 8
    test ecx, ecx
    js .ks_b_files
    movzx edx, byte [rbx + rcx]
    cmp edx, PAWN | BLACK
    jne .ks_b_files
    sub r15d, SHIELD_PAWN
.ks_b_files:
    mov r8d, r12d
    and r8d, 7
    lea r9d, [r8 - 1]
    cmp r9d, 0
    jge .ks_b_fx0
    xor r9d, r9d
.ks_b_fx0:
    mov r10d, r8d
    add r10d, 1
    cmp r10d, 7
    jle .ks_b_fx_loop
    mov r10d, 7
.ks_b_fx_loop:
    cmp r9d, r10d
    jg .ks_b_done
    movzx eax, byte [rbp - 24 + r9]
    movzx edx, byte [rbp - 32 + r9]
    lea ecx, [rax + rdx]
    test ecx, ecx
    jnz .ks_b_semi
    add r15d, KINGOPEN_PEN      ; penal pre cierneho = plus pre bieleho
    jmp .ks_b_fx_next
.ks_b_semi:
    test edx, edx               ; vlastny = cierny
    jnz .ks_b_fx_next
    add r15d, KINGSEMI_PEN
.ks_b_fx_next:
    inc r9d
    jmp .ks_b_fx_loop
.ks_b_done:

    ; castled shelter (MG): iba realna kratka rošáda
    ; (biely: Kg1 + Rf1, cierny: Kg8 + Rf8).
    ; Neodmenujeme manualny krok krala (napr. Ke1-f1), ktory
    ; predtym dostaval rovnaky shelter bonus ako rošáda.
    ; --- biely short-castled king (Kg1 + Rf1) ---
    mov eax, [rbp - 64]
    cmp eax, 6                  ; g1
    jne .ks_bc_check
    movzx ecx, byte [rbx + 5]   ; f1
    cmp ecx, ROOK | WHITE
    jne .ks_bc_check
.ks_wc_apply:
    ; f2 = 13, g2 = 14, h2 = 15
    movzx ecx, byte [rbx + 13]
    cmp ecx, PAWN | WHITE
    je .ks_wc_f_ok
    sub r15d, CASTLE_SHELTER_MISS
    jmp .ks_wc_g
.ks_wc_f_ok:
    add r15d, CASTLE_SHELTER_BONUS
.ks_wc_g:
    movzx ecx, byte [rbx + 14]
    cmp ecx, PAWN | WHITE
    je .ks_wc_g_ok
    sub r15d, CASTLE_SHELTER_MISS
    jmp .ks_wc_h
.ks_wc_g_ok:
    add r15d, CASTLE_SHELTER_BONUS
.ks_wc_h:
    movzx ecx, byte [rbx + 15]
    cmp ecx, PAWN | WHITE
    je .ks_wc_h_ok
    sub r15d, CASTLE_SHELTER_MISS
    jmp .ks_bc_check
.ks_wc_h_ok:
    add r15d, CASTLE_SHELTER_BONUS

    ; --- cierny short-castled king (Kg8 + Rf8) ---
.ks_bc_check:
    mov eax, [rbp - 68]
    cmp eax, 62                 ; g8
    jne .ks_castle_done
    movzx ecx, byte [rbx + 61]  ; f8
    cmp ecx, ROOK | BLACK
    jne .ks_castle_done
.ks_bc_apply:
    ; f7 = 53, g7 = 54, h7 = 55
    movzx ecx, byte [rbx + 53]
    cmp ecx, PAWN | BLACK
    je .ks_bc_f_ok
    add r15d, CASTLE_SHELTER_MISS
    jmp .ks_bc_g
.ks_bc_f_ok:
    sub r15d, CASTLE_SHELTER_BONUS
.ks_bc_g:
    movzx ecx, byte [rbx + 54]
    cmp ecx, PAWN | BLACK
    je .ks_bc_g_ok
    add r15d, CASTLE_SHELTER_MISS
    jmp .ks_bc_h
.ks_bc_g_ok:
    sub r15d, CASTLE_SHELTER_BONUS
.ks_bc_h:
    movzx ecx, byte [rbx + 55]
    cmp ecx, PAWN | BLACK
    je .ks_bc_h_ok
    add r15d, CASTLE_SHELTER_MISS
    jmp .ks_castle_done
.ks_bc_h_ok:
    sub r15d, CASTLE_SHELTER_BONUS
.ks_castle_done:

    ; ================= KING TROPISM (MG only) =================
    ; Pre kazdu nePesiacku nKralovsku figuru: Chebyshev <= 2 od nepriatelovho krala
    ; biela figura -> utok na cierneho krala ([rbp-68]); cierna -> na bieleho ([rbp-64])
%if ENABLE_PL_INFRA = 1
    cmp byte [pl_dirty], 0
    jne .trop_board
    xor r10d, r10d          ; piece index 0..11

.trop_kind_loop:
    cmp r10d, 12
    jge .trop_done
    mov r14d, r10d
    cmp r14d, 6
    jb .trop_kind_white
    sub r14d, 6
    mov r13d, BLACK
    jmp .trop_kind_type
.trop_kind_white:
    xor r13d, r13d
.trop_kind_type:
    inc r14d
    cmp r14d, PAWN
    je .trop_kind_next
    cmp r14d, KING
    je .trop_kind_next
    movzx r11d, byte [pl_counts + r10]
    test r11d, r11d
    jz .trop_kind_next
    mov dword [rbp - 104], r11d
    mov r8, r10
    shl r8, 4
    lea rax, [pl_lists]
    add r8, rax
    mov [rbp - 120], r8
    mov dword [rbp - 80], 0

.trop_entry_loop:
    mov eax, dword [rbp - 80]
    cmp eax, dword [rbp - 104]
    jge .trop_kind_next
    mov r8, [rbp - 120]
    movzx r12d, byte [r8 + rax]
    jmp .trop_piece

.trop_piece_next:
    inc dword [rbp - 80]
    jmp .trop_entry_loop

.trop_kind_next:
    inc r10d
    jmp .trop_kind_loop

.trop_board:
%endif
    lea rsi, [board]
    xor r12, r12
.trop_loop:
    movzx eax, byte [rsi + r12]
    test eax, eax
    jz .trop_next_board
    mov r13d, eax
    and r13d, COLOR_MASK
    mov r14d, eax
    and r14d, PIECE_MASK
    cmp r14d, PAWN
    je .trop_next_board
    cmp r14d, KING
    je .trop_next_board

.trop_piece:
    ; vybrat cieloveho krala
    test r13d, r13d
    jnz .trop_is_black
    mov ebx, [rbp - 68]         ; cierna figura: biely utocnik -> cierne kralov sq
    jmp .trop_dist
.trop_is_black:
    mov ebx, [rbp - 64]         ; cierna figura -> biely kral
.trop_dist:
    ; file distance
    mov ecx, r12d
    and ecx, 7
    mov edx, ebx
    and edx, 7
    sub ecx, edx
    test ecx, ecx
    jns .trop_fok
    neg ecx
.trop_fok:
    ; rank distance
    mov r8d, r12d
    shr r8d, 3
    mov r9d, ebx
    shr r9d, 3
    sub r8d, r9d
    test r8d, r8d
    jns .trop_rok
    neg r8d
.trop_rok:
    ; chebyshev = max
    cmp ecx, r8d
    jge .trop_cheb
    mov ecx, r8d
.trop_cheb:
    cmp ecx, 2
    jg .trop_piece_done
    lea rdi, [tropism_weights]
    movzx eax, byte [rdi + r14]
    test r13d, r13d
    jnz .trop_acc_black
    add dword [rbp - 72], eax   ; biely utoci na cierneho krala
    jmp .trop_piece_done
.trop_acc_black:
    add dword [rbp - 76], eax   ; cierny utoci na bieleho krala

.trop_piece_done:
%if ENABLE_PL_INFRA = 1
    cmp byte [pl_dirty], 0
    je .trop_piece_next
%endif

.trop_next_board:
    inc r12
    cmp r12, 64
    jl .trop_loop

.trop_done:

    ; aplikovat: cap na 16, * TROPISM_SCALE, len v MG
    mov eax, [rbp - 72]
    cmp eax, 16
    jle .trop_w_cap
    mov eax, 16
.trop_w_cap:
    imul eax, eax, TROPISM_SCALE
    add r15d, eax               ; biely profituje

    mov eax, [rbp - 76]
    cmp eax, 16
    jle .trop_b_cap
    mov eax, 16
.trop_b_cap:
    imul eax, eax, TROPISM_SCALE
    sub r15d, eax               ; cierny profituje (penalty pre bieleho)

    ; DEBUG dump
    mov [eval_dbg_mg], r15d
    mov eax, [rbp - 48]
    mov [eval_dbg_eg], eax
    mov eax, [rbp - 56]
    mov [eval_dbg_phase], eax
    mov eax, [rbp - 64]
    mov [eval_dbg_wk], eax
    mov eax, [rbp - 68]
    mov [eval_dbg_bk], eax
    mov eax, [rbp - 72]
    mov [eval_dbg_trop_w], eax
    mov eax, [rbp - 76]
    mov [eval_dbg_trop_b], eax

    ; --- tapered interpolacia: skore = (mg*phase + eg*(24-phase)) / 24 ---
    mov eax, [rbp - 48]         ; eg
    mov ecx, 24
    sub ecx, [rbp - 56]         ; 24 - phase
    imul eax, ecx               ; eg * (24-phase)
    mov edx, r15d               ; mg
    imul edx, [rbp - 56]        ; mg * phase
    add eax, edx
    cdq
    mov ecx, 24
    idiv ecx
    mov r15d, eax               ; tapered skore do r15 (dalsie termy pripocitavaju)

    ; --- bishop pair ---
    cmp dword [rbp - 36], 2
    jl .no_bp_w
    add r15d, BISHOP_PAIR
.no_bp_w:
    cmp dword [rbp - 40], 2
    jl .no_bp_b
    sub r15d, BISHOP_PAIR
.no_bp_b:

    ; --- pawn structure per file: doubled + isolated ---
    mov qword [passed_w], 0
    mov qword [passed_b], 0
    xor r12, r12            ; file
.file_loop:
    movzx eax, byte [rbp - 24 + r12]    ; wcount
    movzx ebx, byte [rbp - 32 + r12]    ; bcount

    ; doubled: kazdy dalsi pesiak na file -DOUBLED_PEN
    cmp eax, 1
    jle .no_dbl_w
    lea ecx, [eax - 1]
    imul ecx, ecx, DOUBLED_PEN
    sub r15d, ecx
.no_dbl_w:
    cmp ebx, 1
    jle .no_dbl_b
    lea ecx, [ebx - 1]
    imul ecx, ecx, DOUBLED_PEN
    add r15d, ecx
.no_dbl_b:

    ; isolated biely: ziadny biely pesiak na susednych files
    test eax, eax
    jz .iso_w_done
    test r12, r12
    jz .iso_w_left_ok
    cmp byte [rbp - 24 + r12 - 1], 0
    jne .iso_w_done
.iso_w_left_ok:
    cmp r12, 7
    je .iso_w_pen
    cmp byte [rbp - 24 + r12 + 1], 0
    jne .iso_w_done
.iso_w_pen:
    imul ecx, eax, ISOLATED_PEN
    sub r15d, ecx
.iso_w_done:

    ; isolated cierny
    test ebx, ebx
    jz .iso_b_done
    test r12, r12
    jz .iso_b_left_ok
    cmp byte [rbp - 32 + r12 - 1], 0
    jne .iso_b_done
.iso_b_left_ok:
    cmp r12, 7
    je .iso_b_pen
    cmp byte [rbp - 32 + r12 + 1], 0
    jne .iso_b_done
.iso_b_pen:
    imul ecx, ebx, ISOLATED_PEN
    add r15d, ecx
.iso_b_done:

    inc r12
    cmp r12, 8
    jl .file_loop

    ; --- passed pawns: biele ---
    mov rax, [rbp - 8]
.pp_w_loop:
    test rax, rax
    jz .pp_w_done
    bsf rdx, rax
    btr rax, rdx
    ; file mask so susednymi
    mov rbx, rdx
    and rbx, 7
    lea rsi, [file_masks]
    mov rdi, [rsi + rbx*8]
    test rbx, rbx
    jz .pp_w_noleft
    or rdi, [rsi + rbx*8 - 8]
.pp_w_noleft:
    cmp rbx, 7
    je .pp_w_noright
    or rdi, [rsi + rbx*8 + 8]
.pp_w_noright:
    ; blockery = cierne pesiacie vysie ranky na 3 files
    mov rcx, rdx
    shr rcx, 3
    lea rsi, [hi_rank_masks]
    mov rsi, [rsi + rcx*8]
    and rdi, rsi
    and rdi, [rbp - 16]
    jnz .pp_w_loop
    ; passed: bonus = PASSED_BASE + PASSED_STEP * rank
    bts qword [passed_w], rdx   ; zaznac bieleho passera
    imul ecx, ecx, PASSED_STEP
    add ecx, PASSED_BASE
    add r15d, ecx
    jmp .pp_w_loop
.pp_w_done:

    ; --- passed pawns: cierne ---
    mov rax, [rbp - 16]
.pp_b_loop:
    test rax, rax
    jz .pp_b_done
    bsf rdx, rax
    btr rax, rdx
    mov rbx, rdx
    and rbx, 7
    lea rsi, [file_masks]
    mov rdi, [rsi + rbx*8]
    test rbx, rbx
    jz .pp_b_noleft
    or rdi, [rsi + rbx*8 - 8]
.pp_b_noleft:
    cmp rbx, 7
    je .pp_b_noright
    or rdi, [rsi + rbx*8 + 8]
.pp_b_noright:
    ; blockery = biele pesiacie na nizsich rankoch
    mov rcx, rdx
    shr rcx, 3
    lea rsi, [lo_rank_masks]
    mov rsi, [rsi + rcx*8]
    and rdi, rsi
    and rdi, [rbp - 8]
    jnz .pp_b_loop
    ; passed: bonus = PASSED_BASE + PASSED_STEP * (7 - rank); rcx = rank
    ; pozor: nepouzivat eax/rax - v rax je maska ciernych pesiacov!
    bts qword [passed_b], rdx   ; zaznac cierneho passera
    mov edx, 7
    sub edx, ecx
    imul edx, edx, PASSED_STEP
    add edx, PASSED_BASE
    sub r15d, edx
    jmp .pp_b_loop
.pp_b_done:

    ; --- connected passed pawns ---
    ; passed pesiak s kamaratom na susednom file (rovnaky/susedny rank)
    ; dostane maly bonus; pri postupe rastie.
    lea rsi, [board]

    ; bieli passeri
    mov rax, [passed_w]
.cpp_w_loop:
    test rax, rax
    jz .cpp_b_start
    bsf rdx, rax
    btr rax, rdx

    mov ecx, edx
    and ecx, 7              ; file
    mov r8d, edx
    shr r8d, 3              ; rank
    xor r9d, r9d            ; found flag

    ; lava strana (f-1)
    test ecx, ecx
    jz .cpp_w_right
    lea r10d, [edx - 1]     ; rovnaky rank
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | WHITE
    je .cpp_w_found
    test r8d, r8d
    jz .cpp_w_l_up
    lea r10d, [edx - 9]     ; rank-1
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | WHITE
    je .cpp_w_found
.cpp_w_l_up:
    cmp r8d, 7
    je .cpp_w_right
    lea r10d, [edx + 7]     ; rank+1
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | WHITE
    je .cpp_w_found

.cpp_w_right:
    cmp ecx, 7
    je .cpp_w_apply
    lea r10d, [edx + 1]     ; rovnaky rank
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | WHITE
    je .cpp_w_found
    test r8d, r8d
    jz .cpp_w_r_up
    lea r10d, [edx - 7]     ; rank-1
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | WHITE
    je .cpp_w_found
.cpp_w_r_up:
    cmp r8d, 7
    je .cpp_w_apply
    lea r10d, [edx + 9]     ; rank+1
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | WHITE
    je .cpp_w_found
    jmp .cpp_w_apply

.cpp_w_found:
    mov r9d, 1

.cpp_w_apply:
    test r9d, r9d
    jz .cpp_w_loop
    mov r10d, r8d
    imul r10d, CONNECTED_PP_STEP
    add r10d, CONNECTED_PP_BASE
    add r15d, r10d
    jmp .cpp_w_loop

.cpp_b_start:
    mov rax, [passed_b]
.cpp_b_loop:
    test rax, rax
    jz .cpp_done
    bsf rdx, rax
    btr rax, rdx

    mov ecx, edx
    and ecx, 7              ; file
    mov r8d, edx
    shr r8d, 3              ; rank
    xor r9d, r9d            ; found flag

    ; lava strana (f-1)
    test ecx, ecx
    jz .cpp_b_right
    lea r10d, [edx - 1]
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | BLACK
    je .cpp_b_found
    test r8d, r8d
    jz .cpp_b_l_up
    lea r10d, [edx - 9]
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | BLACK
    je .cpp_b_found
.cpp_b_l_up:
    cmp r8d, 7
    je .cpp_b_right
    lea r10d, [edx + 7]
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | BLACK
    je .cpp_b_found

.cpp_b_right:
    cmp ecx, 7
    je .cpp_b_apply
    lea r10d, [edx + 1]
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | BLACK
    je .cpp_b_found
    test r8d, r8d
    jz .cpp_b_r_up
    lea r10d, [edx - 7]
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | BLACK
    je .cpp_b_found
.cpp_b_r_up:
    cmp r8d, 7
    je .cpp_b_apply
    lea r10d, [edx + 9]
    movzx r11d, byte [rsi + r10]
    cmp r11d, PAWN | BLACK
    je .cpp_b_found
    jmp .cpp_b_apply

.cpp_b_found:
    mov r9d, 1

.cpp_b_apply:
    test r9d, r9d
    jz .cpp_b_loop
    mov r10d, 7
    sub r10d, r8d
    imul r10d, CONNECTED_PP_STEP
    add r10d, CONNECTED_PP_BASE
    sub r15d, r10d
    jmp .cpp_b_loop

.cpp_done:

    ; --- veze: open/semi-open file, 7. rank ---
    xor r12, r12
.rook_loop:
    lea rsi, [board]
    movzx eax, byte [rsi + r12]
    mov ebx, eax
    and ebx, PIECE_MASK
    cmp ebx, ROOK
    jne .rook_next
    mov r13d, eax
    and r13d, COLOR_MASK
    mov rbx, r12
    and rbx, 7
    lea rsi, [file_masks]
    mov rdi, [rsi + rbx*8]
    ; open file? ziadny pesiak (ani biely ani cierny)
    mov rax, [rbp - 8]
    or rax, [rbp - 16]
    test rax, rdi
    jnz .rook_semi
    test r13d, r13d
    jnz .rook_open_b
    add r15d, ROOK_OPEN
    jmp .rook_rank
.rook_open_b:
    sub r15d, ROOK_OPEN
    jmp .rook_rank
.rook_semi:
    ; semi-open: ziadny vlastny pesiak na file
    test r13d, r13d
    jnz .rook_semi_b
    mov rax, [rbp - 8]
    jmp .rook_semi_test
.rook_semi_b:
    mov rax, [rbp - 16]
.rook_semi_test:
    test rax, rdi
    jnz .rook_rank
    test r13d, r13d
    jnz .rook_semi_b2
    add r15d, ROOK_SEMI
    jmp .rook_rank
.rook_semi_b2:
    sub r15d, ROOK_SEMI
.rook_rank:
    ; 7. rank: biely rank 6, cierny rank 1
    mov rax, r12
    shr eax, 3
    test r13d, r13d
    jnz .rook_rank_b
    cmp eax, 6
    jne .rook_behind_w
    add r15d, ROOK_SEVENTH
    jmp .rook_behind_w
.rook_rank_b:
    cmp eax, 1
    jne .rook_behind_b
    sub r15d, ROOK_SEVENTH
    jmp .rook_behind_b

.rook_behind_w:
    ; rook behind passed pawn (biely): veza je na rovnakom file, nizsi rank ako passer
    ; file mask = rdi (uz vypocitana ako jednofile mask v rbx*8)
    lea rsi, [file_masks]
    mov rdi, [rsi + rbx*8]     ; rbx = file of rook
    test r13d, r13d
    jnz .rook_behind_b          ; len biela veza
    mov rax, [passed_w]         ; passed white bitmask
    and rax, rdi                ; biely passer na rovnakom file?
    jz .rook_next
    bsf rcx, rax                ; najdi passera
    mov edx, ecx
    shr edx, 3                  ; rank passera
    mov eax, r12d
    shr eax, 3                  ; rank vezy
    cmp eax, edx                ; veza musi byt NIZSSIE ako passer
    jge .rook_next
    add r15d, ROOK_BEHIND_PP
    jmp .rook_next
.rook_behind_b:
    ; cierna veza za ciernym passerom: veza je na rovnakom file, VYSSI rank ako passer
    test r13d, r13d
    jz .rook_next               ; len cierna veza
    lea rsi, [file_masks]
    mov rdi, [rsi + rbx*8]
    mov rax, [passed_b]         ; passed black bitmask
    and rax, rdi
    jz .rook_next
    bsf rcx, rax
    mov edx, ecx
    shr edx, 3
    mov eax, r12d
    shr eax, 3
    cmp eax, edx
    jle .rook_next              ; veza musi byt VYSSSIE (vacsi rank) ako passer
    sub r15d, ROOK_BEHIND_PP
.rook_next:
    inc r12
    cmp r12, 64
    jl .rook_loop

    ; --- tempo bonus pre stranu na tahu ---
    lea rsi, [side]
    movzx eax, byte [rsi]
    test eax, eax
    jnz .tempo_b
    add r15d, TEMPO_BONUS
    jmp .tempo_done
.tempo_b:
    sub r15d, TEMPO_BONUS
.tempo_done:

    mov eax, r15d
.neg_done_early:
    pop rdi
    pop rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret
; ============================================================
; pst_init - naplni runtime PST tabulky zo zakladov * scale
; runtime[piece*64 + sq] = base[piece][sq] * scale[piece] / 64
; Volat raz na starte (pred prvym evaluate). Zachova r12/r13.
; ============================================================
global pst_init
pst_init:
    push r12
    push r13
    mov r12, 1              ; typ figury 1..6 (0 = empty, zostava 0)
.piece_loop:
    cmp r12, 6
    ja .done
    ; zdrojove pointery
    lea rax, [pst_base_ptrs_mg]
    mov rbx, [rax + r12*8]
    lea rax, [pst_base_ptrs_eg]
    mov rcx, [rax + r12*8]
    ; scale faktory
    lea rax, [pst_scale_mg]
    mov r8d, dword [rax + r12*4]
    lea rax, [pst_scale_eg]
    mov r9d, dword [rax + r12*4]
    ; cielove base offsety = piece*64 (own) a (piece+7)*64 (enemy)
    mov r10, r12
    shl r10, 6              ; piece*64
    lea rdi, [pst_runtime_mg]
    add rdi, r10            ; dst MG own
    lea rsi, [pst_runtime_eg]
    add rsi, r10            ; dst EG own
    mov r10, r12
    add r10, 7
    shl r10, 6              ; (piece+7)*64
    lea rdx, [pst_runtime_mg]
    add rdx, r10            ; dst MG enemy
    push rdx                ; [rsp] = mg enemy dst
    mov r10, r12
    add r10, 7
    shl r10, 6
    lea rdx, [pst_runtime_eg]
    add rdx, r10            ; dst EG enemy
    push rdx                ; [rsp] = eg enemy dst
    xor r13, r13
.sq_loop:
    cmp r13, 64
    jae .next_piece
    ; MG
    movsx eax, byte [rbx + r13]
    imul eax, r8d
    sar eax, 6
    mov [rdi + r13], al
    mov rdx, [rsp + 8]      ; mg enemy dst
    mov [rdx + r13], al
    ; EG
    movsx eax, byte [rcx + r13]
    imul eax, r9d
    sar eax, 6
    mov [rsi + r13], al
    mov rdx, [rsp]          ; eg enemy dst
    mov [rdx + r13], al
    inc r13
    jmp .sq_loop
.next_piece:
    pop rdx
    pop rdx
    inc r12
    jmp .piece_loop
.done:
    pop r13
    pop r12
    ret
