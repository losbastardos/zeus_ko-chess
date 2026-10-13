; ============================================================
; suite.asm - natívna analyza testovacich sad (EPD/FEN|bm)
; ============================================================

%include "chess.inc"

DEFAULT REL

section .data

suite_usage_text:
    db "Pouzitie:", 10
    db "  suite <subor.epd|subor.txt> [depth] [movetime_ms]", 10
    db "  analyze <FEN|bm>  (priklad: analyze <fen> | e2e4)", 10, 0

suite_usage_uci:
    db "info string usage: suite <file> [depth] [movetime_ms] | analyze <FEN|bm>", 10, 0

suite_err_open_text: db "Suite: nepodarilo sa otvorit subor.", 10, 0
suite_err_open_uci:  db "info string suite error: cannot open file", 10, 0

suite_hdr_text: db "Suite: spracovavam...", 10, 0
suite_hdr_uci:  db "info string suite: processing", 10, 0

suite_res_prefix_text: db "Suite: cases=", 0
suite_res_prefix_uci:  db "info string suite result cases=", 0
suite_res_hits:        db " hits=", 0
suite_res_misses:      db " misses=", 0
suite_res_rate:        db " hitrate%=", 0
suite_res_nodes:       db " nodes=", 0
suite_res_time:        db " time_ms=", 0
suite_res_score:       db " score=", 0
suite_res_slash:       db "/", 0

section .bss

suite_mode:          resb 1   ; 0=text, 1=uci
suite_depth:         resb 1
suite_file_path:     resb 512
suite_file_buf:      resb 262144
suite_line_buf:      resb 2048
suite_fen_buf:       resb 1024
suite_bm_buf:        resb 512
suite_best_buf:      resb 8
suite_best_move:     resw 1
suite_case_mode:     resb 1   ; 1=bm (best move), 2=am (avoid move)
suite_movetime:      resq 1

suite_cases:         resq 1
suite_hits:          resq 1
suite_nodes_total:   resq 1
suite_time_total:    resq 1

suite_fd:            resq 1
suite_read_len:      resq 1

; snapshot povodneho stavu
suite_saved_board:   resb 64
suite_saved_side:    resb 1
suite_saved_castle:  resb 1
suite_saved_ep:      resb 1
suite_saved_half:    resb 1
suite_saved_full:    resw 1
suite_saved_hash:    resq 1
suite_saved_hcount:  resq 1
suite_saved_hhist:   resq 256
suite_saved_limits:  resb 72
suite_saved_uci_stop: resb 1
suite_saved_syzygy_depth: resd 1

section .text

global suite_cmd_text, suite_cmd_uci, suite_snapshot_save, suite_snapshot_restore

extern move_buf, move_buf_len
extern search_depth, nodes_searched
extern board, side, castle, enpassant, halfmove, fullmove, position_hash
extern hash_history, hash_count
extern parse_fen_string, search_best_move
extern print_number, print_newline, write_cstr, uci_now_ms
extern search_limits, uci_stop_flag
extern uci_syzygy_probe_depth

; ------------------------------------------------------------
; util: token parser nad move_buf
; in: rdi = start idx
; out: rax = start, rbx = len, rcx = next idx, rax=-1 ak koniec
; ------------------------------------------------------------
suite_token:
    push r12
    push r13
    mov r12, rdi
    mov r13, [move_buf_len]
.skip_ws:
    cmp r12, r13
    jge .end
    movzx rax, byte [move_buf + r12]
    cmp rax, ' '
    je .ws
    cmp rax, 9
    je .ws
    cmp rax, 10
    je .ws
    cmp rax, 13
    je .ws
    jmp .scan
.ws:
    inc r12
    jmp .skip_ws
.scan:
    mov r8, r12
.scan_loop:
    cmp r8, r13
    jge .done_tok
    movzx rax, byte [move_buf + r8]
    cmp rax, ' '
    je .done_tok
    cmp rax, 9
    je .done_tok
    cmp rax, 10
    je .done_tok
    cmp rax, 13
    je .done_tok
    inc r8
    jmp .scan_loop
.done_tok:
    mov rax, r12
    mov rbx, r8
    sub rbx, r12
    mov rcx, r8
    pop r13
    pop r12
    ret
.end:
    mov rax, -1
    pop r13
    pop r12
    ret

; ------------------------------------------------------------
; util: porovnanie tokenu s C-string
; ------------------------------------------------------------
suite_tok_eq:
    push rbx
    push rcx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor rcx, rcx
.loop:
    cmp rcx, r13
    jge .term
    movzx rax, byte [move_buf + r12 + rcx]
    movzx rbx, byte [r14 + rcx]
    cmp rax, rbx
    jne .no
    inc rcx
    jmp .loop
.term:
    movzx rax, byte [r14 + rcx]
    test rax, rax
    jz .yes
.no:
    xor rax, rax
    jmp .out
.yes:
    mov rax, 1
.out:
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------
; util: ascii decimal do rax (token z move_buf)
; in: rdi start, rsi len; out: rax value, rdx valid(1/0)
; ------------------------------------------------------------
suite_tok_u64:
    push rbx
    push rcx
    xor rax, rax
    xor rdx, rdx
    xor rcx, rcx
.loop:
    cmp rcx, rsi
    jge .ok
    movzx rbx, byte [move_buf + rdi + rcx]
    sub rbx, '0'
    cmp rbx, 9
    ja .bad
    imul rax, 10
    add rax, rbx
    inc rcx
    jmp .loop
.ok:
    mov rdx, 1
    jmp .out
.bad:
    xor rax, rax
    xor rdx, rdx
.out:
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------
; util: trim/copy substring -> dst buffer
; in: rdi=src, rsi=len, rdx=dst, rcx=dst_cap
; out: rax=dst_len
; ------------------------------------------------------------
suite_trim_copy:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi      ; src
    mov r13, rsi      ; len
    mov r14, rdx      ; dst

    ; left trim
.left:
    test r13, r13
    jz .empty
    movzx rax, byte [r12]
    cmp rax, ' '
    je .lstep
    cmp rax, 9
    je .lstep
    cmp rax, 13
    je .lstep
    jmp .right
.lstep:
    inc r12
    dec r13
    jmp .left

.right:
    test r13, r13
    jz .empty
    mov rbx, r13
    dec rbx
.rloop:
    movzx rax, byte [r12 + rbx]
    cmp rax, ' '
    je .rdec
    cmp rax, 9
    je .rdec
    cmp rax, 13
    je .rdec
    jmp .copy
.rdec:
    dec r13
    test r13, r13
    jz .empty
    mov rbx, r13
    dec rbx
    jmp .rloop

.copy:
    mov rax, r13
    cmp rax, rcx
    jb .cap_ok
    mov rax, rcx
    dec rax
.cap_ok:
    mov rbx, rax
    xor rsi, rsi
.cpy_loop:
    cmp rsi, rbx
    jge .term
    mov dl, [r12 + rsi]
    mov [r14 + rsi], dl
    inc rsi
    jmp .cpy_loop
.term:
    mov byte [r14 + rbx], 0
    mov rax, rbx
    jmp .out
.empty:
    mov byte [r14], 0
    xor rax, rax
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------
; util: najde oddelovac "|", " bm " alebo " am "
; in: rdi=buf, rsi=len
; out: rax=0 none, 1 pipe, 2 bm-word, 3 am-word
;      rbx=idx oddelovaca
; ------------------------------------------------------------
suite_find_delim:
    push rcx
    push r12
    mov r12, rdi
    xor rcx, rcx
.loop:
    cmp rcx, rsi
    jge .none
    movzx rax, byte [r12 + rcx]
    cmp rax, '|'
    je .pipe
    cmp rax, 'b'
    je .chk_bm
    cmp rax, 'a'
    je .chk_am
    jmp .next
.chk_bm:
    cmp rcx, 0
    je .next
    mov rax, rcx
    add rax, 2
    cmp rax, rsi
    jge .next
    movzx rax, byte [r12 + rcx - 1]
    cmp rax, ' '
    jne .next
    cmp byte [r12 + rcx + 1], 'm'
    jne .next
    cmp byte [r12 + rcx + 2], ' '
    jne .next
    mov rax, 2
    mov rbx, rcx
    jmp .out
.chk_am:
    cmp rcx, 0
    je .next
    mov rax, rcx
    add rax, 2
    cmp rax, rsi
    jge .next
    movzx rax, byte [r12 + rcx - 1]
    cmp rax, ' '
    jne .next
    cmp byte [r12 + rcx + 1], 'm'
    jne .next
    cmp byte [r12 + rcx + 2], ' '
    jne .next
    mov rax, 3
    mov rbx, rcx
    jmp .out
.pipe:
    mov rax, 1
    mov rbx, rcx
    jmp .out
.next:
    inc rcx
    jmp .loop
.none:
    xor rax, rax
.out:
    pop r12
    pop rcx
    ret

; ------------------------------------------------------------
; util: validuje tvar UCI tahu v buffri
; in: rdi=ptr, rsi=len
; out: rax=1/0
; ------------------------------------------------------------
suite_is_move_tok:
    cmp rsi, 4
    je .base
    cmp rsi, 5
    jne .no
.base:
    mov al, [rdi]
    cmp al, 'a'
    jb .no
    cmp al, 'h'
    ja .no
    mov al, [rdi + 1]
    cmp al, '1'
    jb .no
    cmp al, '8'
    ja .no
    mov al, [rdi + 2]
    cmp al, 'a'
    jb .no
    cmp al, 'h'
    ja .no
    mov al, [rdi + 3]
    cmp al, '1'
    jb .no
    cmp al, '8'
    ja .no
    cmp rsi, 5
    jne .yes
    mov al, [rdi + 4]
    cmp al, 'q'
    je .yes
    cmp al, 'r'
    je .yes
    cmp al, 'b'
    je .yes
    cmp al, 'n'
    je .yes
    jmp .no
.yes:
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

; ------------------------------------------------------------
; util: best move -> text (e2e4 / e7e8q)
; in: rax = move
; out: suite_best_buf null-terminated
; ------------------------------------------------------------
suite_move_to_str:
    push rbx

    mov rbx, rax
    and rbx, 0x3F
    mov rcx, rbx
    and rcx, 7
    add cl, 'a'
    mov [suite_best_buf], cl
    mov rcx, rbx
    shr rcx, 3
    add cl, '1'
    mov [suite_best_buf + 1], cl

    mov rbx, rax
    shr rbx, 6
    and rbx, 0x3F
    mov rcx, rbx
    and rcx, 7
    add cl, 'a'
    mov [suite_best_buf + 2], cl
    mov rcx, rbx
    shr rcx, 3
    add cl, '1'
    mov [suite_best_buf + 3], cl

    mov rbx, rax
    shr rbx, 12
    mov byte [suite_best_buf + 4], 0
    cmp rbx, FLAG_PROMO_Q
    jb .done
    cmp rbx, FLAG_PROMO_N
    ja .done
    cmp rbx, FLAG_PROMO_Q
    jne .pr
    mov byte [suite_best_buf + 4], 'q'
    jmp .term5
.pr:
    cmp rbx, FLAG_PROMO_R
    jne .pb
    mov byte [suite_best_buf + 4], 'r'
    jmp .term5
.pb:
    cmp rbx, FLAG_PROMO_B
    jne .pn
    mov byte [suite_best_buf + 4], 'b'
    jmp .term5
.pn:
    mov byte [suite_best_buf + 4], 'n'
.term5:
    mov byte [suite_best_buf + 5], 0
.done:
    pop rbx
    ret

; ------------------------------------------------------------
; util: porovna bestmove s bm-listom (medzery, ';' koniec)
; in: rdi=ptr moves, rsi=len
; out: rax=1 hit / 0 miss
; ------------------------------------------------------------
suite_match_bm:
    push rbx
    push rcx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor rcx, rcx
.next_tok:
    cmp rcx, r13
    jge .miss
.skip_ws:
    cmp rcx, r13
    jge .miss
    movzx rax, byte [r12 + rcx]
    cmp rax, ';'
    je .miss
    cmp rax, ' '
    je .s1
    cmp rax, 9
    je .s1
    jmp .tok_start
.s1:
    inc rcx
    jmp .skip_ws
.tok_start:
    mov rbx, rcx
.tok_scan:
    cmp rcx, r13
    jge .tok_end
    movzx rax, byte [r12 + rcx]
    cmp rax, ';'
    je .tok_end
    cmp rax, ' '
    je .tok_end
    cmp rax, 9
    je .tok_end
    inc rcx
    jmp .tok_scan
.tok_end:
    mov rdi, r12
    add rdi, rbx
    mov rsi, rcx
    sub rsi, rbx
    call suite_is_move_tok
    test rax, rax
    jz .try_san

    ; porovnaj token s bestmove
    mov rdi, r12
    add rdi, rbx
    mov rsi, rcx
    sub rsi, rbx
    mov r8, 4
    cmp byte [suite_best_buf + 4], 0
    je .len_ready
    mov r8, 5
.len_ready:
    cmp rsi, r8
    jne .next_tok

    xor r9, r9
.cmp_loop:
    cmp r9, r8
    jge .hit
    mov al, [rdi + r9]
    cmp al, [suite_best_buf + r9]
    jne .next_tok
    inc r9
    jmp .cmp_loop

.try_san:
    mov rdi, r12
    add rdi, rbx
    mov rsi, rcx
    sub rsi, rbx
    call suite_match_san_light
    test rax, rax
    jz .next_tok
    jmp .hit

.hit:
    mov rax, 1
    jmp .out
.miss:
    xor rax, rax
.out:
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------
; util: lightweight SAN match token vs bestmove
; Podporuje: O-O/O-O-O, piece letter, capture 'x', cielove pole, promo "=Q".
; ignoruje trailing ! ? + #.
; in: rdi=token ptr, rsi=token len
; out: rax=1/0
; ------------------------------------------------------------
suite_match_san_light:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12

    mov r8, rdi      ; token ptr
    mov r9, rsi      ; token len

    ; trim trailing SAN suffixes
.trim:
    test r9, r9
    jz .miss
    mov al, [r8 + r9 - 1]
    cmp al, '!'
    je .trim_dec
    cmp al, '?'
    je .trim_dec
    cmp al, '+'
    je .trim_dec
    cmp al, '#'
    je .trim_dec
    jmp .have_tok
.trim_dec:
    dec r9
    jmp .trim

.have_tok:
    ; castling SAN
    cmp r9, 3
    jne .chk_ooo
    mov al, [r8]
    cmp al, 'O'
    je .co1
    cmp al, 'o'
    je .co1
    cmp al, '0'
    jne .chk_ooo
.co1:
    cmp byte [r8 + 1], '-'
    jne .chk_ooo
    mov al, [r8 + 2]
    cmp al, 'O'
    je .castle_short
    cmp al, 'o'
    je .castle_short
    cmp al, '0'
    jne .chk_ooo
.castle_short:
    movzx eax, word [suite_best_move]
    mov ecx, eax
    shr ecx, 12
    and ecx, 0xF
    cmp ecx, FLAG_CASTLE
    jne .miss
    shr eax, 6
    and eax, 0x3F
    and eax, 7
    cmp eax, 6
    jne .miss
    jmp .hit

.chk_ooo:
    cmp r9, 5
    jne .not_castle
    mov al, [r8]
    cmp al, 'O'
    je .coo1
    cmp al, 'o'
    je .coo1
    cmp al, '0'
    jne .not_castle
.coo1:
    cmp byte [r8 + 1], '-'
    jne .not_castle
    mov al, [r8 + 2]
    cmp al, 'O'
    je .coo2
    cmp al, 'o'
    je .coo2
    cmp al, '0'
    jne .not_castle
.coo2:
    cmp byte [r8 + 3], '-'
    jne .not_castle
    mov al, [r8 + 4]
    cmp al, 'O'
    je .castle_long
    cmp al, 'o'
    je .castle_long
    cmp al, '0'
    jne .not_castle
.castle_long:
    movzx eax, word [suite_best_move]
    mov ecx, eax
    shr ecx, 12
    and ecx, 0xF
    cmp ecx, FLAG_CASTLE
    jne .miss
    shr eax, 6
    and eax, 0x3F
    and eax, 7
    cmp eax, 2
    jne .miss
    jmp .hit

.not_castle:
    ; najdi '=' (promo), ak je
    mov r10, -1
    xor rcx, rcx
.eq_scan:
    cmp rcx, r9
    jge .eq_done
    mov al, [r8 + rcx]
    cmp al, '='
    jne .eq_next
    mov r10, rcx
    jmp .eq_done
.eq_next:
    inc rcx
    jmp .eq_scan
.eq_done:

    mov r11, r9
    cmp r10, -1
    je .end_ok
    mov r11, r10
.end_ok:
    cmp r11, 2
    jb .miss

    ; destination square z tokenu
    mov dl, [r8 + r11 - 2]
    mov cl, [r8 + r11 - 1]
    cmp dl, 'A'
    jb .f_ok
    cmp dl, 'Z'
    ja .f_ok
    add dl, 32
.f_ok:
    cmp dl, 'a'
    jb .miss
    cmp dl, 'h'
    ja .miss
    cmp cl, '1'
    jb .miss
    cmp cl, '8'
    ja .miss

    ; porovnaj destination s bestmove to-square
    movzx eax, word [suite_best_move]
    mov ebx, eax
    shr ebx, 6
    and ebx, 0x3F
    mov edx, ebx
    and edx, 7
    add dl, 'a'
    cmp dl, [r8 + r11 - 2]
    je .rank_cmp
    ; aj lowercase varianta
    mov dl, [r8 + r11 - 2]
    cmp dl, 'A'
    jb .miss
    cmp dl, 'Z'
    ja .miss
    add dl, 32
    mov edx, ebx
    and edx, 7
    add dl, 'a'
    cmp dl, [r8 + r11 - 2]
    jne .miss
.rank_cmp:
    mov edx, ebx
    shr edx, 3
    add dl, '1'
    cmp dl, [r8 + r11 - 1]
    jne .miss

    ; piece letter (ak zacina KQRBN)
    mov al, [r8]
    mov r12d, PAWN
    cmp al, 'K'
    jne .pQ
    mov r12d, KING
    jmp .ptype_check
.pQ:
    cmp al, 'Q'
    jne .pR
    mov r12d, QUEEN
    jmp .ptype_check
.pR:
    cmp al, 'R'
    jne .pB
    mov r12d, ROOK
    jmp .ptype_check
.pB:
    cmp al, 'B'
    jne .pN
    mov r12d, BISHOP
    jmp .ptype_check
.pN:
    cmp al, 'N'
    jne .ptype_check
    mov r12d, KNIGHT

.ptype_check:
    movzx eax, word [suite_best_move]
    and eax, 0x3F
    movzx eax, byte [board + rax]
    and eax, PIECE_MASK
    cmp eax, r12d
    jne .miss

    ; capture indicator 'x' v tokene -> ebx
    xor rcx, rcx
    xor ebx, ebx
.cap_scan:
    cmp rcx, r9
    jge .cap_done
    cmp byte [r8 + rcx], 'x'
    jne .cap_next
    mov ebx, 1
    jmp .cap_done
.cap_next:
    inc rcx
    jmp .cap_scan
.cap_done:
    ; bestmove capture flag -> edx
    movzx eax, word [suite_best_move]
    mov ecx, eax
    shr ecx, 12
    and ecx, 0xF
    xor edx, edx
    cmp ecx, FLAG_ENPASSANT
    je .bm_cap_yes
    shr eax, 6
    and eax, 0x3F
    movzx eax, byte [board + rax]
    test eax, eax
    jz .bm_cap_done
.bm_cap_yes:
    mov edx, 1
.bm_cap_done:
    cmp edx, ebx
    jne .miss

    ; --- disambiguacia (light SAN) ---
    cmp r12d, PAWN
    je .dis_pawn
    ; figurky: skenuj znaky medzi piece letter a cielovym polickom
    mov ecx, 1
.dis_loop:
    mov eax, r11d
    sub eax, 2
    cmp ecx, eax
    jge .promo_check
    movzx eax, byte [r8 + rcx]
    cmp al, 'x'
    je .dis_next
    cmp al, '1'
    jb .dis_file
    cmp al, '8'
    jbe .dis_rank
.dis_file:
    cmp al, 'a'
    jb .dis_next
    cmp al, 'h'
    ja .dis_next
    movzx eax, word [suite_best_move]
    and eax, 0x3F
    and eax, 7
    add al, 'a'
    cmp al, byte [r8 + rcx]
    jne .miss
    jmp .dis_next
.dis_rank:
    movzx eax, word [suite_best_move]
    and eax, 0x3F
    shr eax, 3
    add al, '1'
    cmp al, byte [r8 + rcx]
    jne .miss
.dis_next:
    inc ecx
    jmp .dis_loop

.dis_pawn:
    test ebx, ebx
    jz .promo_check
    ; pesacia brania: token[0] je from-file
    movzx eax, word [suite_best_move]
    and eax, 0x3F
    and eax, 7
    add al, 'a'
    cmp al, byte [r8]
    jne .miss

.promo_check:
    cmp r10, -1
    je .hit
    ; token po '=' urcuje promo figuru
    cmp r10, r9
    jae .miss
    mov al, [r8 + r10 + 1]
    movzx ebx, word [suite_best_move]
    shr ebx, 12
    cmp al, 'Q'
    je .pr_q
    cmp al, 'q'
    je .pr_q
    cmp al, 'R'
    je .pr_r
    cmp al, 'r'
    je .pr_r
    cmp al, 'B'
    je .pr_b
    cmp al, 'b'
    je .pr_b
    cmp al, 'N'
    je .pr_n
    cmp al, 'n'
    je .pr_n
    jmp .miss
.pr_q:
    cmp ebx, FLAG_PROMO_Q
    je .hit
    jmp .miss
.pr_r:
    cmp ebx, FLAG_PROMO_R
    je .hit
    jmp .miss
.pr_b:
    cmp ebx, FLAG_PROMO_B
    je .hit
    jmp .miss
.pr_n:
    cmp ebx, FLAG_PROMO_N
    je .hit
    jmp .miss

.hit:
    mov rax, 1
    jmp .out
.miss:
    xor rax, rax
.out:
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------
; util: pripravi search limity pre suite case
; depth-only: mode=0
; timed: mode=1 + movetime/soft/hard
; ------------------------------------------------------------
suite_prepare_limits:
    push rax

    mov byte [search_limits + 0], 0
    mov al, [suite_depth]
    mov byte [search_limits + 1], al
    mov byte [search_limits + 2], 0

    xor rax, rax
    mov qword [search_limits + 8], rax
    mov qword [search_limits + 16], rax
    mov qword [search_limits + 24], rax
    mov qword [search_limits + 32], rax
    mov qword [search_limits + 40], rax
    mov qword [search_limits + 48], rax
    mov qword [search_limits + 56], rax
    mov qword [search_limits + 64], rax
    mov byte [uci_stop_flag], 0

    mov rax, [suite_movetime]
    test rax, rax
    jz .set_start
    mov byte [search_limits + 0], 1
    mov qword [search_limits + 8], rax
    mov qword [search_limits + 56], rax
    mov qword [search_limits + 64], rax

.set_start:
    call uci_now_ms
    mov qword [search_limits + 48], rax

    pop rax
    ret

; ------------------------------------------------------------
; parse line (EPD/FEN|bm), search, update counters
; in: rdi=line ptr, rsi=line len
; out: rax=1 processed, 0 skipped/error
; ------------------------------------------------------------
suite_process_line:
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi
    mov r13, rsi

    ; ignore prazdne/koment
    test r13, r13
    jz .skip
    movzx rax, byte [r12]
    cmp rax, '#'
    je .skip
    cmp rax, ';'
    je .skip

    mov rdi, r12
    mov rsi, r13
    call suite_find_delim
    test rax, rax
    jz .skip

    cmp rax, 1
    je .fmt_pipe

    cmp rax, 2
    jne .fmt_word_am
    mov byte [suite_case_mode], 1
    jmp .fmt_word
.fmt_word_am:
    mov byte [suite_case_mode], 2

    ; fmt bm/am-word
.fmt_word:
    mov r15, rbx
.fen_trim_tail:
    test r15, r15
    jz .skip
    movzx rax, byte [r12 + r15 - 1]
    cmp rax, ' '
    je .fen_dec
    cmp rax, 9
    je .fen_dec
    cmp rax, 13
    je .fen_dec
    cmp rax, ';'
    je .fen_dec
    jmp .fen_trim_done
.fen_dec:
    dec r15
    jmp .fen_trim_tail
.fen_trim_done:
    mov rdi, r12
    mov rsi, r15
    lea rdx, [suite_fen_buf]
    mov rcx, 1024
    call suite_trim_copy
    test rax, rax
    jz .skip

    lea rdi, [r12 + rbx + 3]
    mov rsi, r13
    sub rsi, rbx
    sub rsi, 3
    lea rdx, [suite_bm_buf]
    mov rcx, 512
    call suite_trim_copy
    jmp .have_parts

.fmt_pipe:
    mov byte [suite_case_mode], 1
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [suite_fen_buf]
    mov rcx, 1024
    call suite_trim_copy
    test rax, rax
    jz .skip

    lea rdi, [r12 + rbx + 1]
    mov rsi, r13
    sub rsi, rbx
    dec rsi
    lea rdx, [suite_bm_buf]
    mov rcx, 512
    call suite_trim_copy

.have_parts:
    ; bm cast nechame len po prve ';' (EPD ma za nim dalsie opkody)
    lea rdi, [suite_bm_buf]
    xor rcx, rcx
.bm_cut_scan:
    mov al, [rdi + rcx]
    test al, al
    jz .bm_cut_done
    cmp al, ';'
    je .bm_cut_here
    inc rcx
    cmp rcx, 511
    jb .bm_cut_scan
    jmp .bm_cut_done
.bm_cut_here:
    mov byte [rdi + rcx], 0
.bm_cut_done:
    ; right-trim medzier/tabov
    xor rcx, rcx
.bm_len_scan:
    mov al, [rdi + rcx]
    test al, al
    jz .bm_trim
    inc rcx
    cmp rcx, 511
    jb .bm_len_scan
.bm_trim:
    test rcx, rcx
    jz .bm_ready
.bm_trim_loop:
    mov al, [rdi + rcx - 1]
    cmp al, ' '
    je .bm_trim_dec
    cmp al, 9
    je .bm_trim_dec
    jmp .bm_ready
.bm_trim_dec:
    dec rcx
    test rcx, rcx
    jz .bm_zero
    jmp .bm_trim_loop
.bm_zero:
    mov byte [rdi], 0
    jmp .fen_norm
.bm_ready:
    mov byte [rdi + rcx], 0

.fen_norm:
    ; EPD casto nesie len 4 FEN polia (bez halfmove/fullmove)
    ; -> doplnime default " 0 1", aby parse_fen_string dostal plny FEN.
    lea rdi, [suite_fen_buf]
    xor rcx, rcx
    xor rdx, rdx
.fen_count_loop:
    mov al, [rdi + rcx]
    test al, al
    jz .fen_count_done
    cmp al, ' '
    jne .fen_count_next
    inc rdx
.fen_count_next:
    inc rcx
    cmp rcx, 1018
    jb .fen_count_loop
.fen_count_done:
    ; 4-polovy FEN ma 3 medzery
    cmp rdx, 3
    jne .fen_ready
    mov byte [rdi + rcx], ' '
    mov byte [rdi + rcx + 1], '0'
    mov byte [rdi + rcx + 2], ' '
    mov byte [rdi + rcx + 3], '1'
    mov byte [rdi + rcx + 4], 0

.fen_ready:
    ; parse FEN
    lea rdi, [suite_fen_buf]
    call parse_fen_string
    test rax, rax
    jnz .skip

    call suite_prepare_limits

    ; search
    call uci_now_ms
    mov r14, rax

    ; suite ma emulovat UCI go depth: iterative deepening 1..N
    ; (jednorazove volanie iba na finalnej hlbke meni ordering/historie)
    movzx r12d, byte [suite_depth]
    mov ebx, 1
.suite_id_loop:
    cmp ebx, r12d
    jg .suite_id_done
    mov edi, ebx
    call search_best_move
    mov r15, rax
    inc ebx
    jmp .suite_id_loop
.suite_id_done:

    call uci_now_ms
    sub rax, r14
    add [suite_time_total], rax

    mov rax, [nodes_searched]
    add [suite_nodes_total], rax

    mov rax, r15
    call suite_move_to_str
    mov [suite_best_move], r15w

    lea rdi, [suite_bm_buf]
    xor rsi, rsi
.bmlen:
    cmp byte [rdi + rsi], 0
    je .bmdone
    inc rsi
    jmp .bmlen
.bmdone:
    call suite_match_bm
    cmp byte [suite_case_mode], 2
    jne .bm_eval
    ; am: hit ak bestmove NIE JE v avoid liste
    test rax, rax
    jnz .count_only
    inc qword [suite_hits]
    jmp .count_only

.bm_eval:
    test rax, rax
    jz .count_only
    inc qword [suite_hits]
.count_only:
    inc qword [suite_cases]
    mov rax, 1
    jmp .out

.skip:
    xor rax, rax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------
; snapshot/restore stavu hry
; ------------------------------------------------------------
suite_snapshot_save:
    push rcx
    push rsi
    push rdi

    lea rsi, [board]
    lea rdi, [suite_saved_board]
    mov rcx, 64
    rep movsb

    mov al, [side]
    mov [suite_saved_side], al
    mov al, [castle]
    mov [suite_saved_castle], al
    mov al, [enpassant]
    mov [suite_saved_ep], al
    mov al, [halfmove]
    mov [suite_saved_half], al
    mov ax, [fullmove]
    mov [suite_saved_full], ax
    mov rax, [position_hash]
    mov [suite_saved_hash], rax
    mov rax, [hash_count]
    mov [suite_saved_hcount], rax

    lea rsi, [hash_history]
    lea rdi, [suite_saved_hhist]
    mov rcx, 256
    rep movsq

    lea rsi, [search_limits]
    lea rdi, [suite_saved_limits]
    mov rcx, 72
    rep movsb

    mov al, [uci_stop_flag]
    mov [suite_saved_uci_stop], al
    mov eax, [uci_syzygy_probe_depth]
    mov [suite_saved_syzygy_depth], eax

    pop rdi
    pop rsi
    pop rcx
    ret

suite_snapshot_restore:
    push rcx
    push rsi
    push rdi

    lea rsi, [suite_saved_board]
    lea rdi, [board]
    mov rcx, 64
    rep movsb

    mov al, [suite_saved_side]
    mov [side], al
    mov al, [suite_saved_castle]
    mov [castle], al
    mov al, [suite_saved_ep]
    mov [enpassant], al
    mov al, [suite_saved_half]
    mov [halfmove], al
    mov ax, [suite_saved_full]
    mov [fullmove], ax
    mov rax, [suite_saved_hash]
    mov [position_hash], rax
    mov rax, [suite_saved_hcount]
    mov [hash_count], rax

    lea rsi, [suite_saved_hhist]
    lea rdi, [hash_history]
    mov rcx, 256
    rep movsq

    lea rsi, [suite_saved_limits]
    lea rdi, [search_limits]
    mov rcx, 72
    rep movsb

    mov al, [suite_saved_uci_stop]
    mov [uci_stop_flag], al
    mov eax, [suite_saved_syzygy_depth]
    mov [uci_syzygy_probe_depth], eax

    pop rdi
    pop rsi
    pop rcx
    ret

; ------------------------------------------------------------
; vypis summary
; ------------------------------------------------------------
suite_print_summary:
    push rax
    push rbx
    push rcx
    push rdx

    cmp byte [suite_mode], 0
    jne .uci_prefix
    lea rdi, [suite_res_prefix_text]
    call write_cstr
    jmp .cases
.uci_prefix:
    lea rdi, [suite_res_prefix_uci]
    call write_cstr

.cases:
    mov rax, [suite_cases]
    call print_number

    lea rdi, [suite_res_hits]
    call write_cstr
    mov rax, [suite_hits]
    call print_number

    lea rdi, [suite_res_misses]
    call write_cstr
    mov rax, [suite_cases]
    sub rax, [suite_hits]
    call print_number

    lea rdi, [suite_res_rate]
    call write_cstr
    mov rax, [suite_cases]
    test rax, rax
    jz .rate_zero
    mov rbx, rax
    mov rax, [suite_hits]
    imul rax, 100
    xor rdx, rdx
    div rbx
    call print_number
    jmp .nodes
.rate_zero:
    xor rax, rax
    call print_number

.nodes:
    lea rdi, [suite_res_score]
    call write_cstr
    mov rax, [suite_hits]
    call print_number
    lea rdi, [suite_res_slash]
    call write_cstr
    mov rax, [suite_cases]
    call print_number

    lea rdi, [suite_res_nodes]
    call write_cstr
    mov rax, [suite_nodes_total]
    call print_number

    lea rdi, [suite_res_time]
    call write_cstr
    mov rax, [suite_time_total]
    call print_number

    call print_newline

    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ------------------------------------------------------------
; cmd: suite <file> [depth]
; ------------------------------------------------------------
suite_cmd_suite_file:
    push rbx
    push r12
    push r13
    push r14

    ; token1 = file path
    mov rdi, 5
    call suite_token
    cmp rax, -1
    je .usage
    test rbx, rbx
    jz .usage

    ; copy path
    mov r14, rcx
    lea rdi, [move_buf + rax]
    mov rsi, rbx
    lea rdx, [suite_file_path]
    mov rcx, 512
    call suite_trim_copy
    test rax, rax
    jz .usage

    ; optional token2 = depth
    mov qword [suite_movetime], 0
    mov byte [suite_depth], 0
    mov rdi, r14
    call suite_token
    cmp rax, -1
    je .depth_default
    test rbx, rbx
    jz .depth_default
    mov rdi, rax
    mov rsi, rbx
    call suite_tok_u64
    test rdx, rdx
    jz .depth_default
    cmp rax, 1
    jl .depth_default
    cmp rax, 64
    jg .depth_clamp
    mov [suite_depth], al
    mov r14, rcx
    jmp .depth_ok
.depth_clamp:
    mov byte [suite_depth], 64
    mov r14, rcx
    jmp .depth_ok
.depth_default:
    mov al, [search_depth]
    mov [suite_depth], al
.depth_ok:

    ; optional token3 = movetime_ms
    mov rdi, r14
    call suite_token
    cmp rax, -1
    je .args_done
    test rbx, rbx
    jz .args_done
    mov rdi, rax
    mov rsi, rbx
    call suite_tok_u64
    test rdx, rdx
    jz .args_done
    test rax, rax
    jle .args_done
    mov [suite_movetime], rax
.args_done:

    cmp byte [suite_mode], 0
    jne .hdr_uci
    lea rdi, [suite_hdr_text]
    call write_cstr
    jmp .open
.hdr_uci:
    lea rdi, [suite_hdr_uci]
    call write_cstr

.open:
    call suite_snapshot_save

    ; v benchmark suite rezime Syzygy probe vypiname:
    ; EPD testy netreba mapovat na TB a vyhneme sa nestabilnym vetvam.
    mov dword [uci_syzygy_probe_depth], 0

    mov qword [suite_cases], 0
    mov qword [suite_hits], 0
    mov qword [suite_nodes_total], 0
    mov qword [suite_time_total], 0

    ; open file (O_RDONLY)
    mov rax, SYS_OPEN
    lea rdi, [suite_file_path]
    xor rsi, rsi
    xor rdx, rdx
    syscall
    test rax, rax
    js .open_err
    mov [suite_fd], rax

    ; read all
    xor r12, r12
.read_loop:
    mov rax, SYS_READ
    mov rdi, [suite_fd]
    lea rsi, [suite_file_buf + r12]
    mov rdx, 4096
    syscall
    test rax, rax
    jz .read_done
    js .read_done
    add r12, rax
    cmp r12, 258048
    jl .read_loop
.read_done:
    mov [suite_read_len], r12

    mov rax, SYS_CLOSE
    mov rdi, [suite_fd]
    syscall

    ; iterate lines
    xor r13, r13
.line_next:
    cmp r13, [suite_read_len]
    jge .finish

    mov r14, r13
.find_nl:
    cmp r14, [suite_read_len]
    jge .have_line
    movzx rax, byte [suite_file_buf + r14]
    cmp rax, 10
    je .have_line
    inc r14
    jmp .find_nl

.have_line:
    mov rax, r14
    sub rax, r13
    ; trim CR
    test rax, rax
    jz .advance
    movzx rbx, byte [suite_file_buf + r13 + rax - 1]
    cmp rbx, 13
    jne .copy_line
    dec rax
.copy_line:
    lea rdi, [suite_file_buf]
    add rdi, r13
    mov rsi, rax
    lea rdx, [suite_line_buf]
    mov rcx, 2048
    call suite_trim_copy
    test rax, rax
    jz .advance
    lea rdi, [suite_line_buf]
    mov rsi, rax
    call suite_process_line

.advance:
    mov r13, r14
    cmp r13, [suite_read_len]
    jge .finish
    inc r13
    jmp .line_next

.finish:
    call suite_snapshot_restore
    call suite_print_summary
    jmp .ok

.open_err:
    call suite_snapshot_restore
    cmp byte [suite_mode], 0
    jne .oe_uci
    lea rdi, [suite_err_open_text]
    call write_cstr
    jmp .ok
.oe_uci:
    lea rdi, [suite_err_open_uci]
    call write_cstr
    jmp .ok

.usage:
    cmp byte [suite_mode], 0
    jne .usage_uci
    lea rdi, [suite_usage_text]
    call write_cstr
    jmp .ok
.usage_uci:
    lea rdi, [suite_usage_uci]
    call write_cstr

.ok:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------
; cmd: analyze <single-line EPD/FEN|bm>
; ------------------------------------------------------------
suite_cmd_analyze_inline:
    push rbx
    push r12

    ; najdi start po tokene "analyze"
    mov rdi, 0
    call suite_token
    cmp rax, -1
    je .usage
    mov r12, rcx

    ; preskoc medzery
.skip:
    cmp r12, [move_buf_len]
    jge .usage
    movzx rax, byte [move_buf + r12]
    cmp rax, ' '
    je .s1
    cmp rax, 9
    je .s1
    jmp .have
.s1:
    inc r12
    jmp .skip

.have:
    mov al, [search_depth]
    mov [suite_depth], al

    call suite_snapshot_save

    mov qword [suite_cases], 0
    mov qword [suite_hits], 0
    mov qword [suite_nodes_total], 0
    mov qword [suite_time_total], 0

    mov rdi, move_buf
    add rdi, r12
    mov rsi, [move_buf_len]
    sub rsi, r12
    lea rdx, [suite_line_buf]
    mov rcx, 2048
    call suite_trim_copy
    test rax, rax
    jz .usage_restore

    lea rdi, [suite_line_buf]
    mov rsi, rax
    call suite_process_line

    call suite_snapshot_restore
    call suite_print_summary
    jmp .ok

.usage_restore:
    call suite_snapshot_restore
.usage:
    cmp byte [suite_mode], 0
    jne .u_uci
    lea rdi, [suite_usage_text]
    call write_cstr
    jmp .ok
.u_uci:
    lea rdi, [suite_usage_uci]
    call write_cstr

.ok:
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------
; public entrypoints
; ------------------------------------------------------------
suite_cmd_text:
    mov byte [suite_mode], 0
    ; token0 rozhodne analyze vs suite
    mov rdi, 0
    call suite_token
    cmp rax, -1
    je .ret
    mov rdi, rax
    mov rsi, rbx
    lea rdx, [rel .tok_analyze]
    call suite_tok_eq
    test rax, rax
    jnz .do_analyze
    call suite_cmd_suite_file
    ret
.do_analyze:
    call suite_cmd_analyze_inline
.ret:
    ret
.tok_analyze: db "analyze", 0

suite_cmd_uci:
    mov byte [suite_mode], 1
    ; token0 rozhodne analyze vs suite
    mov rdi, 0
    call suite_token
    cmp rax, -1
    je .ret
    mov rdi, rax
    mov rsi, rbx
    lea rdx, [rel .tok_analyze]
    call suite_tok_eq
    test rax, rax
    jnz .do_analyze
    call suite_cmd_suite_file
    ret
.do_analyze:
    call suite_cmd_analyze_inline
.ret:
    ret
.tok_analyze: db "analyze", 0
