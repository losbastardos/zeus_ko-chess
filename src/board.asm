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
board_uni_ranksp:
    db " ", 0
board_uni_rankpad:
    db "  ", 0

; sachove glyfy (UTF-8: E2 99 xx), poradie wP,wN,wB,wR,wQ,wK,bP..bK
; biele su outline (U+2654-59), cierne filled (U+265A-5F)
board_glyphs:
    db 0xE2,0x99,0x99,0          ; wP ♙
    db 0xE2,0x99,0x98,0          ; wN ♘
    db 0xE2,0x99,0x97,0          ; wB ♗
    db 0xE2,0x99,0x96,0          ; wR ♖
    db 0xE2,0x99,0x95,0          ; wQ ♕
    db 0xE2,0x99,0x94,0          ; wK ♔
    db 0xE2,0x99,0x9F,0          ; bP ♟
    db 0xE2,0x99,0x9E,0          ; bN ♞
    db 0xE2,0x99,0x9D,0          ; bB ♝
    db 0xE2,0x99,0x9C,0          ; bR ♜
    db 0xE2,0x99,0x9B,0          ; bQ ♛
    db 0xE2,0x99,0x9A,0          ; bK ♚

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
extern piece_bitmaps, piece_bitmaps_8

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
    je .ascii
    cmp byte [unicode_pieces], 3
    je print_board_glyphs
    jmp print_board_unicode
.ascii:
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
;        edx = textovy riadok r (0..scale/2-1), ecx = scale (8 alebo 16)
; 8px rezim: cita precomputed 8x8 masku (majority-vote downsampl zo 16x16)
; ============================================================
uni_print_cell_row:
    push rbx
    push r12
    push r13
    push r14
    push r15
    test rdi, rdi
    jnz .piece
    ; prazdne policko: bg farba + scale medzier
    sub rsp, 24
    xor eax, eax
.fill:
    mov byte [rsp + rax], ' '
    inc eax
    cmp eax, ecx
    jl .fill
    mov byte [rsp + rax], 0
    mov cl, 1
    call uni_print_color_seq        ; esi = farba policka
    mov rdi, rsp
    call write_cstr
    add rsp, 24
    jmp .done

.piece:
    mov r13d, esi                   ; r13 = farba policka
    mov r15d, ecx                   ; r15 = scale (pocet stlpcov)
    mov eax, 0x00F0F0F0             ; biela figurka
    mov r10d, edi
    and r10d, COLOR_MASK
    jz .wcol
    mov eax, 0x00202020             ; cierna figurka
.wcol:
    mov r14d, eax                   ; r14 = farba figurky
    ; maska je farbovo neutralna -> len typ figurky
    mov eax, edi
    and eax, PIECE_MASK
    dec eax
    cmp r15d, 16
    je .scale16
    ; ---- 8px: 8x8 maska z majority-vote downsamplu (1 bajt/riadok) ----
    shl eax, 3
    lea r10, [piece_bitmaps_8]
    add r10, rax                    ; r10 = maska figurky (8 B)
    movzx r12d, byte [r10 + rdx*2]          ; horny pixel riadok = r 2r
    movzx ebx, byte [r10 + rdx*2 + 1]       ; dolny pixel riadok = 2r+1
    jmp .cols
.scale16:
    shl eax, 5
    lea r10, [piece_bitmaps]
    add r10, rax                    ; r10 = maska figurky (32 B)
    mov r11d, edx
    shl r11d, 2                     ; 2 pixely/riadok * 2 bajty/riadok = 4 bajty na par
    movzx r12d, byte [r10 + r11]    ; horny pixel riadok, byte 0 (x 0-7)
    shl r12d, 8
    movzx eax, byte [r10 + r11 + 1] ; horny pixel riadok, byte 1 (x 8-15)
    or r12d, eax
    movzx ebx, byte [r10 + r11 + 2] ; dolny pixel riadok, byte 0
    shl ebx, 8
    movzx eax, byte [r10 + r11 + 3] ; dolny pixel riadok, byte 1
    or ebx, eax
.cols:
    mov r10d, -1                    ; predchadzajuci stav (bit1=horny px, bit0=dolny px)
.col_loop:
    lea r9d, [r15d - 1]             ; bit index x (r9 preziva volania)
    xor eax, eax
    bt r12d, r9d
    jnc .no_top
    or eax, 2
.no_top:
    bt ebx, r9d
    jnc .no_bot
    or eax, 1
.no_bot:
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
; print_board_unicode - sachovnica cez '▀' polobloky z piece_bitmaps
; Kazdy textovy riadok nesie 2 vertikalne pixely (fg=hore, bg=dole).
; Scale: unicode_pieces=1 -> 8x8 px/policko (66 znakov sirka, zmesti sa
; do 80-stlpcoveho terminalu), =2 -> 16x16 px (130 znakov, sirsi terminal).
; Riadky rankov bez oddelovacich prazdnych riadkov (cierne pasy).
; Podporuje board_flip (cierny pohlad). Panel sa netlaci.
; ============================================================
print_board_unicode:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov ebp, 8                      ; scale = px velkost figurky
    cmp byte [unicode_pieces], 2
    jne .scale_ok
    mov ebp, 16
.scale_ok:
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
    xor r14, r14                    ; r14 = textovy riadok ranku 0..scale/2-1
.row_loop:
    mov eax, ebp
    shr eax, 2                      ; prostredny riadok niesa cislo ranku
    cmp r14, rax
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
    mov ecx, ebp                    ; scale
    call uni_print_cell_row
    inc rbx
    cmp rbx, 8
    jl .cell_loop
    lea rdi, [board_uni_reset]
    call write_cstr
    call print_newline
    inc r14
    mov eax, ebp
    shr eax, 1                      ; scale/2 textovych riadkov na rank
    cmp r14, rax
    jl .row_loop
    inc r12
    cmp r12, 8
    jl .rank_loop
    call .print_file_letters
    call print_newline
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.print_file_letters:
    push rbx
    ; medzery za pismenom: scale-1 (do stack bufferu)
    sub rsp, 24
    mov eax, ebp
    dec eax
    xor ecx, ecx
.sp_fill:
    mov byte [rsp + rcx], ' '
    inc ecx
    cmp ecx, eax
    jl .sp_fill
    mov byte [rsp + rcx], 0
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
    mov rdi, rsp                    ; (scale-1) medzier
    call write_cstr
    inc rbx
    cmp rbx, 8
    jl .fl_loop
    add rsp, 24
    pop rbx
    ret

; ============================================================
; print_board_glyphs - sachovnica z fontovych sachovych glyfov
; (unicode_pieces=3): kazde policko = 1 znak, 8 riadkov x 8 stlpcov.
; Biele figurky = outline glyfy (U+2654-59), cierne = filled
; (U+265A-5F); fg = farba figurky, bg = farba policka.
; Podporuje board_flip. Riadok: "8 " + 8 glyfov + ESC[0m.
; ============================================================
print_board_glyphs:
    push rbx
    push r12
    push r13
    push r15
    call print_newline
    call .print_letters
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
    ; cislo ranku v lavo
    mov eax, r13d
    add eax, '1'
    mov [rank_char_buf], al
    mov byte [rank_char_buf+1], 0
    lea rdi, [rank_char_buf]
    call write_cstr
    lea rdi, [board_uni_ranksp]
    call write_cstr

    xor rbx, rbx                    ; display stlpec 0..7
.cell_loop:
    mov rax, rbx
    cmp byte [board_flip], 0
    je .file_ok
    mov rax, 7
    sub rax, rbx
.file_ok:
    mov r15, rax                    ; r15 = realny file (preziva vsetky volania)
    mov rax, r13
    shl rax, 3
    add rax, r15
    call pos_piece_at_sq_bb         ; piece byte (rax)
    mov r9d, eax                    ; r9 = piece (preziva seq volania)
    ; farba policka
    mov eax, r13d
    add eax, r15d
    and eax, 1
    jz .dark_sq
    mov esi, [light_col]
    jmp .sq_ok
.dark_sq:
    mov esi, [dark_col]
.sq_ok:
    test r9d, r9d
    jnz .piece
    ; prazdne policko: fg=bg=farba policka + medzera
    push rsi
    mov cl, 0
    call uni_print_color_seq
    pop rsi
    mov cl, 1
    call uni_print_color_seq
    lea rdi, [board_uni_ranksp]
    call write_cstr
    jmp .next_cell
.piece:
    ; fg = farba figurky, bg = farba policka
    mov eax, 0x00F0F0F0             ; biela figurka
    test r9d, COLOR_MASK
    jz .wcol
    mov eax, 0x00202020             ; cierna figurka
.wcol:
    push rsi
    mov esi, eax
    mov cl, 0
    call uni_print_color_seq
    pop rsi
    mov cl, 1
    call uni_print_color_seq
    ; index do tabulky glyfov: color*6 + (type-1)
    mov eax, r9d
    and eax, COLOR_MASK
    shr eax, 3
    imul eax, eax, 6
    mov edx, r9d
    and edx, PIECE_MASK
    dec edx
    add eax, edx
    lea rdi, [board_glyphs]
    shl eax, 2                      ; 4 bajty na zaznam
    add rdi, rax
    call write_cstr
.next_cell:
    inc rbx
    cmp rbx, 8
    jl .cell_loop
    lea rdi, [board_uni_reset]
    call write_cstr
    call print_newline
    inc r12
    cmp r12, 8
    jl .rank_loop
    call .print_letters
    call print_newline
    pop r15
    pop r13
    pop r12
    pop rbx
    ret

.print_letters:
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
    lea rdi, [board_uni_ranksp]
    call write_cstr
    inc rbx
    cmp rbx, 8
    jl .fl_loop
    pop rbx
    ret
