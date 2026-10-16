    ; singular search: depth/2, alpha=sBeta-1, beta=sBeta, allow_null=0
    mov rdi, [rbp - 8]
    shr rdi, 1                      ; depth/2
    test rdi, rdi
    jnz .sing_depth_ok
    mov rdi, 1
.sing_depth_ok:
    mov esi, edx
    dec esi                         ; alpha = sBeta - 1
    movsxd rsi, esi
    movsxd rdx, edx                 ; beta = sBeta
    xor ecx, ecx                    ; allow_null = 0
    call negamax
    neg eax                         ; -score (z pohladu protihraca)
    mov r10d, eax                   ; uloz singular score
    pop rcx
    pop rdx                         ; tah (ulozeny pred singular search)
    mov dword [singular_excl], 0    ; vymaz excluded move
    movzx rax, dx                   ; obnov tah pre make_move (16-bit)
    cmp r10d, dword [rbp - 24]      ; singular fail-high? (multi-cut)
    jge .singular_cutoff
    ; fail-low? -> extension
    mov edx, dword [rbp - 48]
    sub edx, 64                     ; sBeta
    cmp r10d, edx
    jl .set_singular_ext            ; singular! extend toto
    jmp .no_singular
.singular_cutoff:
    mov eax, r10d
    jmp .neg_exit_singular          ; beta cutoff
.set_singular_ext:
    mov dword [rbp - 72], 1         ; nastavenie extension flagu
.no_singular:
    push rcx                        ; make_move/clanky mozu prepisat rcx
    call make_move                  ; aplikuj aktualny tah pred child searchom
    pop rcx
    inc qword [search_ply]
    ; rcx je uz korektne obnoven z pop rcx pocas singular vetve
    ; (alebo nikdy nebol modifikovany v .no_singular path)

    ; --- child depth: +1 extension ak je vlastny kral v sachu (cap ply 40) ---
    ; +1 extension tiez pre singular move (singular_excl=0 pred make_move,
    ;    singular_excl_check prebehol vyssie, ext_flag v [rbp-72])
    mov rdi, [rbp - 8]
    cmp dword [rbp - 44], 0
    je .child_depth
    cmp qword [search_ply], 40
    jae .child_depth
    jmp .depth_ready          ; check extension: depth sa neznizuje
.child_depth:
    ; --- SINGULAR EXTENSION: ak bol tento tah oznaceny (ext_flag=1), +1 ---
    cmp dword [rbp - 72], 1
    jne .no_sing_ext
    mov dword [rbp - 72], 0  ; vymaz flag (plati len pre prvy tah)
    jmp .depth_ready          ; depth sa neznizuje = extension
.no_sing_ext:
    dec rdi
.depth_ready:
    mov [rbp - 52], rdi     ; child depth (pre PVS/LMR re-search)

    ; uloz aktualne okno pre trace daneho reply tahu
    mov eax, dword [rbp - 16]
    mov [trace_move_alpha], eax
    mov eax, dword [rbp - 24]
    mov [trace_move_beta], eax

    cmp byte [trace_white_active], 1
    jne .trace_reply_preamble_done
    ; info string wtrace reply move=<move> alpha=<a> beta=<b> stm=<stm> fen=<fen> eval_search=<eval> score=<...>
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rcx
    push rdi
    push rsi
    push rdx
    push r8
    push r9
    push r10

    lea rdi, [trace_w_reply_prefix]
    call write_cstr
    movzx rax, word [rbp - 584 + rcx*2]
    call uci_print_move_token

    lea rdi, [trace_w_alpha]
    call write_cstr
    movsxd rax, dword [trace_move_alpha]
    call trace_print_signed

    lea rdi, [trace_w_beta]
    call write_cstr
    movsxd rax, dword [trace_move_beta]
    call trace_print_signed

    lea rdi, [trace_w_stm]
    call write_cstr
    movzx rax, byte [side]
    call print_number

    lea rdi, [trace_w_fen]
    call write_cstr
    call uci_emit_fen

    lea rdi, [trace_w_eval]
    call write_cstr
    call search_eval_checked
    mov r10d, eax
    movzx eax, byte [side]
    cmp eax, WHITE
    je .trace_reply_eval_ready
    neg r10d
.trace_reply_eval_ready:
    movsxd rax, r10d
    call trace_print_signed

    lea rdi, [trace_w_score]
    call write_cstr

    pop r10
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rdi
    pop rcx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
.trace_reply_preamble_done:

    test rcx, rcx
    jnz .pvs_window

.first_full:
    ; --- PRVY TAH: plne okno ---
    mov rsi, [rbp - 24]
    neg rsi                 ; -beta
    mov rdx, [rbp - 16]
    neg rdx                 ; -alpha
    push rcx                ; zachovaj index; negamax je caller-saved pre rcx
    mov rcx, 1              ; allow_null = 1 (negamax parameter)
    call negamax
    pop rcx                 ; obnov index
    neg eax                 ; -score
    jmp .after_search

.pvs_window:
    ; --- LMR: quiet tah, index/depth prahy, nie v sachu ---
%if ENABLE_LMR = 0
    jmp .no_lmr
%endif
    cmp r12d, 1
    jne .no_lmr
    cmp rcx, LMR_INDEX_MIN
    jl .no_lmr
    cmp qword [rbp - 8], LMR_DEPTH_MIN
    jl .no_lmr
    cmp dword [rbp - 44], 0
    jne .no_lmr
    ; redukovany search: child depth - LMR_BASE_REDUCTION
    ; !improving (eval klesa/stagnuje): volitelna extra redukcia o 1
    mov edx, LMR_BASE_REDUCTION
.lmr_base_red_loop:
    test edx, edx
    jz .lmr_base_red_done
    cmp rdi, 1
    jle .lmr_base_red_done
    dec rdi
    dec edx
    jmp .lmr_base_red_loop
.lmr_base_red_done:
%if LMR_EXTRA_NON_IMPROVING = 1
    cmp dword [rbp - 64], 0
    jne .lmr_red_done
    cmp rdi, 2
    jl .lmr_red_done
    dec rdi
%endif
.lmr_red_done:
    mov rsi, [rbp - 16]
    neg rsi
    dec rsi                 ; -(alpha+1)
    mov rdx, [rbp - 16]
    neg rdx                 ; -alpha
    push rcx                ; zachovaj index
    push rdi                ; zachovaj child depth
    mov rcx, 1
    call negamax
    pop rdi
    pop rcx                 ; obnov index
    neg eax
    cmp eax, dword [rbp - 16]
    jle .after_search       ; fail-low: prijmi redukovany vysledok
    ; uspel: re-search na plnej hlbke null window (fall through)
.no_lmr:
    mov rsi, [rbp - 16]
    neg rsi
    dec rsi                 ; -(alpha+1)
    mov rdx, [rbp - 16]
    neg rdx                 ; -alpha
    push rcx                ; zachovaj index
    mov rcx, 1
    call negamax
    pop rcx                 ; obnov index
    neg eax
    ; PVS: ak alpha < score < beta -> re-search plne okno
    cmp eax, dword [rbp - 16]
    jle .after_search
    cmp eax, dword [rbp - 24]
    jge .after_search
    mov rdi, [rbp - 52]     ; obnov child depth
    mov rsi, [rbp - 24]
    neg rsi                 ; -beta
    mov rdx, [rbp - 16]
    neg rdx                 ; -alpha
    push rcx                ; zachovaj index
    mov rcx, 1
    call negamax
    pop rcx                 ; obnov index
    neg eax

.after_search:
    dec qword [search_ply]

    push rcx                        ; unmake_move clobberuje caller-saved registre
    call unmake_move
    pop rcx
    ; rcx je uz obnoven (nikdy sa neupravil v .after_search ceste bez pop)
    inc dword [rbp - 76]

    cmp byte [trace_white_active], 1
    jne .trace_reply_done
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10

    mov r10d, eax
    movsxd rax, r10d
    call trace_print_signed

    lea rdi, [trace_w_flag]
    call write_cstr
    mov edx, dword [trace_move_alpha]
    cmp r10d, edx
    jle .trace_flag_fl
    mov edx, dword [trace_move_beta]
    cmp r10d, edx
    jge .trace_flag_fh
    lea rdi, [trace_w_flag_exact]
    jmp .trace_flag_emit
.trace_flag_fl:
    lea rdi, [trace_w_flag_fl]
    jmp .trace_flag_emit
.trace_flag_fh:
    lea rdi, [trace_w_flag_fh]
.trace_flag_emit:
    call write_cstr
    call trace_nl

    mov eax, r10d
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
.trace_reply_done:

    cmp eax, ebx
    jle .alpha_update
    mov ebx, eax
    movzx r13d, word [rbp - 584 + rcx*2]   ; best move

.alpha_update:
    cmp eax, dword [rbp - 16]
    jle .check_cutoff
    movsxd rdx, eax         ; 64-bit ciste ulozenie alpha (hore bez smeti)
    mov [rbp - 16], rdx

    ; --- PV update: tento tah zvysil alpha ---
    push rbx
    push rcx
    push rsi
    push rdi

    mov rax, [search_ply]
    mov rbx, rax
    shl rbx, 7
    lea rdi, [pv_table + rbx]
    movzx ecx, word [rbp - 584 + rcx*2]   ; aktualny tah
    mov [rdi], cx

    ; skopiruj child PV (ply+1) za prvy tah
    mov rdi, rax
    inc rdi
    mov rbx, [pv_len + rdi*8]      ; dlzka child PV
    mov rcx, rbx
    shl rdi, 7
    lea rsi, [pv_table + rdi]      ; zdroj child PV
    mov rdi, rax
    shl rdi, 7
    lea rdi, [pv_table + rdi + 2]  ; ciel za prvy tah
    rep movsw

    ; uloz dlzku parent PV = child len + 1
    mov rax, [search_ply]
    lea rdx, [rax + 1]
    mov rdx, [pv_len + rdx*8]
    inc rdx
    mov [pv_len + rax*8], rdx

    pop rdi
    pop rsi
    pop rcx
    pop rbx

.check_cutoff:
    mov edx, dword [rbp - 16]
    cmp edx, dword [rbp - 24]
    jl .no_cutoff

    ; --- beta cutoff: aktualizuj killers/history/cap_history/countermove ---
    movzx eax, word [rbp - 584 + rcx*2]
    mov r9d, eax
    shr r9d, 12
    test r9d, r9d
    jz .cutoff_plain             ; bezny tah: quiet alebo branie
    cmp r9d, FLAG_ENPASSANT
    je .cutoff_ep
    cmp r9d, FLAG_PROMO_Q
    jb .cutoff_done              ; castle: nikdy nie je branie
    cmp r9d, FLAG_PROMO_N
    ja .cutoff_done
    ; promo: spadni do testu brania (board[to] rozhodne)
.cutoff_plain:
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F                ; to
    lea rsi, [board]
    cmp byte [rsi + rdi], EMPTY
    jne .cutoff_capture
    test r9d, r9d
    jnz .cutoff_done             ; promo bez brania: nie je to cisty quiet tah
    ; killers: posun a uloz (ak uz nie je killer1)
    mov r9, [search_ply]
    cmp r9, 63
    ja .cutoff_history
    lea rsi, [killers]
    cmp eax, dword [rsi + r9*8]
    je .cutoff_history
    mov edi, dword [rsi + r9*8]
    mov dword [rsi + r9*8 + 4], edi   ; killer2 = stary killer1
    mov dword [rsi + r9*8], eax       ; killer1 = tah
.cutoff_history:
    ; history[side][from][to] += depth^2 so saturaciou
    movzx r9d, byte [side]
    shl r9d, 12
    movzx edi, ax
    and edi, 0x3F
    shl edi, 6
    mov r10d, eax
    shr r10d, 6
    and r10d, 0x3F
    add edi, r10d
    add edi, r9d
    lea r9, [history]
    mov esi, dword [r9 + rdi*4]
    mov edx, dword [rbp - 8]     ; depth
    imul edx, edx
    add esi, edx
    cmp esi, 40000
    jle .cutoff_hist_store
    mov esi, 40000
.cutoff_hist_store:
    mov dword [r9 + rdi*4], esi

    ; continuation history [prev_to][from][to] += depth^2 (quiet cutoff)
    mov r9, [search_ply]
    test r9, r9
    jz .cutoff_cont_done
    lea rdx, [move_stack]
    movzx edx, word [rdx + r9*2 - 2]
    test edx, edx
    jz .cutoff_cont_done
    shr edx, 6
    and edx, 0x3F                ; prev to
    shl edx, 12                  ; prev_to * 4096
    mov edi, eax
    and edi, 0x3F                ; from
    shl edi, 6
    add edx, edi
    mov edi, eax
    shr edi, 6
    and edi, 0x3F                ; to
    add edx, edi
    lea r9, [cont_history]
    mov esi, dword [r9 + rdx*4]
    mov edi, dword [rbp - 8]     ; depth
    imul edi, edi
    add esi, edi
    cmp esi, 40000
    jle .cutoff_cont_store
    mov esi, 40000
.cutoff_cont_store:
    mov dword [r9 + rdx*4], esi
.cutoff_cont_done:

    ; 2-ply continuation history [prev2_to][from][to] += depth^2 (quiet cutoff)
    mov r9, [search_ply]
    cmp r9, 2
    jb .cutoff_cont2_done
    lea rdx, [move_stack]
    movzx edx, word [rdx + r9*2 - 4]
    test edx, edx
    jz .cutoff_cont2_done
    shr edx, 6
    and edx, 0x3F                ; prev2 to
    shl edx, 12                  ; prev2_to * 4096
    mov edi, eax
    and edi, 0x3F                ; from
    shl edi, 6
    add edx, edi
    mov edi, eax
    shr edi, 6
    and edi, 0x3F                ; to
    add edx, edi
    lea r9, [cont_history2]
    mov esi, dword [r9 + rdx*4]
    mov edi, dword [rbp - 8]     ; depth
    imul edi, edi
    sar edi, 2                   ; jemnejsi update nez 1-ply continuation
    cmp edi, 1
    jge .cutoff_cont2_bonus_ok
    mov edi, 1
.cutoff_cont2_bonus_ok:
    add esi, edi
    cmp esi, 40000
    jle .cutoff_cont2_store
    mov esi, 40000
.cutoff_cont2_store:
    mov dword [r9 + rdx*4], esi
.cutoff_cont2_done:

    ; countermove: uloz tah ako refutaciu opponentovho posledneho tahu
    ; (kluc = tah na ply-1; pri root/null ply klucom nie je -> preskoc)
    mov r9, [search_ply]
    test r9, r9
    jz .cutoff_done
    lea rdx, [move_stack]
    movzx edx, word [rdx + r9*2 - 2]
    test edx, edx
    jz .cutoff_done
    mov esi, edx
    and esi, 0x3F                ; prev from
    shl esi, 6
    shr edx, 6
    and edx, 0x3F                ; prev to
    add edx, esi
    lea rsi, [countermoves]
    mov [rsi + rdx*2], ax        ; countermove = cutoff tah
    jmp .cutoff_done

.cutoff_ep:
    ; en passant: obet = PESIAK, iduca figura = PESIAK
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F                ; to
    imul edi, edi, 6             ; (PAWN-1)*384 + to*6 + (PAWN-1)
    lea rsi, [cap_history]
    jmp .cutoff_cap_bonus

.cutoff_capture:
    ; cap_history[figura][to][obet] += depth^2 so saturaciou 40000
    ; (rsi = board, rdi = to z .cutoff_plain)
    movzx r9d, byte [rsi + rdi]  ; obet
    and r9d, PIECE_MASK
    dec r9d
    imul edi, edi, 6
    add edi, r9d
    movzx r9d, ax
    and r9d, 0x3F                ; from
    movzx r9d, byte [rsi + r9]   ; iduca figura
    and r9d, PIECE_MASK
    dec r9d
    imul r9d, r9d, 384
    add edi, r9d
    lea rsi, [cap_history]
.cutoff_cap_bonus:
    mov r9d, dword [rsi + rdi*4]
    mov edx, dword [rbp - 8]     ; depth
    imul edx, edx
    add r9d, edx
    cmp r9d, 40000
    jle .cutoff_cap_store
    mov r9d, 40000
.cutoff_cap_store:
    mov dword [rsi + rdi*4], r9d
.cutoff_done:
    jmp .loop_done

.no_cutoff:
    inc rcx
    jmp .move_loop

.loop_done:
    ; safeguard: ak heuristiky preskocili vsetky tahy, nevracaj -INF/INF cez alpha,
    ; ale stabilny fallback zo static evaluacie.
    cmp dword [rbp - 76], 0
    jne .loop_scored
    inc qword [prof_allprune]
    mov eax, dword [rbp - 56]
    cmp eax, EVAL_NONE
    jne .neg_exit
    mov eax, dword [rbp - 16]
    jmp .neg_exit

.loop_scored:
    cmp ebx, -INF
    jne .best_ok
    mov eax, dword [rbp - 16]
    jmp .neg_exit
.best_ok:
    ; update correction history na realne prehladanych uzloch
    ; len pre EXACT uzly (bez fail-high/fail-low bound skreslenia)
%if ENABLE_CORR_HISTORY = 1
    cmp ebx, dword [rbp - 32]
    jle .corr_done
    cmp ebx, dword [rbp - 24]
    jge .corr_done

    mov edx, dword [rbp - 68]       ; raw eval pred korekciou
    cmp edx, EVAL_NONE
    je .corr_done
    mov eax, ebx
    sub eax, edx                    ; error = best - raw_eval
    ; konzervativny clamp, aby sa bucket neprestreli
    cmp eax, 256
    jle .corr_hi_ok
    mov eax, 256
.corr_hi_ok:
    cmp eax, -256
    jge .corr_lo_ok
    mov eax, -256
.corr_lo_ok:
    shl eax, 4                      ; CP -> CP*16 (tabulka je CP*64)
    movzx edx, byte [side]
    shl edx, 10
    mov r8, [position_hash]
    and r8d, 1023
    add edx, r8d
    lea r8, [corr_history]

    ; jemny decay bucketu, aby sa stare chyby postupne zabudali
    mov ecx, dword [r8 + rdx*4]
    mov esi, ecx
    sar esi, 5                      ; ~3.1% decay
    sub ecx, esi
    add eax, ecx

    ; clamp bucketu
    cmp eax, 8192
    jle .corr_hi_store
    mov eax, 8192
.corr_hi_store:
    cmp eax, -8192
    jge .corr_store
    mov eax, -8192
.corr_store:
    mov dword [r8 + rdx*4], eax
%endif
.corr_done:

    mov eax, ebx

    cmp byte [trace_white_active], 1
    jne .trace_final_done
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rdi
    push r10
    mov r10d, eax

    lea rdi, [trace_w_final_prefix]
    call write_cstr
    mov rax, rbx
    call trace_print_signed
    lea rdi, [trace_w_returned]
    call write_cstr
    movsxd rax, r10d
    call trace_print_signed
    call trace_nl

    mov eax, r10d
    pop r10
    pop rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
.trace_final_done:

    ; pri aborte (uci_stop_flag) neukladaj do TT
    cmp byte [uci_stop_flag], 0
    jne .neg_exit

    ; store do TT: rdi=hash, rsi=depth, edx=score, ecx=flag, r8w=move
%if ENABLE_TT = 0
    jmp .neg_exit
%endif
    cmp ebx, dword [rbp - 32]   ; best <= original_alpha -> UPPER
    jle .tt_upper
    cmp ebx, dword [rbp - 24]   ; best >= beta -> LOWER
    jge .tt_lower
    xor ecx, ecx                ; TT_EXACT
    jmp .tt_do_store
.tt_upper:
    mov ecx, TT_UPPER
    jmp .tt_do_store
.tt_lower:
    mov ecx, TT_LOWER
.tt_do_store:
    mov rdi, [position_hash]
    mov rsi, [rbp - 8]
    mov edx, ebx
    movzx r8d, r13w
    call tt_store
    mov eax, ebx            ; tt_store clobberuje rax, vrat skore
    jmp .neg_exit

.neg_exit_singular:         ; pouziva sa zo singular multi-cut (eax = score)
.neg_exit:
    mov rsp, rbp
.neg_fast_exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; search_best_move - najde najlepsi tah pre aktualnu stranu
; Vstup:  rdi = hlbka
; Vystup: ax = najlepsi 16-bitovy tah (0 ak niet tahu)
; ============================================================
