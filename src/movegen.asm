; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; movegen.asm - generator pseudo-legálnych tahov (E10/F3)
;
; Plne bitboard generovanie: ziadny mailbox scan, ziaden sync.
; Invariant F3: bb_pieces/bb_side/bb_occ je konzistentny s
; board[64] (udržiava apply_move/unmake_move inkrementalnou xor
; deltou, init/FEN cesty cez pos_bb_init).
;   - pesiaci: posuny/captury cez shift masky + rank/file masky
;   - jazdec/kral: lookup tabulky & ~own_occ
;   - slidery: magic bitboardy (bb_attacks_* s rdx=bb_occ)
; filter_legal_moves robi pure-bit apply/revert + attack query.
; ============================================================

%include "chess.inc"

DEFAULT REL

%define BB_RANK_1       0x00000000000000FF
%define BB_RANK_4       0x00000000FF000000
%define BB_RANK_5       0x000000FF00000000
%define BB_RANK_8       0xFF00000000000000
%define BB_NOT_FILE_A   0xFEFEFEFEFEFEFEFE
%define BB_NOT_FILE_H   0x7F7F7F7F7F7F7F7F

section .text

global generate_all_moves

extern board, side, castle, enpassant, move_list, move_count
extern filter_legal_moves
extern prof_movegen
extern bb_pieces, bb_side, bb_occ
extern bb_knight_attacks, bb_king_attacks
extern bb_attacks_bishop, bb_attacks_rook
extern promo_pieces

; ============================================================
; add_move - prida tah do move_list
; Vstup: r12 = from, r13 = to, r14 = flags
; ============================================================
add_move:
    push rax
    push rbx
    push rsi

    movzx rbx, word [move_count]
    cmp rbx, 255
    jge .done

    lea rsi, [move_list]
    mov rax, r12
    shl r13, 6
    or rax, r13
    mov r13, r14
    shl r13, 12
    or rax, r13
    mov [rsi + rbx*2], ax

    inc rbx
    mov [move_count], bx

.done:
    pop rsi
    pop rbx
    pop rax
    ret

; ============================================================
; bb_mask_own - rax = maska ~own_occ (vyluc vlastne figury)
; ============================================================
bb_mask_own:
    movzx eax, byte [side]
    lea rcx, [bb_side]
    mov rax, [rcx + rax*8]
    not rax
    ret

; ============================================================
; bb_emit_targets - prida vsetky tahy r12 -> bit v r15
; Nici r13, r14 (flags=0), r15; add_move nici r13 (bit z r15).
; ============================================================
bb_emit_targets:
    test r15, r15
    jz .done
    bsf r13, r15
    btr r15, r13
    xor r14d, r14d              ; FLAG_NORMAL
    call add_move
    jmp bb_emit_targets
.done:
    ret

; ============================================================
; bb_emit_pawn_shift - pesiacie tahy s pevnym smerom
; Vstup: r15 = cielova maska, r9b = delta (to - from), r14 = flags
; ============================================================
bb_emit_pawn_shift:
    test r15, r15
    jz .done
    bsf r13, r15
    btr r15, r13
    mov r12d, r13d
    sub r12d, r9d
    xor r14d, r14d              ; FLAG_NORMAL
    call add_move
    jmp bb_emit_pawn_shift
.done:
    ret

; ============================================================
; bb_emit_promos - 4x add_move (FLAGY 1-4) pre kazdy ciel v r15
; Vstup: r15 = cielova maska, r9b = delta (to - from)
; Ghost-promo disciplina: ciel v rbx, add_all_promotions je bezpecna.
; ============================================================
bb_emit_promos:
    test r15, r15
    jz .done
    bsf r13, r15
    btr r15, r13
    mov r12d, r13d
    sub r12d, r9d
    call add_all_promotions
    jmp bb_emit_promos
.done:
    ret

; ============================================================
; bb_generate_pawns - vygeneruje pseudo-legalne pesiakove tahy
; Vstup: r10d = own base slot (side*6), r11d = enemy base slot
; ============================================================
bb_generate_pawns:
    lea rdi, [bb_pieces]
    mov rbx, [rdi + r10*8]      ; vlastni pesiaci
    test rbx, rbx
    jz .done
    cmp byte [side], 0
    jne .pawns_black

    ; ----- biele pesiaci -----
    ; push1 = (pawns<<8) & ~occ ; push2 = (push1<<8) & rank4
    mov r15, rbx
    shl r15, 8
    mov rax, [bb_occ]
    not rax
    and r15, rax                ; push1 ciele
    mov rdx, r15
    shl rdx, 8
    mov rax, [bb_occ]
    not rax
    and rdx, rax
    mov rax, BB_RANK_4
    and rdx, rax                ; push2 ciele (intermediate aj ciel prazdne)
    mov rsi, r15
    mov rax, BB_RANK_8
    and rsi, rax                ; promo ciele (push1)
    not rax
    and r15, rax                ; normal push1
    mov r9d, 8
    call bb_emit_pawn_shift
    mov r15, rsi
    call bb_emit_promos
    mov r15, rdx
    mov r9d, 16
    call bb_emit_pawn_shift
    ; caps L: to = from+7, maska (p<<7)&~FILE_H
    mov r15, rbx
    shl r15, 7
    mov rax, BB_NOT_FILE_H
    and r15, rax
    lea rax, [bb_side]
    mov rdx, [rax + r11*8]
    and r15, rdx
    mov rsi, r15
    mov rax, BB_RANK_8
    and rsi, rax
    not rax
    and r15, rax
    mov r9d, 7
    call bb_emit_pawn_shift
    mov r15, rsi
    call bb_emit_promos
    ; caps R: to = from+9, maska (p<<9)&~FILE_A
    mov r15, rbx
    shl r15, 9
    mov rax, BB_NOT_FILE_A
    and r15, rax
    lea rax, [bb_side]
    mov rdx, [rax + r11*8]
    and r15, rdx
    mov rsi, r15
    mov rax, BB_RANK_8
    and rsi, rax
    not rax
    and r15, rax
    mov r9d, 9
    call bb_emit_pawn_shift
    mov r15, rsi
    call bb_emit_promos
    ; en passant: zdroje = ((ep>>7)&~FILE_A | (ep>>9)&~FILE_H) & pawns
    movzx eax, byte [enpassant]
    cmp eax, 255
    je .done
    mov ecx, eax
    mov rax, 1
    shl rax, cl                 ; epbit
    mov rdx, rax
    shr rdx, 7
    mov rcx, BB_NOT_FILE_A
    and rdx, rcx
    mov rcx, rax
    shr rcx, 9
    mov rsi, BB_NOT_FILE_H
    and rcx, rsi
    or rdx, rcx
    and rdx, rbx                ; zdrojove pesiaci
    mov r14d, FLAG_ENPASSANT
.ep_w_loop:
    test rdx, rdx
    jz .done
    bsf r12, rdx
    btr rdx, r12
    movzx r13d, byte [enpassant]
    call add_move
    jmp .ep_w_loop

    ; ----- cierne pesiaci -----
.pawns_black:
    ; push1 = (pawns>>8) & ~occ ; push2 = (push1>>8) & rank5
    mov r15, rbx
    shr r15, 8
    mov rax, [bb_occ]
    not rax
    and r15, rax
    mov rdx, r15
    shr rdx, 8
    mov rax, [bb_occ]
    not rax
    and rdx, rax
    mov rax, BB_RANK_5
    and rdx, rax                ; push2 ciele (intermediate aj ciel prazdne)
    mov rsi, r15
    mov rax, BB_RANK_1
    and rsi, rax
    not rax
    and r15, rax
    mov r9d, -8
    call bb_emit_pawn_shift
    mov r15, rsi
    call bb_emit_promos
    mov r15, rdx
    mov r9d, -16
    call bb_emit_pawn_shift
    ; caps: to = from-9, maska (p>>9)&~FILE_H
    mov r15, rbx
    shr r15, 9
    mov rax, BB_NOT_FILE_H
    and r15, rax
    lea rax, [bb_side]
    mov rdx, [rax + r11*8]
    and r15, rdx
    mov rsi, r15
    mov rax, BB_RANK_1
    and rsi, rax
    not rax
    and r15, rax
    mov r9d, -9
    call bb_emit_pawn_shift
    mov r15, rsi
    call bb_emit_promos
    ; caps: to = from-7, maska (p>>7)&~FILE_A
    mov r15, rbx
    shr r15, 7
    mov rax, BB_NOT_FILE_A
    and r15, rax
    lea rax, [bb_side]
    mov rdx, [rax + r11*8]
    and r15, rdx
    mov rsi, r15
    mov rax, BB_RANK_1
    and rsi, rax
    not rax
    and r15, rax
    mov r9d, -7
    call bb_emit_pawn_shift
    mov r15, rsi
    call bb_emit_promos
    ; en passant: zdroje = ((ep<<7)&~FILE_H | (ep<<9)&~FILE_A) & pawns
    movzx eax, byte [enpassant]
    cmp eax, 255
    je .done
    mov ecx, eax
    mov rax, 1
    shl rax, cl
    mov rdx, rax
    shl rdx, 7
    mov rcx, BB_NOT_FILE_H
    and rdx, rcx
    mov rcx, rax
    shl rcx, 9
    mov rsi, BB_NOT_FILE_A
    and rcx, rsi
    or rdx, rcx
    and rdx, rbx
    mov r14d, FLAG_ENPASSANT
.ep_b_loop:
    test rdx, rdx
    jz .done
    bsf r12, rdx
    btr rdx, r12
    movzx r13d, byte [enpassant]
    call add_move
    jmp .ep_b_loop

.done:
    ret

; ============================================================
; bb_generate_knights - vygeneruje pseudo-legalne tahy jazdcov
; Vstup: r10d = own base slot (side*6)
; ============================================================
bb_generate_knights:
    lea rdi, [bb_pieces]
    mov rbx, [rdi + r10*8 + 8]
.knight_loop:
    test rbx, rbx
    jz .done
    bsf r12, rbx
    btr rbx, r12
    lea rax, [bb_knight_attacks]
    mov r15, [rax + r12*8]
    call bb_mask_own
    and r15, rax
    call bb_emit_targets
    jmp .knight_loop

.done:
    ret

; ============================================================
; bb_generate_king - vygeneruje pseudo-legalne tahy krala
; Vstup: r10d = own base slot (side*6)
; Pozn.: rosada sa riesi samostatne v generate_castling.
; ============================================================
bb_generate_king:
    lea rdi, [bb_pieces]
    mov rbx, [rdi + r10*8 + 40]
    test rbx, rbx
    jz .done
    bsf r12, rbx
    lea rax, [bb_king_attacks]
    mov r15, [rax + r12*8]
    call bb_mask_own
    and r15, rax
    call bb_emit_targets
.done:
    ret

; ============================================================
; bb_generate_bishops - vygeneruje pseudo-legalne tahy strelcov
; Vstup: r10d = own base slot (side*6)
; ============================================================
bb_generate_bishops:
    lea rdi, [bb_pieces]
    mov rbx, [rdi + r10*8 + 16]
.bishop_loop:
    test rbx, rbx
    jz .done
    bsf r12, rbx
    btr rbx, r12
    mov eax, r12d
    mov rdx, [bb_occ]
    call bb_attacks_bishop
    mov r15, rax
    call bb_mask_own
    and r15, rax
    call bb_emit_targets
    jmp .bishop_loop

.done:
    ret

; ============================================================
; generate_all_moves - bitboard rychlostna cesta (F3)
; ============================================================
generate_all_moves:
    inc qword [prof_movegen]
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov word [move_count], 0
;   jmp .debug_ret          ; TEMP DEBUG

    movzx r10d, byte [side]
    mov r11d, r10d
    xor r11d, 1                 ; enemy side idx
    imul r10d, r10d, 6          ; vlastny base slot

    ; ================= PESIACI =================
    call bb_generate_pawns

    ; ================= JAZDCI =================
    call bb_generate_knights

    ; ================= STRELECI =================
.bishops:
;   jmp .debug_ret          ; TEMP DEBUG
    call bb_generate_bishops

    ; ================= VEZE =================
.rooks:
;   jmp .debug_ret          ; TEMP DEBUG
    lea rdi, [bb_pieces]
    mov rbx, [rdi + r10*8 + 24]
.rook_loop:
    test rbx, rbx
    jz .queens
    bsf r12, rbx
    btr rbx, r12
    mov eax, r12d
    mov rdx, [bb_occ]
    call bb_attacks_rook
    mov r15, rax
    call bb_mask_own
    and r15, rax
    call bb_emit_targets
    jmp .rook_loop

    ; ================= DAMY =================
.queens:
    lea rdi, [bb_pieces]
    mov rbx, [rdi + r10*8 + 32]
.queen_loop:
    test rbx, rbx
    jz .king
    bsf r12, rbx
    btr rbx, r12
    mov eax, r12d
    mov rdx, [bb_occ]
    call bb_attacks_bishop
    mov r15, rax
    mov eax, r12d
    mov rdx, [bb_occ]
    call bb_attacks_rook
    or r15, rax
    call bb_mask_own
    and r15, rax
    call bb_emit_targets
    jmp .queen_loop

    ; ================= KRAL + ROSADA =================
.king:
    call bb_generate_king
    call generate_castling
    call filter_legal_moves


    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================
; add_all_promotions - prida 4 promocne tahy z r12 -> r13
; POZOR: add_move nici r13, ciel treba pred kazdym call obnovit
; ============================================================
add_all_promotions:
    push rbx
    push r14
    mov rbx, r13                ; cielove policko
    mov r14, FLAG_PROMO_Q
    call add_move
    mov r13, rbx
    mov r14, FLAG_PROMO_R
    call add_move
    mov r13, rbx
    mov r14, FLAG_PROMO_B
    call add_move
    mov r13, rbx
    mov r14, FLAG_PROMO_N
    call add_move
    pop r14
    pop rbx
    ret

; ============================================================
; generate_castling - rosady (mailbox kontroly prazdnosti/veze,
; generuje sa max 2x na uzol; legality cez priechod robi filter)
; ============================================================
generate_castling:
    push rax
    push rbx
    push r12
    push r13
    push r14

    movzx rbx, byte [side]
    test rbx, rbx
    jnz .black

.white_k:
    test byte [castle], CASTLE_WK
    jz .white_q
    mov r12, 4
    mov r13, 6
    mov rax, 5
    call is_square_empty
    test rax, rax
    jz .white_q
    mov rax, 6
    call is_square_empty
    test rax, rax
    jz .white_q
    lea rdi, [board]
    movzx rax, byte [rdi + 7]
    cmp rax, ROOK|WHITE
    jne .white_q
    mov r14, FLAG_CASTLE
    call add_move

.white_q:
    test byte [castle], CASTLE_WQ
    jz .done
    mov r12, 4
    mov r13, 2
    mov rax, 3
    call is_square_empty
    test rax, rax
    jz .done
    mov rax, 2
    call is_square_empty
    test rax, rax
    jz .done
    mov rax, 1
    call is_square_empty
    test rax, rax
    jz .done
    lea rdi, [board]
    movzx rax, byte [rdi + 0]
    cmp rax, ROOK|WHITE
    jne .done
    mov r14, FLAG_CASTLE
    call add_move
    jmp .done

.black:
    test byte [castle], CASTLE_BK
    jz .black_q
    mov r12, 60
    mov r13, 62
    mov rax, 61
    call is_square_empty
    test rax, rax
    jz .black_q
    mov rax, 62
    call is_square_empty
    test rax, rax
    jz .black_q
    lea rdi, [board]
    movzx rax, byte [rdi + 63]
    cmp rax, ROOK|BLACK
    jne .black_q
    mov r14, FLAG_CASTLE
    call add_move

.black_q:
    test byte [castle], CASTLE_BQ
    jz .done
    mov r12, 60
    mov r13, 58
    mov rax, 59
    call is_square_empty
    test rax, rax
    jz .done
    mov rax, 58
    call is_square_empty
    test rax, rax
    jz .done
    mov rax, 57
    call is_square_empty
    test rax, rax
    jz .done
    lea rdi, [board]
    movzx rax, byte [rdi + 56]
    cmp rax, ROOK|BLACK
    jne .done
    mov r14, FLAG_CASTLE
    call add_move

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rax
    ret

; ============================================================
; is_square_empty - pomocnik pre generate_castling
; ============================================================
is_square_empty:
    lea rdi, [board]
    movzx rax, byte [rdi + rax]
    test rax, rax
    setz al
    movzx rax, al
    ret

section .bss
section .rodata

