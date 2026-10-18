; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; move.asm - reprezentacia a aplikacia tahov
; ============================================================

%include "chess.inc"

DEFAULT REL

section .text

global parse_user_move, find_move, apply_move

extern board, side, move_buf, move_list, move_count
extern promo_pieces, moved_piece, captured_piece
extern pos_sync_move_delta
extern pl_dirty

; ============================================================
; parse_user_move - prevedie move_buf[0..3] na from | (to << 6)
; ============================================================
parse_user_move:
    push rbx

    movzx rax, byte [move_buf+0]
    sub rax, 'a'
    movzx rbx, byte [move_buf+1]
    sub rbx, '1'
    shl rbx, 3
    add rax, rbx
    mov r12, rax

    movzx rax, byte [move_buf+2]
    sub rax, 'a'
    movzx rbx, byte [move_buf+3]
    sub rbx, '1'
    shl rbx, 3
    add rax, rbx
    mov r13, rax

    mov rax, r12
    shl r13, 6
    or rax, r13

    pop rbx
    ret

; ============================================================
; find_move - najde tah v move_list podla from/to
; Vstup: rax = from | (to << 6)
; Vystup: rax = najdeny 16-bitovy tah, alebo 0
; ============================================================
find_move:
    push rbx
    push rcx
    push rdx
    push rsi

    mov rbx, rax
    xor rcx, rcx
    movzx rdx, word [move_count]
    test rdx, rdx
    jz .not_found

    lea rsi, [move_list]
.loop:
    movzx rax, word [rsi + rcx*2]
    mov r8, rax
    and r8, 0x0FFF
    cmp r8, rbx
    je .found

    inc rcx
    cmp rcx, rdx
    jl .loop

.not_found:
    xor rax, rax
.found:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; apply_move - aplikuje 16-bitovy tah z ax
; Ulozi moved_piece a captured_piece pre update_position_state
; ============================================================
apply_move:
    push rax
    push rbx
    push rcx
    push rdx
    push r12
    push r13
    push r14
    push rsi

    mov byte [pl_dirty], 1

    movzx rbx, ax
    and rbx, 0x3F
    mov r12, rbx            ; from

    movzx rbx, ax
    shr rbx, 6
    and rbx, 0x3F
    mov r13, rbx            ; to

    movzx rbx, ax
    shr rbx, 12
    mov r14, rbx            ; flags

    lea rsi, [board]
    movzx rcx, byte [rsi + r12]
    mov [moved_piece], cl   ; uloz hybanu figurku

    ; uloz branu figurku
    cmp r14, FLAG_ENPASSANT
    je .capture_ep
    cmp r14, FLAG_CASTLE
    je .no_capture

    ; normal / promotion
    movzx rbx, byte [rsi + r13]
    mov [captured_piece], bl
    jmp .apply

.capture_ep:
    movzx rbx, byte [side]
    shl rbx, 3
    xor rbx, BLACK          ; farba protivnika
    or rbx, PAWN
    mov [captured_piece], bl
    jmp .apply

.no_capture:
    mov byte [captured_piece], EMPTY

.apply:
    cmp r14, FLAG_ENPASSANT
    je .enpassant
    cmp r14, FLAG_CASTLE
    je .castle
    cmp r14, FLAG_PROMO_Q
    je .promote
    cmp r14, FLAG_PROMO_R
    je .promote
    cmp r14, FLAG_PROMO_B
    je .promote
    cmp r14, FLAG_PROMO_N
    je .promote

    ; normalny tah
    mov [rsi + r13], cl
    mov byte [rsi + r12], EMPTY
    jmp .done

.promote:
    lea rdi, [promo_pieces]
    movzx rbx, byte [rdi + r14]
    movzx rax, byte [side]
    shl rax, 3
    or rbx, rax
    mov [rsi + r13], bl
    mov byte [rsi + r12], EMPTY
    jmp .done

.enpassant:
    mov [rsi + r13], cl
    mov byte [rsi + r12], EMPTY
    mov rbx, r13
    cmp byte [side], 0
    je .white_ep
    add rbx, 8              ; cierny bral pesiaca na to + 8
    jmp .do_ep
.white_ep:
    sub rbx, 8              ; biely bral pesiaca na to - 8
.do_ep:
    mov byte [rsi + rbx], EMPTY
    jmp .done

.castle:
    mov [rsi + r13], cl
    mov byte [rsi + r12], EMPTY
    cmp r13, 6
    je .castle_wk
    cmp r13, 2
    je .castle_wq
    cmp r13, 62
    je .castle_bk
    cmp r13, 58
    je .castle_bq
    jmp .done

.castle_wk:
    movzx rax, byte [rsi + 7]
    mov byte [rsi + 5], al
    mov byte [rsi + 7], EMPTY
    jmp .done
.castle_wq:
    movzx rax, byte [rsi + 0]
    mov byte [rsi + 3], al
    mov byte [rsi + 0], EMPTY
    jmp .done
.castle_bk:
    movzx rax, byte [rsi + 63]
    mov byte [rsi + 61], al
    mov byte [rsi + 63], EMPTY
    jmp .done
.castle_bq:
    movzx rax, byte [rsi + 56]
    mov byte [rsi + 59], al
    mov byte [rsi + 56], EMPTY

.done:
    ; E10/F3 invariant: bb stav konzistentny s board[64] cez inkrementalnu
    ; xor delta (namiesto plneho pos_bb_init re-syncu)
    mov eax, r12d           ; from
    mov ecx, r13d
    shl ecx, 6
    or eax, ecx
    mov ecx, r14d
    shl ecx, 12
    or eax, ecx             ; 16-bitovy tah
    movzx esi, byte [moved_piece]
    movzx edi, byte [captured_piece]
    call pos_sync_move_delta
    pop rsi
    pop r14
    pop r13
    pop r12
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret