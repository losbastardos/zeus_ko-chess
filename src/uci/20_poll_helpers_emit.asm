    push r12
    push r13

    ; a) poll(fd 0, timeout 0): je na stdin pripraveny bajt?
    mov dword [input_pollfd], 0         ; fd = STDIN
    mov word [input_pollfd + 4], POLLIN
    mov word [input_pollfd + 6], 0
    mov rax, SYS_POLL
    lea rdi, [input_pollfd]
    mov esi, 1                          ; nfds
    xor edx, edx                        ; timeout 0
    syscall
    test rax, rax
    jle .done
    test word [input_pollfd + 6], POLLIN
    jz .done

    ; b) nacitaj volne bajty do input_pend
    mov rdx, INPUT_PEND_SIZE
    sub rdx, [input_pend_len]
    jz .done                            ; buffer plny
    mov rax, SYS_READ
    xor edi, edi
    lea rsi, [input_pend]
    add rsi, [input_pend_len]
    syscall
    test rax, rax
    jle .done
    add [input_pend_len], rax

    ; c)-e) spracuj vsetky cele riadky v bufferi
.line_loop:
    mov r12, [input_pend_len]
    lea rbx, [input_pend]
    xor ecx, ecx
.find_nl:
    cmp rcx, r12
    jae .done                           ; ziadny cely riadok - koncime
    cmp byte [rbx + rcx], 10
    je .have_line
    inc rcx
    jmp .find_nl
.have_line:
    mov r13, rcx                        ; index newlineu = raw dlzka riadku

    ; odstran trailing '\r' (CRLF protokol)
    test r13, r13
    jz .dispatch
    cmp byte [rbx + r13 - 1], 13
    jne .dispatch
    dec r13
.dispatch:
    ; case-sensitive porovnanie prikazov
    ; Neznamy prikaz NESMIE byt zahodeny - nechame ho v input_pend
    ; pre uci_loop (inak by pipelined 'position'/'go' pocas searchu
    ; zmizli a GUI by cakalo na bestmove naveky).
    cmp r13, 4
    jne .try_isready
    mov eax, dword [rbx]
    cmp eax, 'stop'
    je .cmd_stop
    cmp eax, 'quit'
    je .cmd_quit
    jmp .keep_line
.try_isready:
    cmp r13, 7
    jne .try_ponderhit
    cmp dword [rbx], 'isre'
    jne .keep_line
    cmp dword [rbx + 3], 'eady'
    jne .keep_line
    jmp .cmd_isready
.try_ponderhit:
    cmp r13, 9
    jne .keep_line
    cmp dword [rbx], 'pond'
    jne .keep_line
    cmp dword [rbx + 4], 'erhi'
    jne .keep_line
    cmp byte [rbx + 8], 't'
    jne .keep_line

    ; --- ponderhit: len v ponder mode prepne na casovany budget ---
    cmp byte [search_limits + 0], 4
    jne .next_line
    mov byte [search_limits + 0], 2
    mov byte [uci_ponder], 0
    call uci_alloc_time
    call uci_now_ms
    mov [search_limits + 48], rax       ; budget odpocitavany od momentu ponderhitu
    jmp .next_line

.cmd_isready:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [uci_ready]                ; "readyok\n"
    mov edx, 8
    syscall
    jmp .next_line

.cmd_stop:
    mov byte [uci_stop_flag], 1
    call smp_signal_stop      ; zastav aj helper procesy
    jmp .next_line

.cmd_quit:
    mov byte [uci_quit_flag], 1
    ; v infinite/ponder mode musi quit zastavit aj search (inak by visel naveky)
    cmp byte [search_limits + 0], 3
    je .quit_stop
    cmp byte [search_limits + 0], 4
    je .quit_stop
    jmp .next_line
.quit_stop:
    mov byte [uci_stop_flag], 1
    call smp_signal_stop      ; zastav aj helper procesy
    jmp .next_line

.next_line:
    ; vyhod riadok z input_pend (r13+1 bajtov z lava)
    mov rax, r12
    sub rax, r13
    dec rax                             ; nova dlzka = len - nl - 1
    xor ecx, ecx
    lea rsi, [rbx + r13 + 1]            ; zdroj za newlineom
.shift:
    cmp rcx, rax
    jae .shift_done
    mov dl, [rsi + rcx]
    mov [rbx + rcx], dl
    inc rcx
    jmp .shift
.shift_done:
    mov [input_pend_len], rax
    ; po 'stop' zvysne prikazy nechame na uci_loop (bestmove pride skor)
    cmp byte [uci_stop_flag], 0
    jne .done
    jmp .line_loop

.keep_line:
    ; neznamy riadok zostava v input_pend - uci_loop si ho precita po searchu
    jmp .done

.done:
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; uci_sanitize_best - poistka: bestmove musi byt legalny tah
; Vstup:  rax = kandidat (16-bit tah, 0 = mat/pat)
; Vystup: rax = kandidat ak sa najde v legalnom move_liste,
;         inak prvy legalny tah (alebo 0 ak ziaden neexistuje)
; Pozn.: generate_all_moves nici r12-r15, preto ich ukladame.
; ============================================================
uci_sanitize_best:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rax
    test rax, rax
    jz .ret                       ; 0 = mat/pat, nechaj 0000
    call generate_all_moves       ; board je na root pozicii (search skoncil)
    movzx r15, word [move_count]
    lea rsi, [move_list]
    xor rcx, rcx
.scan:
    cmp rcx, r15
    jge .not_found
    movzx eax, word [rsi + rcx*2]
    cmp ax, r14w
    je .found
    inc rcx
    jmp .scan
.found:
    mov rax, r14
    jmp .ret
.not_found:
    ; varovanie do uci_debug.log + fallback na prvy legalny tah
    lea rdi, [uci_log_bad_bm]
    mov esi, uci_log_bad_bm_len
    call uci_log_str
    test r15, r15
    jz .zero
    movzx rax, word [move_list]
    jmp .ret
.zero:
    xor rax, rax
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; uci_print_signed_number - vypise signed cislo z rax
; ============================================================
global uci_print_signed_number
global uci_print_move_token, uci_emit_fen
uci_print_signed_number:
    test rax, rax
    jns .pos
    push rax
    lea rdi, [uci_minus]
    mov rdx, 1
    call write_str
    pop rax
    neg rax
.pos:
    call print_number
    ret

; ============================================================
; extract_pv - vytlaci celu PV z TT (oddelenie medzerami)
; Vstup: rdi = prvy tah (root best move)
; Pozor: volat az po skonceni searchu (pouziva make/unmake na
; realnej pozicii, undo_stack musi byt prazdny)
; ============================================================
extract_pv:
    push rbx
    push r12

    xor rbx, rbx            ; index do pv_moves
.loop:
    cmp rbx, [pv_moves_len]
    jge .done
    lea rax, [pv_moves]
    movzx r12, word [rax + rbx*2]

    ; vytlac "from"
    mov rax, r12
    and rax, 0x3F
    call square_to_str
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, square_str_buf
    mov rdx, 2
    syscall

    ; vytlac "to"
    mov rax, r12
    shr rax, 6
    and rax, 0x3F
    call square_to_str
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, square_str_buf
    mov rdx, 2
    syscall

    ; promocny znak (flags 1-4 = q r b n)
    mov rax, r12
    shr rax, 12
    cmp rax, FLAG_PROMO_Q
    jb .no_promo
    cmp rax, FLAG_PROMO_N
    ja .no_promo
    lea rcx, [pv_promo_chars]
    movzx eax, byte [rcx + rax - 1]
    mov [pv_char_buf], al
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [pv_char_buf]
    mov rdx, 1
    syscall
.no_promo:

    ; medzera
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [pv_space]
    mov rdx, 1
    syscall

    inc rbx
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; uci_print_move_token - vypise tah v tvare e2e4/e7e8q bez medzery
; Vstup: rax (spodnych 16 bitov = tah)
; ============================================================
uci_print_move_token:
    push rbx

    mov bx, ax

    movzx rax, bx
    and rax, 0x3F
    call square_to_str
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, square_str_buf
    mov rdx, 2
    syscall

    movzx rax, bx
    shr rax, 6
    and rax, 0x3F
    call square_to_str
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, square_str_buf
    mov rdx, 2
    syscall

    movzx eax, bx
    shr eax, 12
    cmp eax, FLAG_PROMO_Q
    jb .done
    cmp eax, FLAG_PROMO_N
    ja .done
    lea rcx, [pv_promo_chars]
    movzx eax, byte [rcx + rax - 1]
    mov [pv_char_buf], al
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [pv_char_buf]
    mov rdx, 1
    syscall

.done:
    pop rbx
    ret

; ============================================================
; uci_write_char - vypise 1 znak na stdout
; Vstup: al = znak
; ============================================================
uci_write_char:
    mov [pv_char_buf], al
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [pv_char_buf]
    mov rdx, 1
    syscall
    ret

; ============================================================
; uci_piece_to_fen_char - mapovanie engine piece bajtu na FEN znak
; Vstup: ecx = piece (typ|farba)
; Vystup: al = FEN znak
; ============================================================
uci_piece_to_fen_char:
    mov eax, ecx
    and eax, PIECE_MASK
    cmp eax, PAWN
    je .pawn
    cmp eax, KNIGHT
    je .knight
    cmp eax, BISHOP
    je .bishop
    cmp eax, ROOK
    je .rook
    cmp eax, QUEEN
    je .queen
    cmp eax, KING
    je .king
    mov al, '?'
    ret
.pawn:
    mov al, 'p'
    jmp .case
.knight:
    mov al, 'n'
    jmp .case
.bishop:
    mov al, 'b'
    jmp .case
.rook:
    mov al, 'r'
    jmp .case
.queen:
    mov al, 'q'
    jmp .case
.king:
    mov al, 'k'
.case:
    test ecx, COLOR_MASK
    jnz .done
    sub al, 32
.done:
    ret

; ============================================================
; uci_emit_fen - vypise aktualnu poziciu ako FEN (bez newline)
; ============================================================
uci_emit_fen:
    push rbx
    push r12
    push r13
    push r14
    push r15

    lea r15, [board]
    mov r12d, 7
.rank_loop:
    mov r14d, 0
    xor r13d, r13d
.file_loop:
    cmp r13d, 8
    jae .rank_end
    mov eax, r12d
    shl eax, 3
    add eax, r13d
    movzx ecx, byte [r15 + rax]
    test ecx, ecx
    jnz .piece
    inc r14d
    inc r13d
    jmp .file_loop

.piece:
    test r14d, r14d
    jz .emit_piece
    mov eax, r14d
    add al, '0'
    call uci_write_char
    xor r14d, r14d
    ; syscall v uci_write_char znici rcx - znovu nacitaj figurku z board
    mov eax, r12d
    shl eax, 3
    add eax, r13d
    movzx ecx, byte [r15 + rax]
.emit_piece:
    call uci_piece_to_fen_char
    call uci_write_char
    inc r13d
    jmp .file_loop

.rank_end:
    test r14d, r14d
    jz .rank_sep
    mov eax, r14d
    add al, '0'
    call uci_write_char
.rank_sep:
    test r12d, r12d
    jz .after_board
    mov al, '/'
    call uci_write_char
    dec r12d
    jmp .rank_loop

.after_board:
    mov al, ' '
    call uci_write_char
    movzx eax, byte [side]
    cmp eax, WHITE
    jne .side_b
    mov al, 'w'
    jmp .side_emit
.side_b:
    mov al, 'b'
.side_emit:
    call uci_write_char

    mov al, ' '
    call uci_write_char
    movzx ebx, byte [castle]
    test ebx, ebx
    jnz .castle_emit
    mov al, '-'
    call uci_write_char
    jmp .ep_part
.castle_emit:
    test bl, CASTLE_WK
    jz .castle_wq
    mov al, 'K'
    call uci_write_char
.castle_wq:
    test bl, CASTLE_WQ
    jz .castle_bk
    mov al, 'Q'
    call uci_write_char
.castle_bk:
    test bl, CASTLE_BK
    jz .castle_bq
    mov al, 'k'
    call uci_write_char
.castle_bq:
    test bl, CASTLE_BQ
    jz .ep_part
    mov al, 'q'
    call uci_write_char

.ep_part:
    mov al, ' '
    call uci_write_char
    movzx rax, byte [enpassant]
    cmp rax, 255
    jne .ep_sq
    mov al, '-'
    call uci_write_char
    jmp .hm_part
.ep_sq:
    call square_to_str
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, square_str_buf
    mov rdx, 2
    syscall

.hm_part:
    mov al, ' '
    call uci_write_char
    movzx rax, byte [halfmove]
    call print_number
    mov al, ' '
    call uci_write_char
    movzx rax, word [fullmove]
    call print_number

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; uci_nnuewalk_classify_type - urci typ tahu pre log
; Vstup: ax = tah, captured_piece po make
; Vystup: eax = 0 quiet, 1 capture, 2 castle, 3 ep, 4 promo
; ============================================================
uci_nnuewalk_classify_type:
    movzx eax, ax
    shr eax, 12
    cmp eax, FLAG_CASTLE
    je .castle
    cmp eax, FLAG_ENPASSANT
    je .ep
    cmp eax, FLAG_PROMO_Q
    jb .cap
    cmp eax, FLAG_PROMO_N
    jbe .promo
.cap:
    movzx eax, byte [captured_piece]
    test eax, eax
    jz .quiet
    mov eax, 1
    ret
.quiet:
    xor eax, eax
    ret
.castle:
    mov eax, 2
    ret
.ep:
    mov eax, 3
    ret
.promo:
    mov eax, 4
    ret

; ============================================================
; uci_nnuewalk_cmp_evals - porovnaj inkrementalny a refresh eval
; pre STM aj OPP perspektivu v aktualnej pozicii.
; Vystup: eax = 0 OK, 1 mismatch STM, 2 mismatch OPP
; ============================================================
uci_nnuewalk_cmp_evals:
    push rbx
    mov bl, [side]

    call nnue2_fwd
    mov [uci_nnuewalk_eval_inc_stm], eax

    movzx eax, bl
    xor eax, 1
    mov [side], al
    call nnue2_fwd
    mov [uci_nnuewalk_eval_inc_opp], eax

    mov [side], bl
    call nnue2_refresh
    call nnue2_fwd
    mov [uci_nnuewalk_eval_ref_stm], eax

    movzx eax, bl
    xor eax, 1
    mov [side], al
    call nnue2_fwd
    mov [uci_nnuewalk_eval_ref_opp], eax

    mov [side], bl

    mov eax, [uci_nnuewalk_eval_inc_stm]
    cmp eax, [uci_nnuewalk_eval_ref_stm]
    jne .bad_stm
    mov eax, [uci_nnuewalk_eval_inc_opp]
    cmp eax, [uci_nnuewalk_eval_ref_opp]
    jne .bad_opp
    xor eax, eax
    pop rbx
    ret

.bad_stm:
    mov eax, 1
    pop rbx
    ret

.bad_opp:
    mov eax, 2
    pop rbx
    ret

; ============================================================
; uci_emit_info - vypise jeden info riadok
; Vstup: rdi = depth, rsi = time_ms, rdx = best_move
; ============================================================
uci_emit_info:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx

    lea rdi, [uci_info_depth]
    call write_cstr
    mov rax, r12
    call print_number

    lea rdi, [uci_info_score]
    call write_cstr
    movsxd rax, dword [search_last_score]
    call uci_print_signed_number

    lea rdi, [uci_info_nodes]
    call write_cstr
    mov rax, [nodes_searched]
    call print_number

    lea rdi, [uci_info_time]
    call write_cstr
    mov rax, r13
    call print_number

    test rbx, rbx
    jz .nl

    lea rdi, [uci_info_pv]
    call write_cstr

    mov rdi, rbx
    call extract_pv

.nl:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; diagnostika root kandidatov (top 5 podla cp skore)
    mov r10d, [root_trace_count]
    test r10d, r10d
    jz .emit_allprune

    lea rdi, [uci_info_root_top]
    call write_cstr
    xor ebx, ebx
.root_top_loop:
    cmp ebx, r10d
    jge .root_top_nl
    movzx rax, word [root_trace_moves + rbx*2]
    call uci_print_move_token
    lea rdi, [uci_info_root_sep]
    call write_cstr
    movsxd rax, dword [root_trace_scores + rbx*4]
    call uci_print_signed_number
    lea rdi, [uci_info_root_sp]
    call write_cstr
    inc rbx
    jmp .root_top_loop

.root_top_nl:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

.emit_allprune:
    lea rdi, [uci_info_allprune]
    call write_cstr
    mov rax, [prof_allprune]
    call print_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    cmp byte [uci_rootdiag_enabled], 0
    je .done_emit

    xor ebx, ebx
.rootdiag_loop:
    mov r10d, [root_diag_count]
    cmp ebx, r10d
    jge .done_emit

    lea rdi, [uci_info_rootdiag_prefix]
    call write_cstr
    movzx rax, word [root_diag_moves + rbx*2]
    call uci_print_move_token

    lea rdi, [uci_info_rootdiag_score]
    call write_cstr
    movsxd rax, dword [root_diag_scores + rbx*4]
    call uci_print_signed_number

    lea rdi, [uci_info_rootdiag_alpha]
    call write_cstr
    movsxd rax, dword [root_diag_alpha + rbx*4]
    call uci_print_signed_number

    lea rdi, [uci_info_rootdiag_beta]
    call write_cstr
    movsxd rax, dword [root_diag_beta + rbx*4]
    call uci_print_signed_number

    lea rdi, [uci_info_rootdiag_flag]
    call write_cstr
    movzx eax, byte [root_diag_flag + rbx]
    cmp eax, 1
    je .rootdiag_fl
    cmp eax, 2
    je .rootdiag_fh
    lea rdi, [uci_info_rootdiag_flag_ex]
    call write_cstr
    jmp .rootdiag_flag_done
.rootdiag_fl:
    lea rdi, [uci_info_rootdiag_flag_fl]
    call write_cstr
    jmp .rootdiag_flag_done
.rootdiag_fh:
    lea rdi, [uci_info_rootdiag_flag_fh]
    call write_cstr
.rootdiag_flag_done:

    lea rdi, [uci_info_rootdiag_nodes]
    call write_cstr
    mov rax, [root_diag_nodes + rbx*8]
    call print_number

    lea rdi, [uci_info_rootdiag_pv]
    call write_cstr
    movzx rax, word [root_diag_pv0 + rbx*2]
    test rax, rax
    jz .rootdiag_no_pv
    call uci_print_move_token
    jmp .rootdiag_line_done
.rootdiag_no_pv:
    lea rdi, [uci_str_0000]
    mov rdx, 4
    call write_str

.rootdiag_line_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    inc ebx
    jmp .rootdiag_loop

.done_emit:

    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; uci_go - spracuje UCI 'go' (depth/time controls)
; ============================================================
