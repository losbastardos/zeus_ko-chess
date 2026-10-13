; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; board.asm - sachovnica, inicializacia, tlac
; ============================================================

%include "chess.inc"

DEFAULT REL

section .data

board_sep:
    db "  +---+---+---+---+---+---+---+---+", 0

board_rank_bar:
    db " |", 0

board_cell_empty:
    db "   |", 0

board_cell_prefix:
    db " ", 0

board_cell_suffix:
    db " |", 0

board_piece_white:
    db 27,"[97m", 0

board_piece_black:
    db 27,"[91m", 0

board_color_reset:
    db 27,"[0m", 0

board_files_white:
    db "    a   b   c   d   e   f   g   h", 0

board_files_black:
    db "    h   g   f   e   d   c   b   a", 0

section .text

global init_board, update_position_state, print_board, toggle_board_view

extern board, side, castle, enpassant, halfmove, fullmove, board_flip
extern moved_piece, captured_piece
extern piece_chars, initial_board
extern compute_hash
extern pos_bb_init
extern pl_dirty
extern msg_files, msg_files_len, msg_files_rev, msg_files_rev_len, msg_newline
extern rank_char_buf, square_char_buf
extern print_newline, print_panel_line
extern write_cstr

; ============================================================
; print_piece_cell - vypise jedno policko ako | X |
; Vstup: rcx = piece byte
; ============================================================
print_piece_cell:
    push rax
    push rcx
    push rdx
    push rdi
    push r8

    test rcx, rcx
    jnz .piece
    lea rdi, [board_cell_empty]
    call write_cstr
    jmp .done

.piece:
    mov rdx, rcx
    and rdx, COLOR_MASK
    mov r8, rcx
    and r8, PIECE_MASK
    add r8, rdx
    lea rdi, [piece_chars]
    movzx rax, byte [rdi + r8]
    mov [square_char_buf], al
    mov byte [square_char_buf + 1], 0

    lea rdi, [board_cell_prefix]
    call write_cstr

    test rdx, rdx
    jnz .black_piece
    lea rdi, [board_piece_white]
    call write_cstr
    jmp .print_piece

.black_piece:
    lea rdi, [board_piece_black]
    call write_cstr

.print_piece:
    lea rdi, [square_char_buf]
    call write_cstr
    lea rdi, [board_color_reset]
    call write_cstr
    lea rdi, [board_cell_suffix]
    call write_cstr

.done:
    pop r8
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; ============================================================
; init_board - nacita pociatocnu poziciu
; ============================================================
init_board:
    mov rsi, initial_board
    mov rdi, board
    mov rcx, 64
    rep movsb
    mov byte [side], 0
    mov byte [castle], 0x0F
    mov byte [enpassant], 255
    mov byte [halfmove], 0
    mov word [fullmove], 1
    mov byte [board_flip], 0
    mov byte [pl_dirty], 1
    call pos_bb_init               ; E10/F1: bb stav konzistentny s board
    call compute_hash
    ret

; ============================================================
; toggle_board_view - prepne orientaciu vypisu sachovnice
; 0 = biely dole, 1 = cierny dole
; ============================================================
toggle_board_view:
    xor byte [board_flip], 1
    ret

; ============================================================
; update_position_state - aktualizuje enpassant, rosadu, halfmove, fullmove
; Vstup: ax = 16-bitovy tah (zachovany po apply_move)
; Pozn.: side este obsahuje hraca, ktory hybal; na konci sa vymeni.
; ============================================================
update_position_state:
    push rax
    push rbx
    push rcx
    push rdx
    push r12
    push r13
    push r14

    movzx r12, ax
    and r12, 0x3F           ; from
    movzx r13, ax
    shr r13, 6
    and r13, 0x3F           ; to
    movzx r14, ax
    shr r14, 12             ; flags

    movzx rdx, byte [side]  ; hrac, ktory prave urobil tah

    ; --- en passant ---
    movzx rcx, byte [moved_piece]
    and rcx, PIECE_MASK
    cmp rcx, PAWN
    jne .no_ep
    mov rbx, r13
    sub rbx, r12            ; rozdiel to - from
    test rdx, rdx
    jnz .black_pawn
    cmp rbx, 16
    jne .no_ep
    mov rbx, r12
    add rbx, 8              ; prechodne policko
    mov [enpassant], bl
    jmp .ep_done
.black_pawn:
    cmp rbx, -16
    jne .no_ep
    mov rbx, r12
    sub rbx, 8
    mov [enpassant], bl
    jmp .ep_done
.no_ep:
    mov byte [enpassant], 255
.ep_done:

    ; --- prava rosady ---
    ; biely kral hybal z e1
    cmp rdx, 0
    jne .black_castle
    cmp r12, 4
    jne .check_white_rook
    movzx rcx, byte [moved_piece]
    and rcx, PIECE_MASK
    cmp rcx, KING
    jne .check_white_rook
    and byte [castle], ~(CASTLE_WK | CASTLE_WQ)
    jmp .castle_done
.check_white_rook:
    cmp r12, 0
    jne .check_wh_rook
    and byte [castle], ~CASTLE_WQ
.check_wh_rook:
    cmp r12, 7
    jne .check_white_capture
    and byte [castle], ~CASTLE_WK
.check_white_capture:
    movzx rcx, byte [captured_piece]
    test rcx, rcx
    jz .castle_done
    and rcx, PIECE_MASK
    cmp rcx, ROOK
    jne .castle_done
    cmp r13, 0
    jne .check_wh_cap
    and byte [castle], ~CASTLE_WQ
.check_wh_cap:
    cmp r13, 7
    jne .castle_done
    and byte [castle], ~CASTLE_WK
    jmp .castle_done

.black_castle:
    ; cierny kral hybal z e8
    cmp r12, 60
    jne .check_black_rook
    movzx rcx, byte [moved_piece]
    and rcx, PIECE_MASK
    cmp rcx, KING
    jne .check_black_rook
    and byte [castle], ~(CASTLE_BK | CASTLE_BQ)
    jmp .castle_done
.check_black_rook:
    cmp r12, 56
    jne .check_bh_rook
    and byte [castle], ~CASTLE_BQ
.check_bh_rook:
    cmp r12, 63
    jne .check_black_capture
    and byte [castle], ~CASTLE_BK
.check_black_capture:
    movzx rcx, byte [captured_piece]
    test rcx, rcx
    jz .castle_done
    and rcx, PIECE_MASK
    cmp rcx, ROOK
    jne .castle_done
    cmp r13, 56
    jne .check_bh_cap
    and byte [castle], ~CASTLE_BQ
.check_bh_cap:
    cmp r13, 63
    jne .castle_done
    and byte [castle], ~CASTLE_BK

.castle_done:

    ; --- 50-tahove pravidlo ---
    movzx rcx, byte [moved_piece]
    and rcx, PIECE_MASK
    cmp rcx, PAWN
    je .reset_halfmove
    movzx rcx, byte [captured_piece]
    test rcx, rcx
    jz .inc_halfmove
.reset_halfmove:
    mov byte [halfmove], 0
    jmp .halfmove_done
.inc_halfmove:
    inc byte [halfmove]
.halfmove_done:

    ; --- vymena strany a fullmove ---
    xor byte [side], 1
    cmp byte [side], 0
    jne .skip_fullmove
    inc word [fullmove]
.skip_fullmove:

    pop r14
    pop r13
    pop r12
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================
; print_board - vypise sachovnicu
; ============================================================
print_board:
    push rbx
    push r12
    push r13

    call print_newline
    xor r13, r13

    cmp byte [board_flip], 0
    jne .black_view

    ; --- standardny pohlad: biely dole ---
    mov r12, 7
.rank_loop_white:
    lea rdi, [board_sep]
    call write_cstr
    mov rdi, r13
    call print_panel_line
    inc r13
    call print_newline

    lea rsi, [rank_char_buf]
    mov al, '1'
    add al, r12b
    mov [rsi], al
    mov byte [rsi+1], 0
    lea rdi, [rank_char_buf]
    call write_cstr
    lea rdi, [board_rank_bar]
    call write_cstr

    mov rbx, 0
.file_loop_white:
    mov rax, r12
    shl rax, 3
    add rax, rbx
    lea rdi, [board]
    movzx rcx, byte [rdi + rax]

    call print_piece_cell

    inc rbx
    cmp rbx, 8
    jl .file_loop_white

    mov rdi, r13
    call print_panel_line
    inc r13
    call print_newline

    dec r12
    jns .rank_loop_white

    lea rdi, [board_sep]
    call write_cstr
    mov rdi, r13
    call print_panel_line
    call print_newline
    lea rdi, [board_files_white]
    call write_cstr
    jmp .board_done

.black_view:
    ; --- prevrateny pohlad: cierny dole ---
    xor r12, r12
.rank_loop_black:
    lea rdi, [board_sep]
    call write_cstr
    mov rdi, r13
    call print_panel_line
    inc r13
    call print_newline

    lea rsi, [rank_char_buf]
    mov al, '1'
    add al, r12b
    mov [rsi], al
    mov byte [rsi+1], 0
    lea rdi, [rank_char_buf]
    call write_cstr
    lea rdi, [board_rank_bar]
    call write_cstr

    mov rbx, 7
.file_loop_black:
    mov rax, r12
    shl rax, 3
    add rax, rbx
    lea rdi, [board]
    movzx rcx, byte [rdi + rax]

    call print_piece_cell

    dec rbx
    jns .file_loop_black

    mov rdi, r13
    call print_panel_line
    inc r13
    call print_newline

    inc r12
    cmp r12, 8
    jl .rank_loop_black

    lea rdi, [board_sep]
    call write_cstr
    mov rdi, r13
    call print_panel_line
    call print_newline
    lea rdi, [board_files_black]
    call write_cstr

.board_done:
    call print_newline

    pop r13
    pop r12
    pop rbx
    ret