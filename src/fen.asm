; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; fen.asm - parser FEN reťazca
; ============================================================

%include "chess.inc"

DEFAULT REL

section .text

global parse_fen_string

extern board, side, castle, enpassant, halfmove, fullmove
extern piece_chars
extern compute_hash, init_hash_history, record_hash
extern parse_int
extern pos_sync_from_board
extern pl_dirty
extern print_number

section .rodata
fen_err_rank_prefix: db "info string ERROR invalid FEN rank ", 0
fen_err_rank_suffix: db ": expected 8 squares", 10, 0

section .text

; ============================================================
; fen_write_cstr - vypise null-terminated retazec na stdout
; Vstup: rdi = ukazatel na retazec
; ============================================================
fen_write_cstr:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rbx, rdi
    xor rcx, rcx
.len_loop:
    cmp byte [rbx + rcx], 0
    je .write
    inc rcx
    jmp .len_loop

.write:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, rbx
    mov rdx, rcx
    syscall

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================
; fen_report_rank_error - vypise chybu neplatneho ranku FEN
; Vstup: rax = cislo ranku (1..8)
; ============================================================
fen_report_rank_error:
    push rax

    lea rdi, [rel fen_err_rank_prefix]
    call fen_write_cstr

    pop rax
    call print_number

    lea rdi, [rel fen_err_rank_suffix]
    call fen_write_cstr
    ret

; ============================================================
; fen_piece_char_to_byte - prevedie znak FEN figúrky na bajt
; Vstup: al = znak (p,n,b,r,q,k,P,N,B,R,Q,K)
; Vystup: rax = hodnota figúrky, 0 ak neznámy
; ============================================================
fen_piece_char_to_byte:
    push rbx
    push rcx
    movzx rax, al
    lea rbx, [piece_chars]
    xor rcx, rcx
.loop:
    cmp rcx, 16
    jge .not_found
    movzx rdx, byte [rbx + rcx]
    cmp rdx, rax
    je .found
    inc rcx
    jmp .loop
.found:
    mov rax, rcx
    jmp .done
.not_found:
    xor rax, rax
.done:
    pop rcx
    pop rbx
    ret

; ============================================================
; parse_fen_board - naplní board[64] z prvej časti FEN
; Vstup: rdi = ukazateľ na board field reťazec
; Vystup: rax = 0 OK, 1 chyba; pri chybe rdx = cislo ranku (1..8)
; ============================================================
parse_fen_board:
    push rbx
    push rcx
    push rsi
    push rdi

    ; vynuluj board
    lea rdi, [board]
    xor rax, rax
    mov rcx, 64
    rep stosb

    ; rank_index = 7 (rank 8), file = 0
    mov rbx, 7
    xor rcx, rcx
    pop rdi                     ; obnov ukazateľ na FEN board string

.loop:
    movzx rax, byte [rdi]
    test rax, rax
    jz .end_board
    cmp rax, ' '
    je .end_board
    cmp rax, '/'
    je .next_rank

    cmp rax, '1'
    jb .piece
    cmp rax, '8'
    ja .piece
    ; prázdne políčka
    sub rax, '0'
    add rcx, rax
    cmp rcx, 8
    ja .error_rank
    jmp .next_char

.piece:
    call fen_piece_char_to_byte
    test rax, rax
    jz .error
    cmp rcx, 8
    jae .error_rank
    mov rdx, rbx
    shl rdx, 3
    add rdx, rcx
    cmp rdx, 64
    jae .error
    lea rsi, [board]
    mov [rsi + rdx], al
    inc rcx

.next_char:
    inc rdi
    jmp .loop

.next_rank:
    cmp rcx, 8
    jne .error_rank
    cmp rbx, 0
    jle .error
    dec rbx
    xor rcx, rcx
    inc rdi
    jmp .loop

.end_board:
    cmp rcx, 8
    jne .error_rank
    cmp rbx, 0
    jne .error_rank
    xor rax, rax
    jmp .done

.error_rank:
    mov rdx, rbx
    inc rdx
    mov rax, 1
    jmp .done

.error:
    mov rdx, rbx
    inc rdx
    mov rax, 1

.done:
    pop rsi
    pop rcx
    pop rbx
    ret

; ============================================================
; fen_skip_ws - preskočí whitespace
; Vstup/Vystup: rdi = ukazateľ na aktuálnu pozíciu v reťazci
; ============================================================
fen_skip_ws:
.loop:
    movzx rax, byte [rdi]
    test rax, rax
    jz .done
    cmp rax, ' '
    je .next
    cmp rax, 9
    je .next
    cmp rax, 10
    je .next
    cmp rax, 13
    je .next
    jmp .done
.next:
    inc rdi
    jmp .loop
.done:
    ret

; ============================================================
; fen_next_token - vráti ukazateľ na ďalší token a posunie rdi zaň
; Vstup: rdi = ukazateľ na FEN reťazec (môže začínať whitespace)
; Vystup: rax = ukazateľ na začiatok tokenu, rdi = za tokenom
; ============================================================
fen_next_token:
    push rbx
    call fen_skip_ws
    mov rax, rdi
.token_loop:
    movzx rbx, byte [rdi]
    test rbx, rbx
    jz .done
    cmp rbx, ' '
    je .done
    cmp rbx, 9
    je .done
    cmp rbx, 10
    je .done
    cmp rbx, 13
    je .done
    inc rdi
    jmp .token_loop
.done:
    pop rbx
    ret

; ============================================================
; parse_fen_string - hlavný FEN parser
; Vstup: rdi = ukazateľ na null-terminated FEN reťazec
; Vystup: rax = 0 OK, 1 chyba
; ============================================================
parse_fen_string:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r15, rdi

    ; board field
    call fen_next_token
    mov rdi, rax
    call parse_fen_board
    test rax, rax
    jnz .board_error
    mov r15, rdi              ; uloz poziciu za board token

    ; side
    mov rdi, r15
    call fen_next_token
    mov r15, rdi              ; pozicia za tokenom (rdi prepiseme na citanie)
    mov rdi, rax
    movzx rbx, byte [rdi]
    cmp rbx, 'w'
    je .white
    cmp rbx, 'b'
    je .black
    jmp .error
.white:
    mov byte [side], 0
    jmp .side_done
.black:
    mov byte [side], 1
.side_done:

    ; castle rights
    mov rdi, r15
    call fen_next_token
    mov rdi, rax
    movzx rbx, byte [rdi]
    cmp rbx, '-'
    je .no_castle

    mov byte [castle], 0
.castle_loop:
    movzx rbx, byte [rdi]
    test rbx, rbx
    jz .castle_done
    cmp rbx, ' '
    jle .castle_done
    cmp rbx, 'K'
    jne .check_q
    or byte [castle], CASTLE_WK
.check_q:
    cmp rbx, 'Q'
    jne .check_k
    or byte [castle], CASTLE_WQ
.check_k:
    cmp rbx, 'k'
    jne .check_q2
    or byte [castle], CASTLE_BK
.check_q2:
    cmp rbx, 'q'
    jne .castle_next
    or byte [castle], CASTLE_BQ
.castle_next:
    inc rdi
    jmp .castle_loop

.no_castle:
    mov byte [castle], 0
    inc rdi                     ; preskoc '-' token (inak by ho zral ep parser)
.castle_done:
    mov r15, rdi

    ; en passant
    mov rdi, r15
    call fen_next_token
    mov r15, rdi              ; pozicia za ep tokenom (rdi prepiseme na citanie)
    mov rdi, rax
    movzx rbx, byte [rdi]
    cmp rbx, '-'
    je .no_ep
    ; parse square: file a-h, rank 1-8
    movzx rax, byte [rdi]
    sub rax, 'a'
    cmp rax, 7
    ja .error
    mov r12, rax            ; file
    movzx rax, byte [rdi + 1]
    sub rax, '1'
    cmp rax, 7
    ja .error
    shl rax, 3
    add rax, r12
    mov [enpassant], al
    jmp .ep_done
.no_ep:
    mov byte [enpassant], 255
.ep_done:

    ; halfmove clock
    mov rdi, r15
    call fen_next_token
    mov rsi, rax
    call parse_int
    mov [halfmove], al
    mov r15, rdi

    ; fullmove number
    mov rdi, r15
    call fen_next_token
    mov rsi, rax
    call parse_int
    mov [fullmove], ax

    ; hash & history
    call pos_sync_from_board       ; M1: jednotny full sync entrypoint
    call compute_hash
    call init_hash_history
    call record_hash
    mov byte [pl_dirty], 1

    xor rax, rax
    jmp .done

.board_error:
    mov rax, rdx
    call fen_report_rank_error
    jmp .error

.error:
    mov rax, 1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret