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

; --- unicode rezim: poloblok '▀' + ANSI truecolor ---
board_uni_halfblock:
    db 0xE2, 0x96, 0x80, 0          ; '▀' (UTF-8)
board_uni_reset:
    db 27, "[0m", 0
board_uni_spaces16:
    db "                ", 0         ; 16 medzier (prazdne policko)
board_uni_spaces15:
    db "               ", 0          ; 15 medzier (pod popisky stlpcov)
board_uni_ranksp:
    db " ", 0
board_uni_rankpad:
    db "  ", 0

section .text

global init_board, update_position_state, update_position_state_search, print_board, toggle_board_view

extern board, side, castle, enpassant, halfmove, fullmove, board_flip
extern moved_piece, captured_piece
extern piece_chars, initial_board
extern compute_hash
extern pos_sync_from_board
extern pos_piece_at_sq_bb
extern pl_dirty
extern msg_files, msg_files_len, msg_files_rev, msg_files_rev_len, msg_newline
extern rank_char_buf, square_char_buf
extern print_newline, print_panel_line
extern write_cstr
extern unicode_pieces, light_col, dark_col
extern piece_bitmaps

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
    call pos_sync_from_board       ; M1: jednotny full sync entrypoint
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
    jmp update_position_state_impl

; ============================================================
; update_position_state_search - search varianta (M3 hot-path)
; Podpis identicky, oddelenie call-path od UI/CLI cesty.
; ============================================================
update_position_state_search:
    jmp update_position_state_impl

update_position_state_impl:
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
    cmp byte [unicode_pieces], 0
    jne print_board_unicode
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
    call pos_piece_at_sq_bb
    movzx rcx, al

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
    call pos_piece_at_sq_bb
    movzx rcx, al

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
; ============================================================
; uni_put_dec - zapise 1-3 cifry cisla 0..255 na rdi (dopredu)
; Vstup: eax = hodnota, rdi = dst; Vystup: rdi posunuty za cifry
; ============================================================
uni_put_dec:
    push r8
    push r9
    push rdx
    mov r9d, eax
    cmp r9d, 100
    jb .two
    mov eax, r9d
    xor edx, edx
    mov r8d, 100
    div r8d                         ; eax = stovky, edx = zvysok
    add al, '0'
    mov [rdi], al
    inc rdi
    mov eax, edx
    jmp .last2
.two:
    cmp r9d, 10
    jb .one
    mov eax, r9d
    xor edx, edx
    mov r8d, 10
    div r8d                         ; eax = desiatky, edx = jednotky
    add al, '0'
    mov [rdi], al
    inc rdi
    mov eax, edx
    jmp .final
.one:
    mov eax, r9d
.final:
    add al, '0'
    mov [rdi], al
    inc rdi
    jmp .done
.last2:
    xor edx, edx
    mov r8d, 10
    div r8d
    add al, '0'
    mov [rdi], al
    inc rdi
    mov eax, edx
    jmp .final
.done:
    pop rdx
    pop r9
    pop r8
    ret

; ============================================================
; uni_print_color_seq - vypise ESC[38;2;R;G;Bm (fg) alebo ESC[48;2;R;G;Bm (bg)
; Vstup: esi = farba 0xRRGGBB, cl = 0 -> fg (38), 1 -> bg (48)
; ============================================================
uni_print_color_seq:
    sub rsp, 32
    mov byte [rsp+0], 27            ; ESC
    mov byte [rsp+1], '['
    mov byte [rsp+2], '3'
    mov byte [rsp+3], '8'
    test cl, cl
    jz .pfx
    mov byte [rsp+2], '4'           ; bg: 48
.pfx:
    mov byte [rsp+4], ';'
    mov byte [rsp+5], '2'
    mov byte [rsp+6], ';'
    lea rdi, [rsp+7]
    mov eax, esi
    shr eax, 16                     ; R
    and eax, 0xFF
    call uni_put_dec
    mov byte [rdi], ';'
    inc rdi
    mov eax, esi
    shr eax, 8                      ; G
    and eax, 0xFF
    call uni_put_dec
    mov byte [rdi], ';'
    inc rdi
    mov eax, esi                    ; B
    and eax, 0xFF
    call uni_put_dec
    mov byte [rdi], 'm'
    inc rdi
    mov rdx, rdi
    sub rdx, rsp                    ; dlzka sekvencie
    mov rsi, rsp
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall
    add rsp, 32
    ret

; ============================================================
; uni_print_cell_row - vypise jeden textovy riadok policka
; (2 vertikalne pixel rady cez jeden riadok '▀' znakov)
; Vstup: rdi = piece (0 = prazdne), esi = farba policka 0xRRGGBB,
;        edx = pixel-riadkovy par 0..7
; ============================================================
uni_print_cell_row:
    push rbx
    push r12
    push r13
    push r14
    push r15
    test rdi, rdi
    jnz .piece
    ; prazdne policko: bg farba + 16 medzier (bez fg sekvencie)
    mov cl, 1
    call uni_print_color_seq
    lea rdi, [board_uni_spaces16]
    call write_cstr
    jmp .done

.piece:
    mov r13d, esi                   ; r13 = farba policka
    mov eax, 0x00F0F0F0             ; biela figurka
    mov r10d, edi
    and r10d, COLOR_MASK
    jz .wcol
    mov eax, 0x00202020             ; cierna figurka
.wcol:
    mov r14d, eax                   ; r14 = farba figurky
    ; offset bitmapy: maska je farbovo neutralna -> len typ figurky
    mov eax, edi
    and eax, PIECE_MASK
    dec eax
    shl eax, 5
    lea r10, [piece_bitmaps]
    add r10, rax
    mov r11d, edx
    shl r11d, 2                     ; 2 pixely/riadok * 2 bajty/riadok = 4 bajty na par
    movzx r12d, byte [r10 + r11]    ; horny riadok, byte 0 (x 0-7)
    shl r12d, 8
    movzx eax, byte [r10 + r11 + 1] ; horny riadok, byte 1 (x 8-15)
    or r12d, eax
    movzx ebx, byte [r10 + r11 + 2] ; dolny riadok, byte 0
    shl ebx, 8
    movzx eax, byte [r10 + r11 + 3] ; dolny riadok, byte 1
    or ebx, eax
    mov r15d, 16                    ; pocet stlpcov
    mov r10d, -1                    ; predchadzajuci stav (bit1=horny px, bit0=dolny px)
.col_loop:
    xor eax, eax
    test r12d, 0x8000
    jz .no_top
    or eax, 2
.no_top:
    test ebx, 0x8000
    jz .no_bot
    or eax, 1
.no_bot:
    shl r12d, 1
    shl ebx, 1
    cmp eax, r10d
    je .print_hb
    mov r10d, eax
    ; stav -> (fg, bg): 0=(sq,sq) 1=(sq,pc) 2=(pc,sq) 3=(pc,pc)
    cmp eax, 2
    jb .st_low
    je .st2
    mov esi, r14d
    mov cl, 0
    call uni_print_color_seq
    mov esi, r14d
    mov cl, 1
    call uni_print_color_seq
    jmp .print_hb
.st_low:
    test eax, eax
    jz .st0
    mov esi, r13d                   ; stav 1: fg=sq, bg=pc
    mov cl, 0
    call uni_print_color_seq
    mov esi, r14d
    mov cl, 1
    call uni_print_color_seq
    jmp .print_hb
.st0:
    mov esi, r13d
    mov cl, 0
    call uni_print_color_seq
    mov esi, r13d
    mov cl, 1
    call uni_print_color_seq
    jmp .print_hb
.st2:
    mov esi, r14d                   ; stav 2: fg=pc, bg=sq
    mov cl, 0
    call uni_print_color_seq
    mov esi, r13d
    mov cl, 1
    call uni_print_color_seq
.print_hb:
    lea rdi, [board_uni_halfblock]
    call write_cstr
    dec r15d
    jnz .col_loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; print_board_unicode - sachovnica 8x8 policok x 16x16 px cez '▀'
; Kazdy textovy riadok nesie 2 vertikalne pixely (fg=hore, bg=dole).
; Podporuje board_flip (cierny pohlad). Panel sa netlaci (riadky su 130 znakov).
; ============================================================
print_board_unicode:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call print_newline
    call .print_file_letters
    call print_newline

    xor r12, r12                    ; display riadok dosky 0..7 (0 = hore)
.rank_loop:
    mov rax, 7
    sub rax, r12
    cmp byte [board_flip], 0
    je .rank_ok
    mov rax, r12
.rank_ok:
    mov r13, rax                    ; r13 = realny rank 0..7
    xor r14, r14                    ; r14 = pixel-riadkovy par 0..7
.row_loop:
    cmp r14, 4
    jne .no_ranknum
    mov eax, r13d
    add eax, '1'
    mov [rank_char_buf], al
    mov byte [rank_char_buf+1], 0
    lea rdi, [rank_char_buf]
    call write_cstr
    lea rdi, [board_uni_ranksp]
    call write_cstr
    jmp .num_done
.no_ranknum:
    lea rdi, [board_uni_rankpad]
    call write_cstr
.num_done:
    xor rbx, rbx                    ; display stlpec 0..7
.cell_loop:
    mov rax, rbx
    cmp byte [board_flip], 0
    je .file_ok
    mov rax, 7
    sub rax, rbx
.file_ok:
    mov r15, rax                    ; r15 = realny file 0..7
    mov rax, r13
    shl rax, 3
    add rax, r15
    call pos_piece_at_sq_bb
    mov rdi, rax                    ; piece byte
    mov eax, r13d
    add eax, r15d
    and eax, 1
    jz .dark_sq                     ; (rank+file) parny = tmave policko
    mov esi, [light_col]
    jmp .sq_ok
.dark_sq:
    mov esi, [dark_col]
.sq_ok:
    mov edx, r14d
    call uni_print_cell_row
    inc rbx
    cmp rbx, 8
    jl .cell_loop
    lea rdi, [board_uni_reset]
    call write_cstr
    call print_newline
    inc r14
    cmp r14, 8
    jl .row_loop
    call print_newline              ; oddelenie jednotlivych rankov
    inc r12
    cmp r12, 8
    jl .rank_loop
    call .print_file_letters
    call print_newline
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.print_file_letters:
    push rbx
    lea rdi, [board_uni_rankpad]
    call write_cstr
    xor rbx, rbx
.fl_loop:
    mov rax, rbx
    cmp byte [board_flip], 0
    je .fl_ok
    mov rax, 7
    sub rax, rbx
.fl_ok:
    add eax, 'a'
    mov [square_char_buf], al
    mov byte [square_char_buf+1], 0
    lea rdi, [square_char_buf]
    call write_cstr
    lea rdi, [board_uni_spaces15]
    call write_cstr
    inc rbx
    cmp rbx, 8
    jl .fl_loop
    pop rbx
    ret
