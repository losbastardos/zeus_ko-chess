write_str:
    push rax
    mov rax, SYS_WRITE
    mov rsi, rdi
    mov rdi, STDOUT
    syscall
    pop rax
    ret

; ============================================================
; write_cstr - vypise null-terminated C-string
; ============================================================
write_cstr:
    push rbx
    push rcx
    mov rbx, rdi
    xor rcx, rcx
.len_loop:
    cmp byte [rbx + rcx], 0
    je .print
    inc rcx
    jmp .len_loop
.print:
    mov rdx, rcx
    call write_str
    pop rcx
    pop rbx
    ret

; ============================================================
; uci_log_str - zapise retazec do uci_debug.log (best-effort)
; Vstup: rdi = ptr, rsi = len. Vsetky chyby ticho ignorovane.
; Lazy open v cwd pri prvom volani; fd=-1 -> nikdy viac neotvarame.
; ============================================================
uci_log_str:
    push rbx
    push r12
    push r13
    mov r12, rdi              ; ptr
    mov r13, rsi              ; len
    mov rbx, [uci_log_fd]
    cmp rbx, -2
    jne .have_fd
    mov rax, SYS_OPEN
    lea rdi, [uci_log_name]
    mov esi, O_WRONLY | O_CREAT | O_APPEND
    mov edx, 420              ; 0644
    syscall
    test rax, rax
    js .open_failed
    mov rbx, rax
    mov [uci_log_fd], rax
    jmp .write
.open_failed:
    mov qword [uci_log_fd], -1
    ; jednorazovo viditelne oznamime do stdout (GUI Engine output)
    mov eax, SYS_WRITE
    mov edi, 1
    lea rsi, [uci_log_fail]
    mov edx, uci_log_fail_len
    syscall
    jmp .done
.have_fd:
    cmp rbx, -1
    je .done
.write:
    mov rax, SYS_WRITE
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    syscall
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; uci_token - najde dalsi token v move_buf
; Vstup:  rdi = start index
; Vystup: rax = start index tokenu, rbx = dlzka tokenu,
;         rcx = index prveho znaku za tokenom (alebo -1 ak koniec)
; ============================================================
uci_token:
    push r12
    push r13
    mov r12, rdi
    mov r13, [move_buf_len]

    ; preskoc whitespace
.skip_ws:
    cmp r12, r13
    jge .end
    movzx rax, byte [move_buf + r12]
    cmp rax, ' '
    je .ws_next
    cmp rax, 9
    je .ws_next
    cmp rax, 10
    je .ws_next
    cmp rax, 13
    je .ws_next
    jmp .find_end
.ws_next:
    inc r12
    jmp .skip_ws

.find_end:
    mov r8, r12
.find_loop:
    cmp r8, r13
    jge .end_found
    movzx rax, byte [move_buf + r8]
    cmp rax, ' '
    je .end_found
    cmp rax, 9
    je .end_found
    cmp rax, 10
    je .end_found
    cmp rax, 13
    je .end_found
    inc r8
    jmp .find_loop

.end_found:
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

; ============================================================
; uci_str_eq - porovna token s C-stringom
; Vstup: rdi = token start, rsi = token len, rdx = C-string
; Vystup: rax = 1 ak rovnake, inak 0
; ============================================================
uci_str_eq:
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
    jge .check_term
    movzx rax, byte [move_buf + r12 + rcx]
    movzx rbx, byte [r14 + rcx]
    cmp rax, rbx
    jne .no
    inc rcx
    jmp .loop
.check_term:
    movzx rax, byte [r14 + rcx]
    test rax, rax
    jz .yes
.no:
    xor rax, rax
    jmp .done
.yes:
    mov rax, 1
.done:
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

; ============================================================
; uci_parse_move - prevedie 4-znakovy token na 16-bitovy tah
; Vstup: rdi = token start, rsi = token len
; Vystup: rax = tah, 0 ak chyba
; ============================================================
uci_parse_move:
    push rbx
    cmp rsi, 4
    je .len_ok
    cmp rsi, 5
    jne .error
.len_ok:

    movzx rax, byte [move_buf + rdi]
    sub rax, 'a'
    cmp rax, 7
    ja .error
    mov rbx, rax

    movzx rax, byte [move_buf + rdi + 1]
    sub rax, '1'
    cmp rax, 7
    ja .error
    shl rax, 3
    add rbx, rax

    movzx rax, byte [move_buf + rdi + 2]
    sub rax, 'a'
    cmp rax, 7
    ja .error
    mov rcx, rax

    movzx rax, byte [move_buf + rdi + 3]
    sub rax, '1'
    cmp rax, 7
    ja .error
    shl rax, 3
    add rcx, rax

    shl rcx, 6
    or rbx, rcx

    ; promocia (5. znak: q/r/b/n)
    cmp rsi, 5
    jne .raw
    movzx rax, byte [move_buf + rdi + 4]
    cmp rax, 'q'
    je .promo_q
    cmp rax, 'r'
    je .promo_r
    cmp rax, 'b'
    je .promo_b
    cmp rax, 'n'
    je .promo_n
    jmp .error
.promo_q:
    or rbx, 1 << 12
    jmp .raw
.promo_r:
    or rbx, 2 << 12
    jmp .raw
.promo_b:
    or rbx, 3 << 12
    jmp .raw
.promo_n:
    or rbx, 4 << 12
.raw:
    mov rax, rbx
    jmp .done

.error:
    xor rax, rax
.done:
    pop rbx
    ret

; ============================================================
; uci_apply_moves - aplikuje postupnost tahov za 'moves'
; Vstup: rdi = index prveho tokenu po 'moves'
; ============================================================
uci_apply_moves:
    push rbx
    push r12
    push r13
    push r14
    mov rax, rdi
    mov [uci_next_idx], rax

    ; --- PGN: spočítaj ťahy v tomto príkaze (GUI posiela celú históriu) ---
    ; takeback / kratšia história -> uzavri PGN sekciu a zaznamenaj znovu
    mov r12, rdi              ; cursor
    xor r13, r13              ; počet tokenov (uci_token zachová r12-r15)
.pgn_count_loop:
    mov rdi, r12
    call uci_token
    cmp rax, -1
    je .pgn_count_done
    test rbx, rbx
    jz .pgn_count_done
    inc r13
    mov r12, rcx
    jmp .pgn_count_loop
.pgn_count_done:
    cmp r13, [uci_pgn_ply]
    jae .pgn_no_reset
    call pgn_new_game
    mov qword [uci_pgn_ply], 0
.pgn_no_reset:
    mov qword [uci_pgn_idx], 0

.move_loop:
    mov rdi, [uci_next_idx]
    call uci_token
    cmp rax, -1
    je .done
    test rbx, rbx
    jz .done

    mov r13, rax          ; start tokenu
    mov r14, rbx          ; dlzka tokenu
    mov [uci_next_idx], rcx

    ; generuj tahy pre aktualnu poziciu az teraz
    call generate_all_moves

    mov rdi, r13
    mov rsi, r14
    call uci_parse_move
    test rax, rax
    jz .done

    mov rbx, rax
    test rax, 0xF000
    jz .find_normal

    ; promocia - hladaj presnu zhodu vratane flags
    xor rcx, rcx
    movzx rdx, word [move_count]
    lea rsi, [move_list]
.find_promo:
    cmp rcx, rdx
    jge .done
    movzx rax, word [rsi + rcx*2]
    cmp rax, rbx
    je .apply
    inc rcx
    jmp .find_promo

.find_normal:
    mov rax, rbx
    call find_move
    test rax, rax
    jz .done

.apply:
    ; PGN: zaznamenaj len nové ťahy (rax = nájdený ťah z move_list, s flags)
    mov rcx, [uci_pgn_idx]
    cmp rcx, [uci_pgn_ply]
    jb .pgn_no_san
    push rax
    call pgn_san_begin      ; SAN jadro (move_list ešte obsahuje legálne ťahy)
    pop rax
.pgn_no_san:
    call apply_move
    call update_position_state
    call compute_hash
    call record_hash
    mov rax, [uci_pgn_idx]
    cmp rax, [uci_pgn_ply]
    jb .pgn_skip
    call pgn_write_move     ; append do games.pgn (real-time)
    inc qword [uci_pgn_ply]
.pgn_skip:
    inc qword [uci_pgn_idx]
    jmp .move_loop

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; uci_parse_fen - prečíta 6 FEN tokenov, zloží reťazec a zavolá parser
; Vstup: rdi = index prvého tokenu za 'fen'
; Vystup: rax = index tokenu za FEN políčkami (alebo -1 ak chyba)
; ============================================================
uci_parse_fen:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi              ; aktuálny index tokenu
    lea r14, [fen_buf]        ; cieľový buffer
    mov r13, 6                ; počet FEN políčok

.field_loop:
    mov rdi, r12
    call uci_token
    cmp rax, -1
    je .error
    test rbx, rbx
    jz .error

    mov r15, rcx              ; uloz index dalsieho tokenu
    mov r12, rax              ; zaciatok tokenu
    mov rcx, rbx              ; dlzka tokenu

.copy_loop:
    cmp rcx, 0
    jle .copy_done
    movzx rax, byte [move_buf + r12]
    mov [r14], al
    inc r14
    inc r12
    dec rcx
    jmp .copy_loop

.copy_done:
    dec r13
    jz .all_fields
    mov byte [r14], ' '
    inc r14
    mov r12, r15
    jmp .field_loop

.all_fields:
    mov byte [r14], 0         ; null terminate

    lea rdi, [fen_buf]
    call parse_fen_string
    test rax, rax
    jnz .error

    mov rax, r15              ; vráti index za posledným FEN tokenom
    jmp .done

.error:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; uci_position - spracuje 'position' prikaz
; ============================================================
uci_position:
    push rbx
    push r12

    ; dalsi token po 'position'
    mov rdi, 8
    call uci_token
    cmp rax, -1
    je .done

    mov rdi, rax
    mov rsi, rbx
    mov r12, rax              ; uloz zaciatok tokenu (str_eq prepise rax)
    lea rdx, [rel .str_startpos]
    call uci_str_eq
    test rax, rax
    jnz .startpos

    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_fen]
    call uci_str_eq
    test rax, rax
    jnz .fen

    ; inak ignorujeme
    jmp .done

.startpos:
    mov [uci_next_idx], rcx

    call init_board
    call init_hash_history
    call record_hash
    jmp .find_moves

.fen:
    mov rdi, rcx
    call uci_parse_fen
    cmp rax, -1
    je .done
    mov [uci_next_idx], rax

.find_moves:
    ; hladaj 'moves'
.start_loop:
    mov rdi, [uci_next_idx]
    call uci_token
    cmp rax, -1
    je .done
    test rbx, rbx
    jz .done

    mov rdi, rax
    mov rsi, rbx
    lea rdx, [rel .str_moves]
    call uci_str_eq
    test rax, rax
    jz .next_token

    mov rdi, rcx
    call uci_apply_moves
    jmp .done

.next_token:
    mov [uci_next_idx], rcx
    jmp .start_loop

.done:
    ; UCI position meni board/hash mimo make_move delty; pri NNUE2 preto
    ; po kompletnom spracovani pozicie obnov accumulator explicitne.
    cmp byte [eval_mode], 2
    jne .done_ret
    cmp byte [nnue2_ready], 1
    jne .done_ret
    call nnue2_refresh

.done_ret:
    pop r12
    pop rbx
    ret

.str_startpos: db "startpos", 0
.str_fen:      db "fen", 0
.str_moves:    db "moves", 0

; ============================================================
; uci_setoption - spracuje 'setoption name <id> value <x>'
; Vstup: rdi = index tokenu za 'setoption'
; ============================================================
uci_setoption:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi

    ; ocakavame 'name'
    mov rdi, r12
    call uci_token
    cmp rax, -1
    je .done
    test rbx, rbx
    jz .done
    mov r12, rcx

    ; id optionu
    mov rdi, r12
    call uci_token
    cmp rax, -1
    je .done
    test rbx, rbx
    jz .done
    mov r13, rax          ; start id
    mov r14, rbx          ; dlzka id
    mov r12, rcx

    ; ocakavame 'value' (povinne podla UCI); ak chyba, tolerancne
    ; pouzijeme nasledujuci token rovno ako hodnotu (napr. GUI, ktore
    ; 'value' nevysiela — inak by sa option mlcky nastavil na 0/false)
    mov rdi, r12
    call uci_token
    cmp rax, -1
    je .done
    test rbx, rbx
    jz .done

    mov rdi, rax
    mov rsi, rbx
    lea rdx, [rel .str_value]
    mov r15, rax          ; start tokenu (hodnota, ak 'value' chyba)
    push rcx
    push rbx
    call uci_str_eq
    pop rbx
    pop rcx
    test rax, rax
    jnz .value_keyword

    ; 'value' chyba: tento token JE hodnota (rbx = dlzka, rcx = zvysok)
    jmp .value_ready

.value_keyword:
    mov r12, rcx

    ; hodnota
    mov rdi, r12
    call uci_token
    cmp rax, -1
    je .value_missing
    test rbx, rbx
    jz .value_missing
    mov r15, rax          ; start hodnoty
    jmp .value_ready

.value_missing:
    mov r15, [move_buf_len] ; prazdna hodnota (napr. SyzygyPath reset)
    xor ebx, ebx

.value_ready:
    ; rbx = dlzka hodnoty (0 pri prazdnej hodnote)

    ; porovnaj id
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel .str_hash]
    call uci_str_eq
    test rax, rax
    jnz .opt_hash

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel .str_ownbook]
    call uci_str_eq
    test rax, rax
    jnz .opt_ownbook

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel .str_ponder]
    call uci_str_eq
    test rax, rax
    jnz .opt_ponder

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel .str_syzygypath]
    call uci_str_eq
    test rax, rax
    jnz .opt_syzygypath

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel .str_syzygyprobedepth]
    call uci_str_eq
    test rax, rax
    jnz .opt_syzygyprobedepth

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel .str_moveoverhead]
    call uci_str_eq
    test rax, rax
    jnz .opt_moveoverhead

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel .str_evalmode]
    call uci_str_eq
    test rax, rax
    jnz .opt_evalmode

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel .str_threads]
    call uci_str_eq
    test rax, rax
    jnz .opt_threads

    jmp .done

.opt_hash:
    mov rdi, r15
    mov rsi, rbx
    call uci_parse_int
    test eax, eax
    jg .hash_min_ok
    mov eax, 16
.hash_min_ok:
    cmp eax, 1024
    jle .hash_max_ok
    mov eax, 1024
.hash_max_ok:
    mov [uci_hash_size], eax
    mov edi, eax
    call tt_init
    jmp .done

.opt_ownbook:
    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel .str_true]
    call uci_str_eq
    test rax, rax
    jz .opt_ownbook_false
    mov byte [uci_own_book], 1
    jmp .done
.opt_ownbook_false:
    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel .str_false]
    call uci_str_eq
    test rax, rax
    jz .done
    mov byte [uci_own_book], 0
    jmp .done

.opt_ponder:
    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel .str_true]
    call uci_str_eq
    test rax, rax
    jz .opt_ponder_false
    mov byte [uci_ponder], 1
    jmp .done
.opt_ponder_false:
    mov rdi, r15
    mov rsi, rbx
    lea rdx, [rel .str_false]
    call uci_str_eq
    test rax, rax
    jz .done
    mov byte [uci_ponder], 0
    jmp .done

.opt_syzygypath:
    ; SyzygyPath: ber celu hodnotu az do konca riadku (mozu byt medzery v ceste)
    ; r15 = start prveho tokenu hodnoty; [move_buf_len] = koniec vstupneho riadku
    mov rcx, [move_buf_len]
    cmp r15, rcx
    jae .tb_clear
    sub rcx, r15
    jmp .tb_trim_tail

.tb_clear:
    lea rdi, [tb_path]
    mov byte [rdi], 0
    mov qword [tb_path_len], 0
    call tb_init
    jmp .done

.tb_trim_tail:
    test rcx, rcx
    jz .tb_copy_ready
    movzx eax, byte [move_buf + r15 + rcx - 1]
    cmp al, ' '
    je .tb_trim_dec
    cmp al, 9
    je .tb_trim_dec
    cmp al, 10
    je .tb_trim_dec
    cmp al, 13
    je .tb_trim_dec
    jmp .tb_copy_ready
.tb_trim_dec:
    dec rcx
    jmp .tb_trim_tail

.tb_copy_ready:
    ; specialna hodnota "<empty>" vypne TB cestu
    cmp rcx, 7
    jne .tb_len_cap
    movzx eax, byte [move_buf + r15 + 0]
    cmp al, '<'
    jne .tb_len_cap
    movzx eax, byte [move_buf + r15 + 1]
    cmp al, 'e'
    jne .tb_len_cap
    movzx eax, byte [move_buf + r15 + 2]
    cmp al, 'm'
    jne .tb_len_cap
    movzx eax, byte [move_buf + r15 + 3]
    cmp al, 'p'
    jne .tb_len_cap
    movzx eax, byte [move_buf + r15 + 4]
    cmp al, 't'
    jne .tb_len_cap
    movzx eax, byte [move_buf + r15 + 5]
    cmp al, 'y'
    jne .tb_len_cap
    movzx eax, byte [move_buf + r15 + 6]
    cmp al, '>'
    jne .tb_len_cap
    jmp .tb_clear

.tb_len_cap:
    cmp rcx, 255
    jbe .tb_len_ok
    mov rcx, 255            ; bezpecna truncat na max 255 znakov
.tb_len_ok:
    lea rsi, [move_buf + r15] ; zdroj: hodnota v move_buf
    lea rdi, [tb_path]         ; ciel: interny buffer tb.asm
    xor r8, r8
.tb_copy:
    cmp r8, rcx
    jae .tb_term
    movzx eax, byte [rsi + r8]
    mov [rdi + r8], al
    inc r8
    jmp .tb_copy
.tb_term:
    mov byte [rdi + r8], 0
    mov [tb_path_len], r8
    call tb_init            ; rdi ukazuje na ulozenu cestu
    jmp .done

.opt_syzygyprobedepth:
    mov rdi, r15
    mov rsi, rbx
    call uci_parse_int
    test eax, eax
    jge .syzygy_depth_min_ok
    xor eax, eax
.syzygy_depth_min_ok:
    cmp eax, 64
    jle .syzygy_depth_store
    mov eax, 64
.syzygy_depth_store:
    mov [uci_syzygy_probe_depth], eax
    jmp .done

.opt_moveoverhead:
    mov rdi, r15
    mov rsi, rbx
    call uci_parse_int
    test eax, eax
    jl .overhead_min
    cmp eax, 10000
    jle .overhead_store
    mov eax, 10000
.overhead_min:
    xor eax, eax
.overhead_store:
    mov [uci_move_overhead], eax
    jmp .done

.opt_evalmode:
    mov rdi, r15
    mov rsi, rbx
    call uci_parse_int
    test eax, eax
    jge .evalmode_min_ok
    xor eax, eax
.evalmode_min_ok:
    cmp eax, 2
    jle .evalmode_store
    mov eax, 2
.evalmode_store:
    mov [eval_mode], al
    cmp al, 0
    je .done
    ; Runtime prepnutie eval modu: nacitaj model z rovnakej konfiguracie
    ; ako pri starte (nnue_file v chess.ini, fallback default_nnue_file).
    lea rdi, [key_nnue_file]
    lea rsi, [default_nnue_file]
    call config_get
    mov rdi, rax
    cmp byte [eval_mode], 2
    je .evalmode_load_v2
    call nnue_load
    jmp .evalmode_load_done
.evalmode_load_v2:
    call nnue2_load
.evalmode_load_done:
    test eax, eax
    jnz .evalmode_load_fail
    cmp byte [eval_mode], 2
    jne .done
    cmp byte [nnue2_ready], 1
    jne .done
    call nnue2_refresh
    jmp .done

.evalmode_load_fail:
    mov byte [eval_mode], 0
    jmp .done

.opt_threads:
    mov rdi, r15
    mov rsi, rbx
    call uci_parse_int
    cmp eax, 1
    jge .threads_min_ok
    mov eax, 1
.threads_min_ok:
    cmp eax, 8
    jle .threads_store
    mov eax, 8
.threads_store:
    mov [uci_threads], eax
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.str_hash:     db "Hash", 0
.str_value:    db "value", 0
.str_ownbook:  db "OwnBook", 0
.str_ponder:   db "Ponder", 0
.str_syzygypath: db "SyzygyPath", 0
.str_syzygyprobedepth: db "SyzygyProbeDepth", 0
.str_moveoverhead: db "MoveOverhead", 0
.str_evalmode: db "EvalMode", 0
.str_threads: db "Threads", 0
.str_true:     db "true", 0
.str_false:    db "false", 0

uci_str_depth:      db "depth", 0
uci_str_movetime:   db "movetime", 0
uci_str_wtime:      db "wtime", 0
uci_str_btime:      db "btime", 0
uci_str_winc:       db "winc", 0
uci_str_binc:       db "binc", 0
uci_str_movestogo:  db "movestogo", 0
uci_str_threads:    db "threads", 0
uci_str_infinite:   db "infinite", 0
uci_str_ponder_kw:  db "ponder", 0

uci_info_depth: db "info depth ", 0
uci_info_score: db " score cp ", 0
uci_info_nodes: db " nodes ", 0
uci_info_time:  db " time ", 0
uci_info_pv:    db " pv ", 0
uci_minus:      db "-", 0
pv_promo_chars: db "qrbn"
pv_space:       db " "

; ============================================================
; uci_now_ms - monotonic cas v ms
; Vystup: rax = ms
; ============================================================
uci_now_ms:
    push rbx
    push rcx
    push rdx

    mov rax, SYS_CLOCK_GETTIME
    mov rdi, CLOCK_MONOTONIC
    lea rsi, [uci_timespec]
    syscall
    test rax, rax
    js .err

    mov rax, [uci_timespec]      ; sec
    imul rax, 1000
    mov rbx, rax                 ; sec_ms
    mov rax, [uci_timespec + 8]  ; nsec
    mov rcx, 1000000
    xor rdx, rdx
    div rcx
    add rax, rbx
    jmp .done

.err:
    xor rax, rax

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; uci_alloc_time - casovy budget pre mode 2 (time/movestogo + inc, min 50ms)
; Pouziva cas strany na tahu z search_limits; vysledok do +56/+64.
; Volaju uci_go (mode 2) aj search_poll_input (ponderhit).
; ============================================================
uci_alloc_time:
    movzx ecx, byte [side]
    test ecx, ecx
    jz .alloc_white
    mov rax, [search_limits + 24]       ; btime
    mov rcx, [search_limits + 40]       ; binc
    jmp .alloc_common
.alloc_white:
    mov rax, [search_limits + 16]       ; wtime
    mov rcx, [search_limits + 32]       ; winc
.alloc_common:
    movzx edx, byte [search_limits + 2] ; movestogo
    test edx, edx
    jnz .have_mtg
    mov edx, 30
.have_mtg:
    mov r8d, edx
    xor rdx, rdx
    div r8
    add rax, rcx
    test rax, rax
    jnz .alloc_store
    mov rax, 50
.alloc_store:
    ; odcitaj move overhead od soft/hard limitu
    mov r9d, [uci_move_overhead]
    sub rax, r9
    jg .soft_ok
    mov rax, 10
.soft_ok:
    mov [search_limits + 56], rax        ; soft = base - overhead
    mov rcx, rax
    shr rcx, 1
    add rcx, rax
    mov [search_limits + 64], rcx        ; hard = base + base/2
    ret

; ============================================================
; search_poll_input - neblokujuce spracovanie UCI vstupu pocas searchu
; Volane z check_time (search.asm) len kazdych 1024 nodov.
; Obsluzi: stop, ponderhit (len v mode 4), isready, quit.
; Registre: nici caller-saved + rbx/r12/r13 (tie su ulozene).
; ============================================================
search_poll_input:
    push rbx
