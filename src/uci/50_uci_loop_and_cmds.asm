uci_loop:
    push rbx
    push r12
    ; startovaci marker do logu - diagnostika: bezi nova binarka + kde loguje
    lea rdi, [uci_log_start]
    mov esi, uci_log_start_len
    call uci_log_str

.loop:
    call uci_read_line
    cmp rax, -1
    je .done

    ; log prijateho riadku: ">> <riadok>"
    lea rdi, [uci_log_prefix_in]
    mov esi, 3
    call uci_log_str
    lea rdi, [move_buf]
    mov rsi, [move_buf_len]
    call uci_log_str
    lea rdi, [msg_newline]
    mov esi, 1
    call uci_log_str

    ; prazdny riadok
    mov r12, [move_buf_len]
    test r12, r12
    jz .loop

    ; prvy token
    mov rdi, 0
    call uci_token
    cmp rax, -1
    je .loop
    mov r12, rax          ; start tokenu (rbx = dlzka, uci_str_eq ho zachova)

    ; 'quit'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_quit]
    call uci_str_eq
    test rax, rax
    jnz .done

    ; 'isready'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_isready]
    call uci_str_eq
    test rax, rax
    jnz .isready

    ; 'uci'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_uci]
    call uci_str_eq
    test rax, rax
    jnz .uci

    ; 'position'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_position]
    call uci_str_eq
    test rax, rax
    jnz .position

    ; 'go'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_go]
    call uci_str_eq
    test rax, rax
    jnz .go

    ; 'setoption'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_setoption]
    call uci_str_eq
    test rax, rax
    jnz .setoption

    ; 'ucinewgame'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_ucinewgame]
    call uci_str_eq
    test rax, rax
    jnz .ucinewgame

    ; 'stop'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_stop]
    call uci_str_eq
    test rax, rax
    jnz .stop

    ; 'ponderhit'
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_ponderhit]
    call uci_str_eq
    test rax, rax
    jnz .ponderhit

    ; 'analyze' (non-standard helper)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_analyze]
    call uci_str_eq
    test rax, rax
    jnz .analyze

    ; 'suite' (non-standard helper)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_suite]
    call uci_str_eq
    test rax, rax
    jnz .suite

    ; 'tbtest' (non-standard helper)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_tbtest]
    call uci_str_eq
    test rax, rax
    jnz .tbtest

    ; 'bbtest' (non-standard helper, bitboard scaffold validation)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_bbtest]
    call uci_str_eq
    test rax, rax
    jnz .bbtest

    ; 'ecotest' (non-standard helper: ECO kod + nazov otvorenia)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_ecotest]
    call uci_str_eq
    test rax, rax
    jnz .ecotest

    ; 'list' (non-standard helper: legalne tahy aktualnej pozicie)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_list]
    call uci_str_eq
    test rax, rax
    jnz .list

    ; 'hashtest' (non-standard helper: make/unmake hash konzistencia)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_hashtest]
    call uci_str_eq
    test rax, rax
    jnz .hashtest

    ; 'eval' (non-standard helper: cisty static eval bez searchu)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_eval]
    call uci_str_eq
    test rax, rax
    jnz .eval

    ; 'evalstate' (non-standard helper: NNUE acc stav + inc/ref eval)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_evalstate]
    call uci_str_eq
    test rax, rax
    jnz .evalstate

    ; 'evaldiff' (non-standard helper: static diferencial list-path vs scan-path)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_evaldiff]
    call uci_str_eq
    test rax, rax
    jnz .evaldiff

    ; 'rootdiag' (non-standard helper: zapne detailny root log)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_rootdiag]
    call uci_str_eq
    test rax, rax
    jnz .rootdiag

    ; 'nnuewalk' (non-standard helper: NNUE acc inkremental vs refresh)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_nnuewalk]
    call uci_str_eq
    test rax, rax
    jnz .nnuewalk

    ; 'halfkpdump' (non-standard helper: HalfKP index dump, p0=STM, p1=OPP)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_halfkpdump]
    call uci_str_eq
    test rax, rax
    jnz .halfkpdump

    ; 'perft' (non-standard helper: perft N na aktualnej pozicii)
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rel .str_perft]
    call uci_str_eq
    test rax, rax
    jnz .perft

    ; neznamy prikaz - vypiseme len ak nie je prazdny
    lea rdi, [uci_unknown]
    call write_cstr
    jmp .loop

.ecotest:
    lea rdi, [uci_eco_prefix]
    call write_cstr
    call eco_test_print
    jmp .loop

.list:
    call generate_all_moves
    call print_move_list
    jmp .loop

.perft:
    ; perft N - N je token za slovom "perft" (offset 5; ws sa preskoci)
    mov rdi, 5
    call uci_token
    cmp rax, -1
    je .perft_default
    mov rdi, rax
    mov rsi, rbx
    call uci_parse_int
    test rax, rax
    jg .perft_cap
.perft_default:
    mov eax, 1
.perft_cap:
    cmp rax, 10
    jle .perft_run
    mov eax, 10
.perft_run:
    mov rdi, rax
    call perft
    call print_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.eval:
    ; evaluate vracia skore z pohladu bieleho; dopocteme aj STM perspektivu
    call evaluate
    mov dword [uci_eval_white_tmp], eax
    mov dword [uci_eval_stm_tmp], eax
    movzx eax, byte [side]
    cmp eax, WHITE
    je .eval_emit
    mov eax, [uci_eval_stm_tmp]
    neg eax
    mov [uci_eval_stm_tmp], eax

.eval_emit:
    lea rdi, [uci_info_eval_white]
    call write_cstr
    movsxd rax, dword [uci_eval_white_tmp]
    call uci_print_signed_number
    lea rdi, [uci_info_eval_stm]
    call write_cstr
    movsxd rax, dword [uci_eval_stm_tmp]
    call uci_print_signed_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.evalstate:
    lea rdi, [uci_info_evalstate_prefix]
    call write_cstr
    movzx rax, byte [side]
    call print_number

    lea rdi, [uci_info_evalstate_valid]
    call write_cstr
    movzx rax, byte [nnue_acc_valid]
    call print_number

    lea rdi, [uci_info_evalstate_match]
    call write_cstr
    xor eax, eax
    cmp byte [nnue_acc_valid], 1
    jne .evalstate_match_emit
    mov rax, [nnue_acc_hash]
    cmp rax, [position_hash]
    jne .evalstate_match_emit
    mov eax, 1
.evalstate_match_emit:
    call print_number

    lea rdi, [uci_info_evalstate_inc]
    call write_cstr
    cmp byte [nnue2_ready], 1
    jne .evalstate_inc_zero
    call nnue2_fwd
    movsxd rax, eax
    call uci_print_signed_number
    jmp .evalstate_ref
.evalstate_inc_zero:
    xor eax, eax
    call uci_print_signed_number

.evalstate_ref:
    lea rdi, [uci_info_evalstate_ref]
    call write_cstr
    cmp byte [nnue2_ready], 1
    jne .evalstate_ref_zero
    call nnue2_refresh
    call nnue2_fwd
    movsxd rax, eax
    call uci_print_signed_number
    jmp .evalstate_done
.evalstate_ref_zero:
    xor eax, eax
    call uci_print_signed_number

.evalstate_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.evaldiff:
    ; uloz a priprav list-path stav z aktualnej sachovnice
    mov al, [pl_dirty]
    mov [uci_evaldiff_saved_dirty], al
    call pl_rebuild_from_board
    mov byte [pl_dirty], 0

    ; list-path evaluate
    call evaluate
    mov [uci_evaldiff_list_score], eax
    mov eax, [eval_dbg_mg]
    mov [uci_evaldiff_list_mg], eax
    mov eax, [eval_dbg_eg]
    mov [uci_evaldiff_list_eg], eax
    mov eax, [eval_dbg_phase]
    mov [uci_evaldiff_list_phase], eax
    mov eax, [eval_dbg_wk]
    mov [uci_evaldiff_list_wk], eax
    mov eax, [eval_dbg_bk]
    mov [uci_evaldiff_list_bk], eax
    mov eax, [eval_dbg_trop_w]
    mov [uci_evaldiff_list_tropw], eax
    mov eax, [eval_dbg_trop_b]
    mov [uci_evaldiff_list_tropb], eax

    ; scan-path evaluate
    mov byte [pl_dirty], 1
    call evaluate
    mov [uci_evaldiff_scan_score], eax
    mov eax, [eval_dbg_mg]
    mov [uci_evaldiff_scan_mg], eax
    mov eax, [eval_dbg_eg]
    mov [uci_evaldiff_scan_eg], eax
    mov eax, [eval_dbg_phase]
    mov [uci_evaldiff_scan_phase], eax
    mov eax, [eval_dbg_wk]
    mov [uci_evaldiff_scan_wk], eax
    mov eax, [eval_dbg_bk]
    mov [uci_evaldiff_scan_bk], eax
    mov eax, [eval_dbg_trop_w]
    mov [uci_evaldiff_scan_tropw], eax
    mov eax, [eval_dbg_trop_b]
    mov [uci_evaldiff_scan_tropb], eax

    ; obnov povodny dirty flag
    mov al, [uci_evaldiff_saved_dirty]
    mov [pl_dirty], al

%if ENABLE_PL_INVARIANT = 1
    ; snapshot adries, ktore videla list-path slucka v evaluate
    mov rax, [eval_dbg_lp_lists_base]
    mov [uci_evaldiff_lists_base_lo], eax
    shr rax, 32
    mov [uci_evaldiff_lists_base_hi], eax
    mov rax, [eval_dbg_lp_counts_base]
    mov [uci_evaldiff_counts_base_lo], eax
    shr rax, 32
    mov [uci_evaldiff_counts_base_hi], eax

    ; vypis list komponenty
    lea rdi, [uci_info_evaldiff_list]
    call write_cstr
    lea rdi, [uci_info_evaldiff_score]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_score]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_mg]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_mg]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_eg]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_eg]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_phase]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_phase]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_wk]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_wk]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_bk]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_bk]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_tropw]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_tropw]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_tropb]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_tropb]
    call uci_print_signed_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
%endif

%if ENABLE_PL_INVARIANT = 1
    ; what list-path actually saw: base adresy
    lea rdi, [uci_info_evaldiff_seen_base]
    call write_cstr
    mov eax, [uci_evaldiff_lists_base_hi]
    call print_number
    lea rdi, [uci_info_evaldiff_slash]
    call write_cstr
    mov eax, [uci_evaldiff_lists_base_lo]
    call print_number
    lea rdi, [uci_info_evaldiff_counts_base]
    call write_cstr
    mov eax, [uci_evaldiff_counts_base_hi]
    call print_number
    lea rdi, [uci_info_evaldiff_slash]
    call write_cstr
    mov eax, [uci_evaldiff_counts_base_lo]
    call print_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; what list-path saw: county
    lea rdi, [uci_info_evaldiff_seen_counts]
    call write_cstr
    xor ecx, ecx
.evaldiff_seen_counts_loop:
    cmp ecx, 12
    jge .evaldiff_seen_counts_done
    lea rdi, [uci_info_evaldiff_idx_prefix]
    call write_cstr
    mov eax, ecx
    call print_number
    lea rdi, [uci_info_evaldiff_eq]
    call write_cstr
    movzx eax, byte [eval_dbg_lp_counts + rcx]
    call print_number
    lea rdi, [uci_info_evaldiff_sp]
    call write_cstr
    inc ecx
    jmp .evaldiff_seen_counts_loop
.evaldiff_seen_counts_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; what list-path saw: first square
    lea rdi, [uci_info_evaldiff_seen_first]
    call write_cstr
    xor ecx, ecx
.evaldiff_seen_first_loop:
    cmp ecx, 12
    jge .evaldiff_seen_first_done
    lea rdi, [uci_info_evaldiff_idx_prefix]
    call write_cstr
    mov eax, ecx
    call print_number
    lea rdi, [uci_info_evaldiff_eq]
    call write_cstr
    movzx eax, byte [eval_dbg_lp_first + rcx]
    call print_number
    lea rdi, [uci_info_evaldiff_sp]
    call write_cstr
    inc ecx
    jmp .evaldiff_seen_first_loop
.evaldiff_seen_first_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; direct pl_counts/pl_lists view (checker-side)
    lea rdi, [uci_info_evaldiff_direct_counts]
    call write_cstr
    xor ecx, ecx
.evaldiff_direct_counts_loop:
    cmp ecx, 12
    jge .evaldiff_direct_counts_done
    lea rdi, [uci_info_evaldiff_idx_prefix]
    call write_cstr
    mov eax, ecx
    call print_number
    lea rdi, [uci_info_evaldiff_eq]
    call write_cstr
    movzx eax, byte [pl_counts + rcx]
    call print_number
    lea rdi, [uci_info_evaldiff_sp]
    call write_cstr
    inc ecx
    jmp .evaldiff_direct_counts_loop
.evaldiff_direct_counts_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    lea rdi, [uci_info_evaldiff_direct_first]
    call write_cstr
    xor ecx, ecx
.evaldiff_direct_first_loop:
    cmp ecx, 12
    jge .evaldiff_direct_first_done
    lea rdi, [uci_info_evaldiff_idx_prefix]
    call write_cstr
    mov eax, ecx
    call print_number
    lea rdi, [uci_info_evaldiff_eq]
    call write_cstr
    mov r8d, ecx
    shl r8d, 4
    movzx eax, byte [pl_lists + r8]
    call print_number
    lea rdi, [uci_info_evaldiff_sp]
    call write_cstr
    inc ecx
    jmp .evaldiff_direct_first_loop
.evaldiff_direct_first_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
%endif

    ; vypis scan komponenty
    lea rdi, [uci_info_evaldiff_scan]
    call write_cstr
    lea rdi, [uci_info_evaldiff_score]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_score]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_mg]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_mg]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_eg]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_eg]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_phase]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_phase]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_wk]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_wk]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_bk]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_bk]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_tropw]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_tropw]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_tropb]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_tropb]
    call uci_print_signed_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; prvy odlisny komponent
    lea rdi, [uci_info_evaldiff_first]
    call write_cstr

    mov eax, [uci_evaldiff_list_score]
    cmp eax, [uci_evaldiff_scan_score]
    jne .evaldiff_first_score
    mov eax, [uci_evaldiff_list_mg]
    cmp eax, [uci_evaldiff_scan_mg]
    jne .evaldiff_first_mg
    mov eax, [uci_evaldiff_list_eg]
    cmp eax, [uci_evaldiff_scan_eg]
    jne .evaldiff_first_eg
    mov eax, [uci_evaldiff_list_phase]
    cmp eax, [uci_evaldiff_scan_phase]
    jne .evaldiff_first_phase
    mov eax, [uci_evaldiff_list_wk]
    cmp eax, [uci_evaldiff_scan_wk]
    jne .evaldiff_first_wk
    mov eax, [uci_evaldiff_list_bk]
    cmp eax, [uci_evaldiff_scan_bk]
    jne .evaldiff_first_bk
    mov eax, [uci_evaldiff_list_tropw]
    cmp eax, [uci_evaldiff_scan_tropw]
    jne .evaldiff_first_tropw
    mov eax, [uci_evaldiff_list_tropb]
    cmp eax, [uci_evaldiff_scan_tropb]
    jne .evaldiff_first_tropb
    lea rdi, [uci_info_evaldiff_none]
    call write_cstr
    jmp .evaldiff_first_emit_nl

.evaldiff_first_score:
    lea rdi, [uci_info_evaldiff_name_score]
    call write_cstr
    lea rdi, [uci_info_evaldiff_listv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_score]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_scanv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_score]
    call uci_print_signed_number
    jmp .evaldiff_first_emit_nl
.evaldiff_first_mg:
    lea rdi, [uci_info_evaldiff_name_mg]
    call write_cstr
    lea rdi, [uci_info_evaldiff_listv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_mg]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_scanv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_mg]
    call uci_print_signed_number
    jmp .evaldiff_first_emit_nl
.evaldiff_first_eg:
    lea rdi, [uci_info_evaldiff_name_eg]
    call write_cstr
    lea rdi, [uci_info_evaldiff_listv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_eg]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_scanv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_eg]
    call uci_print_signed_number
    jmp .evaldiff_first_emit_nl
.evaldiff_first_phase:
    lea rdi, [uci_info_evaldiff_name_phase]
    call write_cstr
    lea rdi, [uci_info_evaldiff_listv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_phase]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_scanv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_phase]
    call uci_print_signed_number
    jmp .evaldiff_first_emit_nl
.evaldiff_first_wk:
    lea rdi, [uci_info_evaldiff_name_wk]
    call write_cstr
    lea rdi, [uci_info_evaldiff_listv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_wk]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_scanv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_wk]
    call uci_print_signed_number
    jmp .evaldiff_first_emit_nl
.evaldiff_first_bk:
    lea rdi, [uci_info_evaldiff_name_bk]
    call write_cstr
    lea rdi, [uci_info_evaldiff_listv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_bk]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_scanv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_bk]
    call uci_print_signed_number
    jmp .evaldiff_first_emit_nl
.evaldiff_first_tropw:
    lea rdi, [uci_info_evaldiff_name_tropw]
    call write_cstr
    lea rdi, [uci_info_evaldiff_listv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_tropw]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_scanv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_tropw]
    call uci_print_signed_number
    jmp .evaldiff_first_emit_nl
.evaldiff_first_tropb:
    lea rdi, [uci_info_evaldiff_name_tropb]
    call write_cstr
    lea rdi, [uci_info_evaldiff_listv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_list_tropb]
    call uci_print_signed_number
    lea rdi, [uci_info_evaldiff_scanv]
    call write_cstr
    movsxd rax, dword [uci_evaldiff_scan_tropb]
    call uci_print_signed_number

.evaldiff_first_emit_nl:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.rootdiag:
    mov byte [uci_rootdiag_enabled], 1
    jmp .loop

.hashtest:
    ; deterministicky hash test: 256 legalnych ply,
    ; po make/unmake porovnaj inkrementalny hash vs compute_hash.
    call init_board
    call init_hash_history
    call record_hash
    mov dword [uci_hashtest_plies], 0
    mov dword [uci_hashtest_phase], 0

.hashtest_loop:
    call compute_hash
    mov r15, [position_hash]                ; h0 pred tahom

    mov byte [nnue_acc_valid], 0
    call generate_all_moves
    call filter_legal_moves
    movzx ecx, word [move_count]
    test ecx, ecx
    jz .hashtest_ok

    mov rax, [position_hash]
    xor edx, edx
    div ecx                                  ; edx = pseudo-random index tahu
    lea rsi, [move_list]
    movzx eax, word [rsi + rdx*2]
    mov [uci_hashtest_move], ax
    movzx ebx, ax
    shr ebx, 12
    mov [uci_hashtest_flag], ebx

    call make_move

    mov r14, [position_hash]                ; inkremental po make
    call compute_hash
    mov r13, [position_hash]                ; plny po make
    cmp r13, r14
    jne .hashtest_fail_make

    call unmake_move

    mov r14, [position_hash]                ; inkremental po unmake
    call compute_hash
    mov r13, [position_hash]                ; plny po unmake
    cmp r13, r14
    jne .hashtest_fail_unmake_delta
    cmp r13, r15                            ; restore na h0?
    jne .hashtest_fail_unmake_restore

    inc dword [uci_hashtest_plies]
    cmp dword [uci_hashtest_plies], 256
    jl .hashtest_loop

.hashtest_ok:
    lea rdi, [uci_info_hashtest_ok]
    call write_cstr
    mov eax, [uci_hashtest_plies]
    movsxd rax, eax
    call print_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.hashtest_fail_make:
    mov dword [uci_hashtest_phase], 1
    mov [uci_hashtest_h_expected], r14
    mov [uci_hashtest_h_actual], r13
    jmp .hashtest_emit_fail

.hashtest_fail_unmake_delta:
    mov dword [uci_hashtest_phase], 2
    mov [uci_hashtest_h_expected], r14
    mov [uci_hashtest_h_actual], r13
    jmp .hashtest_emit_fail

.hashtest_fail_unmake_restore:
    mov dword [uci_hashtest_phase], 3
    mov [uci_hashtest_h_expected], r15
    mov [uci_hashtest_h_actual], r13

.hashtest_emit_fail:
    lea rdi, [uci_info_hashtest_bad]
    call write_cstr
    mov eax, [uci_hashtest_phase]
    cmp eax, 1
    jne .phase_check2
    lea rdi, [uci_info_hashtest_phase_make]
    call write_cstr
    jmp .phase_done
.phase_check2:
    cmp eax, 2
    jne .phase_restore
    lea rdi, [uci_info_hashtest_phase_unmake_delta]
    call write_cstr
    jmp .phase_done
.phase_restore:
    lea rdi, [uci_info_hashtest_phase_unmake_restore]
    call write_cstr
.phase_done:
    lea rdi, [uci_info_hashtest_ply]
    call write_cstr
    mov eax, [uci_hashtest_plies]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_info_hashtest_flag]
    call write_cstr
    mov eax, [uci_hashtest_flag]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_info_hashtest_move]
    call write_cstr
    movzx rax, word [uci_hashtest_move]
    call uci_print_move_token
    lea rdi, [uci_info_hashtest_h_expected]
    call write_cstr
    mov rax, [uci_hashtest_h_expected]
    call print_number
    lea rdi, [uci_info_hashtest_h_actual]
    call write_cstr
    mov rax, [uci_hashtest_h_actual]
    call print_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.nnuewalk:
    ; random playout + unwind: po kazdom make aj unmake porovnaj
    ; nnue2_eval (acc delta) vs nnue2_refresh + nnue2_eval.
    cmp byte [nnue2_ready], 1
    je .nnuewalk_go
    lea rdi, [uci_info_nnuewalk_no_nnue]
    call write_cstr
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.nnuewalk_go:
    call init_board
    call init_hash_history
    call record_hash
    call nnue2_refresh
    mov dword [uci_nnuewalk_plies], 0
    mov dword [uci_nnuewalk_total], 0
    mov dword [uci_nnuewalk_phase], 0
    mov dword [uci_nnuewalk_persp], 0

.nnuewalk_fwd_loop:
    mov eax, [uci_nnuewalk_plies]
    cmp eax, 60
    jge .nnuewalk_unwind

    mov byte [nnue_acc_valid], 0
    call generate_all_moves
    call filter_legal_moves
    movzx ecx, word [move_count]
    test ecx, ecx
    jz .nnuewalk_unwind

    mov rax, [position_hash]
    xor edx, edx
    div ecx
    lea rsi, [move_list]
    movzx eax, word [rsi + rdx*2]
    mov [uci_nnuewalk_move], ax

    mov ecx, [uci_nnuewalk_plies]
    mov [uci_nnuewalk_moves + rcx*2], ax

    call nnue2_refresh
    movzx eax, word [uci_nnuewalk_move]
    call make_move

    mov ax, [uci_nnuewalk_move]
    call uci_nnuewalk_classify_type
    mov ecx, [uci_nnuewalk_plies]
    mov [uci_nnuewalk_types + rcx], al
    mov [uci_nnuewalk_type], eax

    mov dword [uci_nnuewalk_phase], 1
    call uci_nnuewalk_cmp_evals
    test eax, eax
    jnz .nnuewalk_fail

    inc dword [uci_nnuewalk_plies]
    inc dword [uci_nnuewalk_total]
    jmp .nnuewalk_fwd_loop

.nnuewalk_unwind:
    cmp dword [uci_nnuewalk_plies], 0
    je .nnuewalk_ok

.nnuewalk_unwind_loop:
    cmp dword [uci_nnuewalk_plies], 0
    je .nnuewalk_ok

    dec dword [uci_nnuewalk_plies]
    mov ecx, [uci_nnuewalk_plies]
    movzx eax, word [uci_nnuewalk_moves + rcx*2]
    mov [uci_nnuewalk_move], ax
    movzx eax, byte [uci_nnuewalk_types + rcx]
    mov [uci_nnuewalk_type], eax

    call unmake_move

    mov dword [uci_nnuewalk_phase], 2
    call uci_nnuewalk_cmp_evals
    test eax, eax
    jnz .nnuewalk_fail

    jmp .nnuewalk_unwind_loop

.nnuewalk_ok:
    lea rdi, [uci_info_nnuewalk_ok]
    call write_cstr
    mov eax, [uci_nnuewalk_total]
    movsxd rax, eax
    call print_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.nnuewalk_fail:
    mov [uci_nnuewalk_persp], eax
    lea rdi, [uci_info_nnuewalk_bad]
    call write_cstr

    mov eax, [uci_nnuewalk_phase]
    cmp eax, 1
    jne .nnuewalk_emit_phase_unmake
    lea rdi, [uci_info_nnuewalk_phase_make]
    call write_cstr
    jmp .nnuewalk_emit_ply
.nnuewalk_emit_phase_unmake:
    lea rdi, [uci_info_nnuewalk_phase_unmake]
    call write_cstr

.nnuewalk_emit_ply:
    lea rdi, [uci_info_nnuewalk_ply]
    call write_cstr
    mov eax, [uci_nnuewalk_plies]
    movsxd rax, eax
    call print_number

    lea rdi, [uci_info_nnuewalk_move]
    call write_cstr
    movzx rax, word [uci_nnuewalk_move]
    call uci_print_move_token

    lea rdi, [uci_info_nnuewalk_type]
    call write_cstr
    mov eax, [uci_nnuewalk_type]
    cmp eax, 1
    je .nnuewalk_type_capture
    cmp eax, 2
    je .nnuewalk_type_castle
    cmp eax, 3
    je .nnuewalk_type_ep
    cmp eax, 4
    je .nnuewalk_type_promo
    lea rdi, [uci_info_nnuewalk_type_quiet]
    call write_cstr
    jmp .nnuewalk_emit_persp
.nnuewalk_type_capture:
    lea rdi, [uci_info_nnuewalk_type_capture]
    call write_cstr
    jmp .nnuewalk_emit_persp
.nnuewalk_type_castle:
    lea rdi, [uci_info_nnuewalk_type_castle]
    call write_cstr
    jmp .nnuewalk_emit_persp
.nnuewalk_type_ep:
    lea rdi, [uci_info_nnuewalk_type_ep]
    call write_cstr
    jmp .nnuewalk_emit_persp
.nnuewalk_type_promo:
    lea rdi, [uci_info_nnuewalk_type_promo]
    call write_cstr

.nnuewalk_emit_persp:
    lea rdi, [uci_info_nnuewalk_persp]
    call write_cstr
    mov eax, [uci_nnuewalk_persp]
    cmp eax, 1
    jne .nnuewalk_persp_opp
    lea rdi, [uci_info_nnuewalk_persp_stm]
    call write_cstr
    movsxd rax, dword [uci_nnuewalk_eval_inc_stm]
    jmp .nnuewalk_emit_evals
.nnuewalk_persp_opp:
    lea rdi, [uci_info_nnuewalk_persp_opp]
    call write_cstr
    movsxd rax, dword [uci_nnuewalk_eval_inc_opp]

.nnuewalk_emit_evals:
    lea rdi, [uci_info_nnuewalk_eval_inc]
    call write_cstr
    call uci_print_signed_number
    lea rdi, [uci_info_nnuewalk_eval_ref]
    call write_cstr
    mov eax, [uci_nnuewalk_persp]
    cmp eax, 1
    jne .nnuewalk_ref_opp
    movsxd rax, dword [uci_nnuewalk_eval_ref_stm]
    jmp .nnuewalk_ref_emit
.nnuewalk_ref_opp:
    movsxd rax, dword [uci_nnuewalk_eval_ref_opp]
.nnuewalk_ref_emit:
    call uci_print_signed_number

    lea rdi, [uci_info_nnuewalk_fen]
    call write_cstr
    call uci_emit_fen

    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    jmp .loop

.isready:
    lea rdi, [uci_ready]
    mov rdx, uci_ready_len
    call write_str
    jmp .loop

.uci:
    lea rdi, [uci_id_name]
    call write_cstr
    lea rdi, [uci_id_author]
    call write_cstr
    lea rdi, [uci_opt_hash]
    call write_cstr
    lea rdi, [uci_opt_ownbook]
    call write_cstr
    lea rdi, [uci_opt_ponder]
    call write_cstr
    lea rdi, [uci_opt_syzygy]
    call write_cstr
    lea rdi, [uci_opt_syzygy_depth]
    call write_cstr
    lea rdi, [uci_opt_overhead]
    call write_cstr
    lea rdi, [uci_opt_evalmode]
    call write_cstr
    lea rdi, [uci_opt_threads]
    call write_cstr
    lea rdi, [uci_ok]
    call write_cstr
    jmp .loop

.position:
    call uci_position
    jmp .loop

.go:
    call uci_go
    jmp .loop

.setoption:
    mov rdi, 9
    call uci_token
    cmp rax, -1
    je .loop
    mov rdi, rax
    call uci_setoption
    jmp .loop

.ucinewgame:
    call init_board
    call init_hash_history
    call record_hash
    ; init_board/reset hash meni poziciu mimo make_move delty,
    ; pri NNUE2 preto explicitne obnov accumulator.
    cmp byte [eval_mode], 2
    jne .ucinewgame_no_refresh
    cmp byte [nnue2_ready], 1
    jne .ucinewgame_no_refresh
    call nnue2_refresh
.ucinewgame_no_refresh:
    call pgn_new_game         ; uzavrie PGN sekciu predchádzajúcej partie
    mov qword [uci_pgn_ply], 0
    jmp .loop

.stop:
    mov byte [uci_stop_flag], 1
    jmp .loop

.ponderhit:
    mov byte [uci_ponder], 0
    jmp .loop

.analyze:
    call suite_cmd_uci
    jmp .loop

.suite:
    call suite_cmd_uci
    jmp .loop

.tbtest:
    call tb_piece_count
    mov r12, rax
    call tb_probe_wdl
    mov rbx, rax
    call tb_probe_dtz
    mov r13, rax

    lea rdi, [uci_tbtest_prefix]
    call write_cstr
    mov rax, r12
    call print_number
    lea rdi, [uci_tbtest_wdl]
    call write_cstr
    mov rax, rbx
    call print_number
    lea rdi, [uci_tbtest_dtz]
    call write_cstr
    mov rax, r13
    call print_number
    lea rdi, [uci_tbtest_map]
    call write_cstr
    mov rax, [tb_map_size]
    call print_number
    lea rdi, [uci_tbtest_path]
    call write_cstr
    lea rdi, [tb_file_path]
    call write_cstr
    lea rdi, [uci_tbtest_wdl_payload]
    call write_cstr
    movzx rax, byte [tb_wdl_payload_probe_byte]
    call print_number
    lea rdi, [uci_tbtest_wdl_off]
    call write_cstr
    mov rax, [tb_wdl_payload_probe_off]
    call print_number
    lea rdi, [uci_tbtest_wdl_flags]
    call write_cstr
    movzx rax, byte [tb_wdl_header_flags]
    call print_number
    lea rdi, [uci_tbtest_wdl_hdr_off]
    call write_cstr
    mov rax, [tb_wdl_pairs_header_off]
    call print_number
    lea rdi, [uci_tbtest_wdl_blocks]
    call write_cstr
    mov eax, [tb_wdl_pairs_num_blocks]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_wdl_syms]
    call write_cstr
    mov eax, [tb_wdl_pairs_num_syms]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_wdl_blocksize]
    call write_cstr
    movzx rax, byte [tb_wdl_pairs_blocksize]
    call print_number
    lea rdi, [uci_tbtest_wdl_idxbits]
    call write_cstr
    movzx rax, byte [tb_wdl_pairs_idxbits]
    call print_number
    lea rdi, [uci_tbtest_wdl_const]
    call write_cstr
    movzx rax, byte [tb_wdl_pairs_is_const]
    call print_number
    lea rdi, [uci_tbtest_wdl_order_byte]
    call write_cstr
    movzx rax, byte [tb_wdl_debug_order_byte]
    call print_number
    lea rdi, [uci_tbtest_wdl_wk]
    call write_cstr
    mov eax, [tb_wdl_debug_wk]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_wdl_bk]
    call write_cstr
    mov eax, [tb_wdl_debug_bk]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_wdl_extra]
    call write_cstr
    mov eax, [tb_wdl_debug_extra]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_wdl_order]
    call write_cstr
    mov eax, [tb_wdl_debug_order]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_wdl_idx]
    call write_cstr
    mov rax, [tb_wdl_debug_idx]
    call print_number
    lea rdi, [uci_tbtest_wdl_idx]
    call write_cstr
    mov rax, [tb_wdl_debug_idx + 8]
    call print_number
    lea rdi, [uci_tbtest_wdl_tbsize]
    call write_cstr
    mov rax, [tb_tb_size]
    call print_number
    lea rdi, [uci_tbtest_wdl_nf_code]
    call write_cstr
    movzx rax, byte [tb_wdl_debug_nf_code]
    call print_number
    lea rdi, [uci_tbtest_wdl_p4_tbsize]
    call write_cstr
    mov rax, [tb_wdl_debug_tb_size]
    call print_number
    lea rdi, [uci_tbtest_wdl_p4_tbsize]
    call write_cstr
    mov rax, [tb_wdl_debug_tb_size + 8]
    call print_number
    lea rdi, [uci_tbtest_dtz_payload]
    call write_cstr
    movzx rax, byte [tb_dtz_payload_probe_byte]
    call print_number
    lea rdi, [uci_tbtest_dtz_off]
    call write_cstr
    mov rax, [tb_dtz_payload_probe_off]
    call print_number
    lea rdi, [uci_tbtest_dtz_flags]
    call write_cstr
    movzx rax, byte [tb_dtz_header_flags]
    call print_number
    lea rdi, [uci_tbtest_dtz_hdr_off]
    call write_cstr
    mov rax, [tb_dtz_pairs_header_off]
    call print_number
    lea rdi, [uci_tbtest_dtz_blocks]
    call write_cstr
    mov eax, [tb_dtz_pairs_num_blocks]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_syms]
    call write_cstr
    mov eax, [tb_dtz_pairs_num_syms]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_blocksize]
    call write_cstr
    movzx rax, byte [tb_dtz_pairs_blocksize]
    call print_number
    lea rdi, [uci_tbtest_dtz_idxbits]
    call write_cstr
    movzx rax, byte [tb_dtz_pairs_idxbits]
    call print_number
    lea rdi, [uci_tbtest_dtz_const]
    call write_cstr
    movzx rax, byte [tb_dtz_pairs_is_const]
    call print_number
    lea rdi, [uci_tbtest_dtz_order_byte]
    call write_cstr
    movzx rax, byte [tb_dtz_debug_order_byte]
    call print_number
    lea rdi, [uci_tbtest_dtz_wk]
    call write_cstr
    mov eax, [tb_dtz_debug_wk]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_bk]
    call write_cstr
    mov eax, [tb_dtz_debug_bk]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_extra]
    call write_cstr
    mov eax, [tb_dtz_debug_extra]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_target]
    call write_cstr
    mov eax, [tb_dtz_debug_target_code]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_order]
    call write_cstr
    mov eax, [tb_dtz_debug_order]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_idx]
    call write_cstr
    mov rax, [tb_dtz_debug_idx]
    call print_number
    lea rdi, [uci_tbtest_dtz_raw_symbol]
    call write_cstr
    mov eax, [tb_dtz_debug_raw_symbol]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_helper_ret]
    call write_cstr
    mov eax, [tb_dtz_debug_helper_ret]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_helper_ok]
    call write_cstr
    movzx rax, byte [tb_dtz_debug_helper_ok]
    call print_number
    lea rdi, [uci_tbtest_dtz_nf_code]
    call write_cstr
    mov eax, [tb_dtz_debug_nf_code]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_bside]
    call write_cstr
    mov eax, [tb_dtz_debug_bside_used]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_flags1]
    call write_cstr
    mov eax, [tb_dtz_debug_flags1]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_minlen]
    call write_cstr
    mov eax, [tb_dtz_debug_min_len]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_tbsize]
    call write_cstr
    mov eax, [tb_dtz_debug_tb_size]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dtz_ptr_wdl_i]
    call write_cstr
    mov rax, [tb_dtz_debug_ptr_wdl_index]
    call print_number
    lea rdi, [uci_tbtest_dtz_ptr_wdl_s]
    call write_cstr
    mov rax, [tb_dtz_debug_ptr_wdl_size]
    call print_number
    lea rdi, [uci_tbtest_dtz_ptr_wdl_d]
    call write_cstr
    mov rax, [tb_dtz_debug_ptr_wdl_data]
    call print_number
    lea rdi, [uci_tbtest_dtz_ptr_dtz_i]
    call write_cstr
    mov rax, [tb_dtz_debug_ptr_dtz_index]
    call print_number
    lea rdi, [uci_tbtest_dtz_ptr_dtz_s]
    call write_cstr
    mov rax, [tb_dtz_debug_ptr_dtz_size]
    call print_number
    lea rdi, [uci_tbtest_dtz_ptr_dtz_d]
    call write_cstr
    mov rax, [tb_dtz_debug_ptr_dtz_data]
    call print_number
    lea rdi, [uci_tbtest_dec_mainidx]
    call write_cstr
    mov rax, [tb_dec_trace_mainidx]
    call print_number
    lea rdi, [uci_tbtest_dec_litidx]
    call write_cstr
    mov eax, [tb_dec_trace_litidx]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dec_block]
    call write_cstr
    mov eax, [tb_dec_trace_block]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dec_bitcnt]
    call write_cstr
    mov eax, [tb_dec_trace_bitcnt]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dec_code_hex]
    call write_cstr
    mov rax, [tb_dec_trace_code_hex]
    call print_number
    lea rdi, [uci_tbtest_dec_root_sym]
    call write_cstr
    mov eax, [tb_dec_trace_root_sym]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dec_leaf_sym]
    call write_cstr
    mov eax, [tb_dec_trace_leaf_sym]
    movsxd rax, eax
    call print_number
    lea rdi, [uci_tbtest_dec_stage]
    call write_cstr
    movzx eax, byte [tb_dec_stage_tmp]
    movsxd rax, eax
    call print_number
    lea rdi, [msg_newline]
    mov rdx, 1
    call write_str
    ; per-step walk trace (max 8 krokov child traversalu)
    xor r12d, r12d
.dec_step_loop:
    cmp r12d, [tb_dec_trace_nsteps]
    jae .dec_step_done
    cmp r12d, 8
    jae .dec_step_done
    lea rdi, [uci_tbtest_dec_step]
    call write_cstr
    mov rax, r12
    call print_number
    lea rdi, [uci_tbtest_dec_step_sym]
    call write_cstr
    mov ecx, r12d
    shl ecx, 5
    lea rdx, [tb_dec_trace_steps]
    movsxd rax, dword [rdx + rcx]
    call print_number
    lea rdi, [uci_tbtest_dec_step_s1]
    call write_cstr
    mov ecx, r12d
    shl ecx, 5
    lea rdx, [tb_dec_trace_steps]
    movsxd rax, dword [rdx + rcx + 4]
    call print_number
    lea rdi, [uci_tbtest_dec_step_s2]
    call write_cstr
    mov ecx, r12d
    shl ecx, 5
    lea rdx, [tb_dec_trace_steps]
    movsxd rax, dword [rdx + rcx + 8]
    call print_number
    lea rdi, [uci_tbtest_dec_step_lit]
    call write_cstr
    mov ecx, r12d
    shl ecx, 5
    lea rdx, [tb_dec_trace_steps]
    movsxd rax, dword [rdx + rcx + 12]
    call print_number
    lea rdi, [uci_tbtest_dec_step_pick]
    call write_cstr
    mov ecx, r12d
    shl ecx, 5
    lea rdx, [tb_dec_trace_steps]
    movsxd rax, dword [rdx + rcx + 16]
    call print_number
    lea rdi, [msg_newline]
    mov rdx, 1
    call write_str
    inc r12d
    jmp .dec_step_loop
.dec_step_done:
    jmp .loop

.bbtest:
    call pos_validate
    mov r12, rax
    lea rdi, [uci_bbtest_prefix]
    call write_cstr
    mov rax, r12
    call print_number
    lea rdi, [msg_newline]
    mov rdx, 1
    call write_str
    jmp .loop

.halfkpdump:
    ; Perspektivna konvencia dumpu:
    ; p0 = strana na tahu (STM), p1 = super (OPP).
    ; ks je king_rel pouzity indexerom danej perspektivy.
    lea rdi, [rel .out_halfkpdump_hdr]
    call write_cstr

    ; p0 (STM)
    movzx edx, byte [side]
    lea rdi, [uci_halfkp_idxbuf]
    call nnue2_halfkp_collect     ; eax=count, ecx=ks
    mov r8d, eax                  ; count
    mov r9d, ecx                  ; ks
    lea rdi, [rel .out_halfkp_p0]
    call write_cstr
    mov eax, r9d
    call print_number
    lea rdi, [rel .out_halfkp_n]
    call write_cstr
    mov eax, r8d
    call print_number
    lea rdi, [rel .out_halfkp_idx]
    call write_cstr
    xor r10d, r10d
.halfkp_p0_idx_loop:
    cmp r10d, r8d
    jae .halfkp_p0_done
    lea rdi, [rel .out_halfkp_sp]
    call write_cstr
    mov eax, [uci_halfkp_idxbuf + r10*4]
    call print_number
    inc r10d
    jmp .halfkp_p0_idx_loop
.halfkp_p0_done:
    lea rdi, [msg_newline]
    mov rdx, 1
    call write_str

    ; p1 (OPP)
    movzx edx, byte [side]
    xor edx, 1
    lea rdi, [uci_halfkp_idxbuf]
    call nnue2_halfkp_collect     ; eax=count, ecx=ks
    mov r8d, eax
    mov r9d, ecx
    lea rdi, [rel .out_halfkp_p1]
    call write_cstr
    mov eax, r9d
    call print_number
    lea rdi, [rel .out_halfkp_n]
    call write_cstr
    mov eax, r8d
    call print_number
    lea rdi, [rel .out_halfkp_idx]
    call write_cstr
    xor r10d, r10d
.halfkp_p1_idx_loop:
    cmp r10d, r8d
    jae .halfkp_p1_done
    lea rdi, [rel .out_halfkp_sp]
    call write_cstr
    mov eax, [uci_halfkp_idxbuf + r10*4]
    call print_number
    inc r10d
    jmp .halfkp_p1_idx_loop
.halfkp_p1_done:
    lea rdi, [msg_newline]
    mov rdx, 1
    call write_str
    jmp .loop

.done:
    call pgn_quit             ; uzavrie partiu a zavrie games.pgn
    pop r12
    pop rbx
    ret

.str_quit:    db "quit", 0
.str_isready: db "isready", 0
.str_uci:     db "uci", 0
.str_position:db "position", 0
.str_go:      db "go", 0
.str_setoption: db "setoption", 0
.str_ucinewgame: db "ucinewgame", 0
.str_stop:    db "stop", 0
.str_ponderhit: db "ponderhit", 0
.str_analyze: db "analyze", 0
.str_suite:   db "suite", 0
.str_tbtest:  db "tbtest", 0
.str_ecotest: db "ecotest", 0
.str_bbtest:  db "bbtest", 0
.str_list:    db "list", 0
.str_eval:    db "eval", 0
.str_evaldiff: db "evaldiff", 0
.str_evalstate: db "evalstate", 0
.str_hashtest: db "hashtest", 0
.str_nnuewalk: db "nnuewalk", 0
.str_halfkpdump: db "halfkpdump", 0
.str_rootdiag: db "rootdiag", 0
.str_perft:   db "perft", 0

.out_halfkpdump_hdr: db "halfkpdump", 10, 0
.out_halfkp_p0: db "p0 ks=", 0
.out_halfkp_p1: db "p1 ks=", 0
.out_halfkp_n: db " n=", 0
.out_halfkp_idx: db " idx:", 0
.out_halfkp_sp: db " ", 0
