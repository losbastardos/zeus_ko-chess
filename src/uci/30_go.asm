uci_go:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; reset limitov (cisty stav - ziadny sticky mode/times z predchadzajuceho go)
    mov byte [search_limits + 0], 0      ; mode: fixed depth
    movzx rax, byte [search_depth]
    mov byte [search_limits + 1], al     ; default depth
    mov byte [search_limits + 2], 0      ; movestogo 0 = fallback 30 v alloc
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
    mov byte [uci_quit_flag], 0
    call smp_init
    call smp_clear_stop

    ; parsuj argumenty za 'go'
    mov rdi, 2
.go_loop:
    call uci_token
    cmp rax, -1
    je .after_parse
    test rbx, rbx
    jz .after_parse

    mov r15, rax               ; start aktualneho tokenu
    mov r14, rcx               ; index za aktualnym tokenom

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_depth]
    call uci_str_eq
    test rax, rax
    jnz .parse_depth

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_movetime]
    call uci_str_eq
    test rax, rax
    jnz .parse_movetime

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_wtime]
    call uci_str_eq
    test rax, rax
    jnz .parse_wtime

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_btime]
    call uci_str_eq
    test rax, rax
    jnz .parse_btime

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_winc]
    call uci_str_eq
    test rax, rax
    jnz .parse_winc

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_binc]
    call uci_str_eq
    test rax, rax
    jnz .parse_binc

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_movestogo]
    call uci_str_eq
    test rax, rax
    jnz .parse_movestogo

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_threads]
    call uci_str_eq
    test rax, rax
    jnz .parse_threads

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_infinite]
    call uci_str_eq
    test rax, rax
    jnz .set_infinite

    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel uci_str_ponder_kw]
    call uci_str_eq
    test rax, rax
    jnz .set_ponder

    mov rdi, r14
    jmp .go_loop

.parse_depth:
    mov rdi, r14
    call uci_token
    cmp rax, -1
    je .after_parse
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    test rax, rax
    jz .after_parse
    cmp rax, 64
    jle .depth_store
    mov rax, 64
.depth_store:
    mov byte [search_limits + 1], al
    mov rdi, rcx
    jmp .go_loop

.parse_movetime:
    mov rdi, r14
    call uci_token
    cmp rax, -1
    je .after_parse
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    test rax, rax
    jz .after_parse
    mov byte [search_limits + 0], 1
    mov qword [search_limits + 8], rax
    mov qword [search_limits + 56], rax
    mov qword [search_limits + 64], rax
    mov rdi, rcx
    jmp .go_loop

.parse_wtime:
    mov rdi, r14
    call uci_token
    cmp rax, -1
    je .after_parse
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    mov byte [search_limits + 0], 2
    mov qword [search_limits + 16], rax
    mov rdi, rcx
    jmp .go_loop

.parse_btime:
    mov rdi, r14
    call uci_token
    cmp rax, -1
    je .after_parse
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    mov byte [search_limits + 0], 2
    mov qword [search_limits + 24], rax
    mov rdi, rcx
    jmp .go_loop

.parse_winc:
    mov rdi, r14
    call uci_token
    cmp rax, -1
    je .after_parse
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    mov qword [search_limits + 32], rax
    mov rdi, rcx
    jmp .go_loop

.parse_binc:
    mov rdi, r14
    call uci_token
    cmp rax, -1
    je .after_parse
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    mov qword [search_limits + 40], rax
    mov rdi, rcx
    jmp .go_loop

.parse_movestogo:
    mov rdi, r14
    call uci_token
    cmp rax, -1
    je .after_parse
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    test rax, rax
    jz .after_parse
    cmp rax, 255
    jle .mtg_store
    mov rax, 255
.mtg_store:
    mov byte [search_limits + 2], al
    mov rdi, rcx
    jmp .go_loop

.parse_threads:
    mov rdi, r14
    call uci_token
    cmp rax, -1
    je .after_parse
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    cmp rax, 1                   ; clamp: minimum 1 (threads 0 -> 1), parse pokracuje
    jge .th_min_ok
    mov rax, 1
.th_min_ok:
    cmp rax, 8
    jle .th_store
    mov rax, 8
.th_store:
    mov [uci_threads], eax
    mov rdi, rcx
    jmp .go_loop

.set_infinite:
    mov byte [search_limits + 0], 3
    mov byte [search_limits + 1], 64
    mov qword [search_limits + 56], 0
    mov qword [search_limits + 64], 0
    mov rdi, r14
    jmp .go_loop

.set_ponder:
    mov byte [search_limits + 0], 4
    mov byte [uci_ponder], 1
    mov rdi, r14
    jmp .go_loop

.after_parse:
    movzx r12, byte [search_limits + 1]

    ; timed mody bez explicitneho depth skusia hlbsie hladanie
    movzx eax, byte [search_limits + 0]
    test eax, eax
    jz .after_depth_adjust
    movzx eax, byte [search_depth]
    cmp r12, rax
    jne .after_depth_adjust
    mov r12, 64
    mov byte [search_limits + 1], 64

.after_depth_adjust:
    ; zjednoduseny allocation pre time controls
    movzx eax, byte [search_limits + 0]
    cmp eax, 2
    jne .time_start
    call uci_alloc_time

.time_start:
    call uci_now_ms
    mov [search_limits + 48], rax

.search:
    mov byte [uci_move_source], 0
    cmp byte [uci_own_book], 0
    je .no_book
    cmp byte [book_mode], 0
    jne .think_book
    call book_lookup
    test rax, rax
    jz .no_book
    mov byte [uci_move_source], 1
    jmp .do_move
.think_book:
    call book_pick_move
    test rax, rax
    jz .no_book
    mov byte [uci_move_source], 1
    jmp .do_move
.no_book:
    xor r13d, r13d            ; best_move
    xor r14d, r14d            ; best_depth
    mov r15, 1                ; current depth
    mov qword [uci_iter_dur], 0
    mov dword [uci_last_iter_move], 0
    cmp byte [uci_stop_flag], 0
    jne .id_loop              ; stop hned: helperov nespustame
    mov eax, [uci_threads]
    cmp eax, 1
    jle .id_loop
    mov rax, [smp_shared]        ; spawn guard: bez shared stop-flag helperov nespustame
    test rax, rax
    jz .id_loop
    call smp_spawn_helpers

.id_loop:
    cmp byte [uci_stop_flag], 0
    jne .id_done

    cmp r15, r12
    jg .id_done

    ; --- mode 2: soft/hard casove brany pred startom iteracie ---
    ; soft: ak uz minul soft limit, dalsiu iteraciu nezacname
    ; hard: nezacname iteraciu, ktora by s rezervou 2x posledna
    ;       iteracia (typicky rastie 2-2.5x na hlbku) precfuje hard limit
    cmp byte [search_limits + 0], 2
    jne .timegates_ok
    call uci_now_ms
    sub rax, [search_limits + 48]        ; elapsed
    cmp rax, [search_limits + 56]        ; > soft -> koncime
    jg .id_done
    mov rcx, [uci_iter_dur]
    add rcx, rcx
    add rcx, rax
    cmp rcx, [search_limits + 64]        ; elapsed + 2*dur > hard -> koncime
    jg .id_done
.timegates_ok:
    call uci_now_ms
    mov [uci_iter_start], rax

    ; --- ASPIRATION WINDOW: pre depth >= 5 okolo predch. skore ---
    mov dword [asp_use], 0
    mov dword [asp_retry], 0
    cmp r15, 5
    jl .asp_ready
    mov eax, [search_last_score]
    cmp eax, MATE_SCORE - 1000   ; pri mat/hornych skorach plne okno
    jge .asp_ready
    cmp eax, -MATE_SCORE + 1000
    jle .asp_ready
    mov dword [asp_delta], 50
    sub eax, 50
    mov [asp_alpha], eax
    mov eax, [search_last_score]
    add eax, 50
    mov [asp_beta], eax
    mov dword [asp_use], 1
.asp_ready:
    mov rdi, r15
    call search_best_move
    mov [uci_last_iter_move], eax

    cmp byte [uci_stop_flag], 0
    jne .id_done

    test rax, rax
    jz .id_done

    ; --- aspiration retry pri fail-low / fail-high ---
    cmp dword [asp_use], 0
    je .asp_ok
    mov ecx, [search_last_score]
    cmp ecx, [asp_alpha]
    jle .asp_widen_low
    cmp ecx, [asp_beta]
    jge .asp_widen_high
    jmp .asp_ok
.asp_widen_low:
    ; pozor: rax = bestmove z search_best_move, musi prezit do .asp_ok!
    mov edx, [asp_delta]
    shl edx, 2                  ; delta *= 4
    mov [asp_delta], edx
    mov ecx, [asp_alpha]
    sub ecx, edx
    cmp ecx, -INF
    jge .wl_store
    mov ecx, -INF
.wl_store:
    mov [asp_alpha], ecx
    jmp .asp_again
.asp_widen_high:
    mov edx, [asp_delta]
    shl edx, 2
    mov [asp_delta], edx
    mov ecx, [asp_beta]
    add ecx, edx
    cmp ecx, INF
    jle .wh_store
    mov ecx, INF
.wh_store:
    mov [asp_beta], ecx
.asp_again:
    inc dword [asp_retry]
    cmp dword [asp_retry], 4
    jl .asp_ready
    ; po 4 retry berieme posledny vysledok (fail-soft)
.asp_ok:
    mov r13, rax
    mov r14, r15

    ; trvanie iteracie (vratane aspiration retry) pre hard gate
    call uci_now_ms
    sub rax, [uci_iter_start]
    mov [uci_iter_dur], rax

    call uci_now_ms
    sub rax, [search_limits + 48]
    mov rdi, r15
    mov rsi, rax
    mov rdx, r13
    call uci_emit_info

    inc r15
    jmp .id_loop

.id_done:
    call smp_stop_and_reap    ; bezpecne aj bez helperov (child_count=0 -> hned return)
    test r13, r13
    jnz .id_have_best

    ; ak stop prisiel pocas iteracie pred .asp_ok, pouzi posledny tah,
    ; ktory search vratil, aby sme nespustali novy fallback search
    ; s aktivnym uci_stop_flag (ten casto vracia nahodny prvy tah).
    mov eax, [uci_last_iter_move]
    test eax, eax
    jz .id_fallback_depth1
    mov r13d, eax
    mov r14, r15
    call uci_now_ms
    sub rax, [search_limits + 48]
    mov rdi, r14
    mov rsi, rax
    mov rdx, r13
    call uci_emit_info
    jmp .id_have_best

.id_fallback_depth1:
    mov rdi, 1
    call search_best_move
    mov r13, rax
    mov r14, 1
    call uci_now_ms
    sub rax, [search_limits + 48]
    mov rdi, r14
    mov rsi, rax
    mov rdx, r13
    call uci_emit_info

.id_have_best:
    mov rax, r13
    call uci_sanitize_best    ; poistka proti nelegalnemu bestmove

.do_move:
    mov r12, rax

    ; viditelna diagnostika: zdroj bestmove (book/search)
    cmp byte [uci_move_source], 1
    jne .src_search
    lea rdi, [uci_info_src_book]
    mov rdx, uci_info_src_book_len
    call write_str
    lea rdi, [uci_log_src_prefix]
    mov esi, uci_log_src_prefix_len
    call uci_log_str
    lea rdi, [uci_src_book_str]
    mov esi, uci_src_book_len
    call uci_log_str
    lea rdi, [msg_newline]
    mov esi, 1
    call uci_log_str
    jmp .src_done
.src_search:
    lea rdi, [uci_info_src_search]
    mov rdx, uci_info_src_search_len
    call write_str
    lea rdi, [uci_log_src_prefix]
    mov esi, uci_log_src_prefix_len
    call uci_log_str
    lea rdi, [uci_src_search_str]
    mov esi, uci_src_search_len
    call uci_log_str
    lea rdi, [msg_newline]
    mov esi, 1
    call uci_log_str
.src_done:

    ; --- log "<< bestmove <tah>" (0000 ak nulty tah) ---
    test r12, r12
    jz .log_bm_null
    mov rax, r12
    and rax, 0x3F
    call square_to_str
    mov ax, [square_str_buf]
    mov [uci_log_move_buf], ax
    mov rax, r12
    shr rax, 6
    and rax, 0x3F
    call square_to_str
    mov ax, [square_str_buf]
    mov [uci_log_move_buf + 2], ax
    mov r13d, 4                 ; r13 uz je mrtvy (best move je v r12)
    mov rax, r12
    shr rax, 12
    cmp rax, FLAG_PROMO_Q
    jb .log_bm_go
    cmp rax, FLAG_PROMO_N
    ja .log_bm_go
    lea rdx, [pv_promo_chars]
    movzx edx, byte [rdx + rax - 1]
    mov [uci_log_move_buf + 4], dl
    mov r13d, 5
.log_bm_go:
    lea rdi, [uci_log_bm_prefix]
    mov esi, uci_log_bm_prefix_len
    call uci_log_str
    lea rdi, [uci_log_move_buf]
    mov esi, r13d
    call uci_log_str
    lea rdi, [msg_newline]
    mov esi, 1
    call uci_log_str
    jmp .log_bm_done
.log_bm_null:
    lea rdi, [uci_log_bm_null]
    mov esi, uci_log_bm_null_len
    call uci_log_str
.log_bm_done:

    lea rdi, [uci_bestmove]
    mov rdx, uci_bestmove_len
    call write_str

    ; nulty tah (mat/pat): UCI konvencia "bestmove 0000"
    test r12, r12
    jnz .bm_have_move
    lea rdi, [uci_str_0000]
    mov rdx, 4
    call write_str
    jmp .bm_no_promo
.bm_have_move:

    mov rax, r12
    and rax, 0x3F
    call square_to_str
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, square_str_buf
    mov rdx, 2
    syscall

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
    jb .bm_no_promo
    cmp rax, FLAG_PROMO_N
    ja .bm_no_promo
    lea rcx, [pv_promo_chars]
    movzx eax, byte [rcx + rax - 1]
    mov [pv_char_buf], al
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [pv_char_buf]
    mov rdx, 1
    syscall
.bm_no_promo:

    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    mov byte [uci_ponder], 0

    ; ak prislo 'quit' pocas searchu, proces konci hned po bestmove
    cmp byte [uci_quit_flag], 0
    je .no_quit_exit
    mov rax, SYS_EXIT
    xor edi, edi
    syscall
.no_quit_exit:

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; uci_parse_int - prevedie token na cislo
; Vstup: rdi = token start, rsi = token len
; Vystup: rax = cislo, 0 ak chyba
; ============================================================
