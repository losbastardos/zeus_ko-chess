search_best_move:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbp, rsp

    ; helper procesy (smp.asm) musia ist rovno do single rezimu;
    ; poistka proti buducej SMP dispatch logike
    cmp dword [smp_worker_mode], 0
    jne .sbm_single

.sbm_single:
    mov rbx, rdi            ; odloz hlbku searchu pred volaniami

%if ENABLE_PL_INFRA = 1
    ; piece-list stav pre search cesty synchronizuj raz na root pozicii
    call pl_rebuild_from_board
%endif

    mov qword [nodes_searched], 0
    mov qword [prof_qnodes], 0
    mov qword [prof_evals], 0
    mov qword [prof_movegen], 0
    mov qword [prof_makes], 0
    mov qword [prof_unmakes], 0
    mov qword [prof_allprune], 0
%if ENABLE_SEE_AUDIT = 1
    call see_audit_reset
%endif
    mov dword [search_last_score], 0
    mov qword [search_ply], 0
    mov qword [root_pv_len], 0   ; root PV zacina prazdna

    ; vynuluj killer tabulku; history/cap_history/countermoves/continuation/corr
    ; len pri prvej ID iteracii
    lea rdi, [killers]
    mov rcx, 2*64
    xor eax, eax
    rep stosd
    cmp rbx, 1
    jne .skip_history_clear
    lea rdi, [history]
    mov rcx, 2*64*64
    rep stosd
    lea rdi, [cap_history]
    mov rcx, 6*64*6
    rep stosd
    lea rdi, [countermoves]
    mov rcx, 64*64/2          ; slova -> po dvoch v dworde
    rep stosd
    lea rdi, [cont_history]
    mov rcx, 64*64*64
    rep stosd
    lea rdi, [cont_history2]
    mov rcx, 64*64*64
    rep stosd
    lea rdi, [corr_history]
    mov rcx, 2*1024
    rep stosd
    ; nova pozicia/go: reset root ordering hintu z predch. iteracie
    mov dword [root_best_move], 0
.skip_history_clear:

    call generate_all_moves
    mov r15, rbx
    movzx r12, word [move_count]
    test r12, r12
    jz .no_moves

    ; lokalna kopia tahov
    mov rax, r12
    shl rax, 1
    add rax, 7
    and rax, ~7
    sub rsp, rax

    lea rsi, [move_list]
    mov rdi, rsp
    mov rcx, r12
.copy_loop:
    mov ax, [rsi]
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    dec rcx
    jnz .copy_loop

    mov r13, -INF           ; best score
    xor r14d, r14d          ; best move
    mov dword [root_trace_count], 0
    mov dword [root_diag_count], 0
    xor rcx, rcx
    ; aspiration: ak nepoziadane, pouzi plne okno
    cmp dword [asp_use], 0
    jne .asp_ready
    mov dword [asp_alpha], -INF
    mov dword [asp_beta], INF
.asp_ready:
    mov eax, [asp_alpha]
    mov [root_alpha], eax

.move_loop:
    ; na roote kontrolujeme stop/time vzdy (pocet root tahov je maly)
    call check_time
    test eax, eax
    jnz .loop_done

    cmp byte [uci_stop_flag], 0
    jne .loop_done

    cmp rcx, r12
    jge .loop_done

    ; jednoduche ordering: captures/promocie dopredu (selection)
    mov r10, rcx            ; best index
    mov r11d, -1            ; best score
    mov r8, rcx             ; scan index
    lea rsi, [board]

.root_sel_loop:
    cmp r8, r12
    jge .root_sel_done

    movzx rax, word [rsp + r8*2]
    xor edx, edx

    ; root ordering key:
    ; - promo bonus
    ; - capture MVV-LVA (+capture history)
    ; - quiet history
    mov r9d, eax
    shr r9d, 12
    and r9d, 0xF

    ; promo bonus
    cmp r9d, FLAG_PROMO_Q
    jb .root_not_promo
    cmp r9d, FLAG_PROMO_N
    ja .root_not_promo
    add edx, 80000
.root_not_promo:

    ; en-passant je capture aj ked board[to] je prazdny
    cmp r9d, FLAG_ENPASSANT
    je .root_cap_ep

    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    bt qword [bb_occ], rdi
    jc .root_cap_normal

    ; cieleny tie-break: nepreferuj manualny krok kralom z e1/e8,
    ; ked su root skore remizovane.
    movzx r9d, ax
    and r9d, 0x3F                 ; from
    cmp r9d, 4                    ; e1
    je .root_king_home_check
    cmp r9d, 60                   ; e8
    jne .root_rook_home_check
.root_king_home_check:
    movzx edi, byte [rsi + r9]
    and edi, PIECE_MASK
    cmp edi, KING
    jne .root_rook_home_check
    sub edx, 25000

    ; sekundarny tie-break: v otvarani nepreferuj manualny tah domacou vezou
    ; z a1/h1/a8/h8, ak nejde o nutenu takticku volbu.
.root_rook_home_check:
    movzx r9d, ax
    and r9d, 0x3F                 ; from
    cmp r9d, 0                    ; a1
    je .root_rook_home_sq
    cmp r9d, 7                    ; h1
    je .root_rook_home_sq
    cmp r9d, 56                   ; a8
    je .root_rook_home_sq
    cmp r9d, 63                   ; h8
    jne .root_quiet_hist
.root_rook_home_sq:
    movzx edi, byte [rsi + r9]
    and edi, PIECE_MASK
    cmp edi, ROOK
    jne .root_quiet_hist
    movzx edi, word [fullmove]
    cmp edi, 12
    ja .root_quiet_hist
    sub edx, 12000

    ; quiet history[side][from][to]
.root_quiet_hist:
    movzx edi, byte [side]
    shl edi, 12
    mov r9d, eax
    and r9d, 0x3F
    shl r9d, 6
    add edi, r9d
    mov r9d, eax
    shr r9d, 6
    and r9d, 0x3F
    add edi, r9d
    lea r9, [history]
    add edx, dword [r9 + rdi*4]
    jmp .root_score_done

.root_cap_ep:
    ; EP: victim pawn, attacker pawn
    add edx, 200900
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    imul edi, edi, 6
    lea r9, [cap_history]
    add edx, dword [r9 + rdi*4]
    jmp .root_score_done

.root_cap_normal:
    ; capture MVV-LVA + live cap_history
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    movzx edi, byte [rsi + rdi]      ; victim
    and edi, PIECE_MASK
    lea r9, [q_capture_value]
    mov edi, dword [r9 + rdi*4]
    imul edi, edi, 10
    add edx, 200000
    add edx, edi

    movzx edi, ax
    and edi, 0x3F
    movzx edi, byte [rsi + rdi]      ; attacker
    and edi, PIECE_MASK
    sub edx, dword [r9 + rdi*4]

    ; cap_history index = (attacker-1)*384 + to*6 + (victim-1)
    movzx edi, ax
    and edi, 0x3F
    movzx edi, byte [rsi + rdi]
    and edi, PIECE_MASK
    dec edi
    imul edi, edi, 384
    mov r9d, edi
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    imul edi, edi, 6
    add r9d, edi
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    movzx edi, byte [rsi + rdi]
    and edi, PIECE_MASK
    dec edi
    add r9d, edi
    lea rdi, [cap_history]
    add edx, dword [rdi + r9*4]

.root_score_done:
    ; best move z predchadzajucej ID iteracie ma prioritu
    cmp ax, word [root_best_move]
    jne .root_score_cmp
    add edx, 1000000
.root_score_cmp:
    cmp edx, r11d
    jle .root_sel_next
    mov r11d, edx
    mov r10, r8

.root_sel_next:
    inc r8
    jmp .root_sel_loop

.root_sel_done:
    cmp r10, rcx
    je .root_sel_picked
    mov ax, [rsp + rcx*2]
    mov dx, [rsp + r10*2]
    mov [rsp + rcx*2], dx
    mov [rsp + r10*2], ax

.root_sel_picked:

    movzx rax, word [rsp + rcx*2]
    mov byte [trace_root_target], 0
    cmp byte [trace_white_enable], 0
    je .root_trace_target_done
    cmp eax, 2331                 ; d4e5
    jne .root_trace_target_done
    mov byte [trace_root_target], 1
.root_trace_target_done:
    mov r9, [nodes_searched]
    mov [root_diag_nodes_start], r9
    push rcx
    call make_move
    mov rcx, [rsp]          ; obnov index

    mov rdi, r15
    dec rdi
    ; Root PVS default: plne okno len pre prvy tah.
    test rcx, rcx
    jz .root_full
.root_pvs:
    ; PVS null window: child (-(alpha+1), -alpha) ako v negamax slucke
    movsxd rsi, dword [root_alpha]
    neg rsi
    dec rsi                 ; -(alpha+1)
    movsxd rdx, dword [root_alpha]
    neg rdx                 ; -alpha
    mov eax, [root_alpha]
    mov [root_diag_a_tmp], eax
    mov eax, [root_alpha]
    inc eax
    mov [root_diag_b_tmp], eax
    jmp .root_call
.root_full:
    mov eax, [asp_alpha]
    mov [root_diag_a_tmp], eax
    mov eax, [asp_beta]
    mov [root_diag_b_tmp], eax
    movsxd rsi, dword [asp_beta]
    neg rsi                 ; -beta
    movsxd rdx, dword [asp_alpha]
    neg rdx                 ; -alpha
.root_call:
    push rcx                ; zachovaj index
    mov rcx, 1              ; allow_null = 1
    call negamax
    pop rcx                 ; obnov index
    neg eax
    ; PVS re-search: null-window tah s alpha < score < beta
    cmp qword [rsp], 0
    je .root_searched
    cmp eax, dword [root_alpha]
    jle .root_searched
    cmp eax, dword [asp_beta]
    jge .root_searched
    mov rdi, r15
    dec rdi
    mov eax, [asp_alpha]
    mov [root_diag_a_tmp], eax
    mov eax, [asp_beta]
    mov [root_diag_b_tmp], eax
    movsxd rsi, dword [asp_beta]
    neg rsi
    movsxd rdx, dword [asp_alpha]
    neg rdx
    push rcx                ; zachovaj index
    mov rcx, 1
    call negamax
    pop rcx                 ; obnov index
    neg eax
.root_searched:
    call unmake_move
    mov byte [trace_root_target], 0
    pop rcx                 ; index pushnuty pred make_move

    cmp byte [uci_stop_flag], 0
    jne .loop_done

    ; detailny root log: score, okno, fail flag, nodes, child pv0
    mov edx, [root_diag_count]
    cmp edx, 256
    jae .root_diag_done

    mov bx, word [rsp + rcx*2]
    mov [root_diag_moves + rdx*2], bx
    mov [root_diag_scores + rdx*4], eax
    mov esi, [root_diag_a_tmp]
    mov [root_diag_alpha + rdx*4], esi
    mov esi, [root_diag_b_tmp]
    mov [root_diag_beta + rdx*4], esi

    mov esi, eax
    mov edi, [root_diag_a_tmp]
    cmp esi, edi
    jle .root_diag_fl
    mov edi, [root_diag_b_tmp]
    cmp esi, edi
    jge .root_diag_fh
    mov byte [root_diag_flag + rdx], 0
    jmp .root_diag_flag_done
.root_diag_fl:
    mov byte [root_diag_flag + rdx], 1
    jmp .root_diag_flag_done
.root_diag_fh:
    mov byte [root_diag_flag + rdx], 2
.root_diag_flag_done:

    mov r8, [nodes_searched]
    sub r8, [root_diag_nodes_start]
    mov [root_diag_nodes + rdx*8], r8
    mov bx, word [pv_table]
    mov [root_diag_pv0 + rdx*2], bx
    inc dword [root_diag_count]
.root_diag_done:

    ; diagnostika: udrzuj top 5 root tahov podla skore zostupne
    movzx r8d, word [rsp + rcx*2]
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push rbx
    push r8

    mov edx, dword [root_trace_count]
    cmp edx, 5
    jb .trace_insert

    mov esi, dword [root_trace_scores + 4*4]
    cmp eax, esi
    jle .trace_done
    mov edx, 4
    jmp .trace_store

.trace_insert:
    inc dword [root_trace_count]

.trace_store:
    mov dword [root_trace_scores + rdx*4], eax
    mov bx, word [rsp]
    mov word [root_trace_moves + rdx*2], bx

.trace_bubble:
    test edx, edx
    jz .trace_done
    mov esi, dword [root_trace_scores + rdx*4]
    mov edi, dword [root_trace_scores + rdx*4 - 4]
    cmp esi, edi
    jle .trace_done

    mov dword [root_trace_scores + rdx*4 - 4], esi
    mov dword [root_trace_scores + rdx*4], edi

    mov bx, word [root_trace_moves + rdx*2]
    mov di, word [root_trace_moves + rdx*2 - 2]
    mov word [root_trace_moves + rdx*2 - 2], bx
    mov word [root_trace_moves + rdx*2], di

    dec edx
    jmp .trace_bubble

.trace_done:
    pop r8
    pop rbx
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax

    cmp eax, r13d
    jl .next
    jg .take_new

    ; tie-break pri rovnakom score:
    ; ak aktualny best je skory manualny tah domacim kralom/vezou
    ; a novy tah nie je, preferuj novy tah.
    xor edx, edx                    ; edx = curr_bad_opening_move
    movzx r8d, word [rsp + rcx*2]
    mov r9d, r8d
    shr r9d, 12
    cmp r9d, FLAG_CASTLE
    je .tb_curr_done
    mov r9d, r8d
    and r9d, 0x3F
    cmp r9d, 4
    je .tb_curr_sq_ok
    cmp r9d, 60
    jne .tb_curr_rook
.tb_curr_sq_ok:
    lea r11, [board]
    movzx r10d, byte [r11 + r9]
    and r10d, PIECE_MASK
    cmp r10d, KING
    jne .tb_curr_rook
    mov edx, 1
.tb_curr_rook:
    mov r9d, r8d
    and r9d, 0x3F
    cmp r9d, 0
    je .tb_curr_rook_sq
    cmp r9d, 7
    je .tb_curr_rook_sq
    cmp r9d, 56
    je .tb_curr_rook_sq
    cmp r9d, 63
    jne .tb_curr_done
.tb_curr_rook_sq:
    lea r11, [board]
    movzx r10d, byte [r11 + r9]
    and r10d, PIECE_MASK
    cmp r10d, ROOK
    jne .tb_curr_done
    movzx r10d, word [fullmove]
    cmp r10d, 12
    ja .tb_curr_done
    mov edx, 1
.tb_curr_done:

    xor esi, esi                    ; esi = best_bad_opening_move
    movzx r8d, r14w
    mov r9d, r8d
    shr r9d, 12
    cmp r9d, FLAG_CASTLE
    je .tb_best_done
    mov r9d, r8d
    and r9d, 0x3F
    cmp r9d, 4
    je .tb_best_sq_ok
    cmp r9d, 60
    jne .tb_best_rook
.tb_best_sq_ok:
    lea r11, [board]
    movzx r10d, byte [r11 + r9]
    and r10d, PIECE_MASK
    cmp r10d, KING
    jne .tb_best_rook
    mov esi, 1
.tb_best_rook:
    mov r9d, r8d
    and r9d, 0x3F
    cmp r9d, 0
    je .tb_best_rook_sq
    cmp r9d, 7
    je .tb_best_rook_sq
    cmp r9d, 56
    je .tb_best_rook_sq
    cmp r9d, 63
    jne .tb_best_done
.tb_best_rook_sq:
    lea r11, [board]
    movzx r10d, byte [r11 + r9]
    and r10d, PIECE_MASK
    cmp r10d, ROOK
    jne .tb_best_done
    movzx r10d, word [fullmove]
    cmp r10d, 12
    ja .tb_best_done
    mov esi, 1
.tb_best_done:

    cmp esi, 1
    jne .next                       ; best nie je home-king -> ponechaj best
    cmp edx, 0
    jne .next                       ; current je tiez home-king -> bez zmeny

.take_new:
    mov r13d, eax
    mov dword [root_alpha], eax   ; alpha = best
    movzx r14d, word [rsp + rcx*2]

    ; --- update root PV (ply 0) ---
    push rax
    push rbx
    push rcx
    push rsi
    push rdi
    push r14

    lea rdi, [root_pv_table]     ; prvy tah root PV
    mov [rdi], r14w

    mov rcx, [pv_len]            ; dlzka child PV (ply 0, lebo root negamax bezi na ply 0)
    mov rbx, rcx
    lea rsi, [pv_table]          ; child PV zaciatok
    lea rdi, [root_pv_table + 2] ; parent za prvym tahom
    rep movsw

    inc rbx
    mov [root_pv_len], rbx       ; dlzka root PV

    pop r14
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    pop rax

.next:
    inc rcx
    jmp .move_loop

.loop_done:
    test r14d, r14d
    jnz .have_best
    cmp r12, 0
    je .have_best
    movzx r14d, word [rsp]
    mov r13d, 0

.have_best:
    mov dword [root_best_move], r14d   ; pre ordering v dalsej ID iteracii

    mov dword [search_last_score], r13d
    mov edi, r14d
    call collect_pv         ; naplni pv_moves[] pre panel/UCI vypis
    mov eax, r14d
    jmp .sbm_exit

.no_moves:
    xor eax, eax

.sbm_exit:
%if ENABLE_SEE_AUDIT = 1
    call see_audit_emit
%endif
    mov rsp, rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; perft - spocita legalne listove uzly do danej hlbky
; Vstup:  rdi = hlbka
; Vystup: rax = pocet uzlov (64-bit)
; ============================================================
