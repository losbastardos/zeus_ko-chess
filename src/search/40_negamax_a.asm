negamax:
    push rbp
    push rbx                ; best score
    push r12                ; quiet flag aktualneho tahu
    push r13                ; best move
    push r14                ; tt_move
    push r15                ; move count
    mov rbp, rsp

    inc qword [nodes_searched]
    ; check_time nevolaj na kazdom node: staci periodicky
    mov rax, [nodes_searched]
    and rax, 2047
    jnz .neg_continue
    call check_time
    test eax, eax
    jz .neg_continue
    xor eax, eax
    jmp .neg_exit

.neg_continue:

    ; vynuluj PV pre aktualny ply
    mov rax, [search_ply]
    mov qword [pv_len + rax*8], 0

    ; bezpecnostny cap ply: undo_stack ma 64 zaznamov; pri ply >= 60
    ; vratime staticky eval (check extension + qsearch floor -32 by inak
    ; prekrocili kapacitu a make_move by prepisal pamat za undo_stack)
    cmp qword [search_ply], 60
    jl .ply_cap_ok
    call search_eval_checked
    movzx ebx, byte [side]
    test ebx, ebx
    jz .ply_cap_done
    neg eax
.ply_cap_done:
    jmp .neg_exit
.ply_cap_ok:

    sub rsp, 1616           ; 512B move_list kopia + 1KB ordering klucov + lokaly
                            ; [rbp-72] = singular_move (0=normalny), [rbp-48] = tt_score

    mov [rbp - 8], rdi      ; depth
    mov [rbp - 16], rsi     ; alpha
    mov [rbp - 24], rdx     ; beta
    mov [rbp - 40], rcx     ; allow_null
    mov dword [rbp - 48], -32000  ; tt_score pre singular (NONE)
    mov dword [rbp - 72], 0       ; singular_move = 0 (nie sme v singular sub-searchi)
    mov dword [rbp - 76], 0       ; pocet realne prehladanych child tahov (anti all-prune fallback)

    cmp qword [rbp - 8], 0
    jne .not_leaf

    mov rdi, 4              ; maximalna q-hlbka
    mov rsi, [rbp - 16]
    mov rdx, [rbp - 24]
    call quiescence
    jmp .neg_exit

.not_leaf:
    ; --- MATE DISTANCE PRUNING ---
    ; alpha >= -MATE+ply, beta <= MATE-ply; ak sa stretnu, vrat alpha
    mov rax, [search_ply]
    lea rdx, [rax - MATE_SCORE]     ; -MATE + ply (dolna hranica)
    cmp rdx, [rbp - 16]
    jle .mdp_alpha_ok
    mov [rbp - 16], rdx
.mdp_alpha_ok:
    mov rdx, MATE_SCORE
    sub rdx, rax                    ; MATE - ply (horna hranica)
    cmp rdx, [rbp - 24]
    jge .mdp_beta_ok
    mov [rbp - 24], rdx
.mdp_beta_ok:
    mov rax, [rbp - 16]
    cmp rax, [rbp - 24]
    jl .mdp_ok
    jmp .neg_exit                   ; alpha >= beta: uz nemoze byt lepsi mat
.mdp_ok:

    ; in_check flag pre cely uzol (null move, LMR, extension)
    movzx eax, byte [side]
    call is_in_check
    mov dword [rbp - 44], eax

    ; --- DETEKCIA REMIZY v search ---
    ; 50-tahove pravidlo: halfmove >= 100 -> remiza
    movzx eax, byte [halfmove]
    cmp eax, 100
    jae .draw_score
    ; opakovanie pozicie z historie hry (2. vyskyt = remiza)
    ; repetitia nemoze nastat skor ako po 4 ply od rootu
    cmp qword [search_ply], 4
    jl .no_draw
    lea rsi, [hash_history]
    mov rdx, [hash_count]
    mov rdi, [position_hash]
.draw_loop:
    test rdx, rdx
    jz .no_draw
    dec rdx
    cmp [rsi + rdx*8], rdi
    je .draw_score
    jmp .draw_loop
.draw_score:
    xor eax, eax
    jmp .neg_exit
.no_draw:

    ; --- SYZYGY TB PROBE ---
    ; uci_syzygy_probe_depth: 0 = vypnute, inak probe len pri depth >= threshold
    movsxd rax, dword [uci_syzygy_probe_depth]
    test eax, eax
    jle .tb_skip
    cmp qword [rbp - 8], rax
    jl .tb_skip

    ; bez nastavenej TB cesty nema probe zmysel (a obchadzame nestabilne vetvy)
    cmp qword [tb_path_len], 0
    jle .tb_skip

    ; ak je na sachovnici <= 3 kamenov, skus WDL probe
    ; 4+ piece sety nie su v engine este plne stabilne -> fallback na normalny search
    ; zname skore vratime okamzite; TB_NOT_FOUND = normalny search
    ; (pouzivame len caller-saved registre, nic nie je live)
    call tb_piece_count
    cmp eax, 3
    jg .tb_skip
    call tb_probe_wdl
    cmp eax, TB_NOT_FOUND
    je .tb_skip
    cmp eax, TB_WIN
    je .tb_win
    cmp eax, TB_LOSS
    je .tb_loss
    xor eax, eax            ; TB_DRAW -> 0
    jmp .neg_exit
.tb_win:
    ; konzistencia s mate scoringom: rychlejsi win ma vyssie skore
    mov rax, MATE_SCORE
    sub rax, [search_ply]
    jmp .neg_exit
.tb_loss:
    ; konzistencia s mate scoringom: pomalsia prehra ma vyssie skore
    mov rax, [search_ply]
    sub rax, MATE_SCORE
    jmp .neg_exit
.tb_skip:

    ; uloz povodne alpha pre urcenie TT flagu
    mov rax, [rbp - 16]
    mov [rbp - 32], rax     ; original_alpha
    xor r14d, r14d          ; tt_move = 0

    ; TT probe: rdi=hash, rsi=depth, rdx=alpha, rcx=beta
%if ENABLE_TT = 0
    jmp .tt_probe_done
%endif
    ; diagnostika: pri cielenom trace d4e5 vetvy nechceme TT skore-cutoff,
    ; potrebujeme vidiet realny priebeh reply slucky
    cmp byte [trace_root_target], 1
    jne .tt_probe_go
    cmp qword [search_ply], 0
    jne .tt_probe_go
    movzx eax, byte [side]
    cmp eax, WHITE
    jne .tt_probe_go
    jmp .tt_probe_done
.tt_probe_go:
    mov rdi, [position_hash]
    mov rsi, [rbp - 8]
    mov rdx, [rbp - 16]
    mov rcx, [rbp - 24]
    call tt_probe
    cmp edx, 1
    je .tt_score_hit
    cmp edx, 2
    jne .tt_probe_done
    mov r14d, r8d           ; zapamataj si TT tah pre ordering
    mov dword [rbp - 48], -32000    ; tt_score pre singular: NONE
    jmp .tt_probe_done
.tt_score_hit:
    mov r14d, r8d           ; tt_move
    mov [rbp - 48], eax     ; tt_score pre singular extensions
    ; TT usable score: vratan priamo ak nie sme v singular sub-searchi
    cmp dword [singular_excl], 0
    jne .tt_probe_done      ; v singular sub-searchi: neprunej priamo
    jmp .neg_exit           ; vracia eax = tt score
.tt_probe_done:

    ; --- IIR: pri vysokej hlbke bez TT tahu zniz hlbku o 1 ---
    cmp qword [rbp - 8], 4
    jl .iir_done
    test r14d, r14d
    jnz .iir_done
    dec qword [rbp - 8]
.iir_done:

    ; --- PROBCUT (depth >= 5, !in_check, nie v singular sub-searchi) ---
    ; Skus brania s oknom (beta+PROBCUT_MARGIN, beta+PROBCUT_MARGIN+1) na depth-4.
    ; Ak fail-high -> prune (tento uzol presiahne beta aj v plnom searchi).
    ; PROBCUT_MARGIN = 200 cps (Stockfish-like hodnota)
%define PROBCUT_MARGIN 200
%if ENABLE_PROBCUT = 0
    jmp .probcut_done
%endif
    cmp qword [rbp - 8], 5
    jl .probcut_done
    cmp dword [rbp - 44], 0         ; !in_check
    jne .probcut_done
    cmp dword [singular_excl], 0    ; nie v singular sub-searchi
    jne .probcut_done
    ; vygeneruj tahy (brania) a skus kazde s uzkou oknom
    call generate_all_moves
    movzx r15, word [move_count]
    test r15, r15
    jz .probcut_done
    ; uloz move_list do docasneho miesta (reuse [rbp-584] = kopia zoznamu)
    lea rsi, [move_list]
    lea rdi, [rbp - 584]
    movzx rcx, word [move_count]
.pc_copy:
    mov ax, [rsi]
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    dec rcx
    jnz .pc_copy
    ; precist cez brania (flags == 0 ale board[to] != EMPTY)
    xor rcx, rcx
.pc_loop:
    cmp rcx, r15
    jge .probcut_done
    movzx rax, word [rbp - 584 + rcx*2]
    ; je to branie? (to = board[to] != EMPTY a flags != promo/castle/ep simple)
    mov r9d, eax
    shr r9d, 12
    and r9d, 0xF
    cmp r9d, 5                      ; EP = flag 5 -> capture
    je .pc_is_capture
    cmp r9d, 6                      ; castle: nie je branie
    je .pc_next
    cmp r9d, 0
    jne .pc_next                    ; promo non-capture: preskoc
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    lea rsi, [board]
    movzx esi, byte [rsi + rdi]
    test esi, esi
    jz .pc_next                     ; prazdne: nie je branie
.pc_is_capture:
    ; SEE >= 0? (neprunej zle brania v ProbCut)
    push rax
    push rcx
    call see
    mov esi, eax
    pop rcx
    pop rax
    test esi, esi
    js .pc_next                     ; zle branie: preskoc
    ; skus tah
    push rax
    push rcx
    call make_move
    inc qword [search_ply]
    pop rcx
    pop rax
    ; search: -negamax(depth-4, -(beta+margin), -(beta+margin)+1, 0)
    ; Ak child fail-low (vrati <= -(beta+margin)), potom v rodicovi
    ; score >= beta+margin -> mozeme prune s hodnotou beta+margin.
    mov rdi, [rbp - 8]
    sub rdi, 4
    test rdi, rdi
    jl .pc_undo
    jnz .pc_depth_ok
    mov rdi, 1
.pc_depth_ok:
    mov rsi, [rbp - 24]
    add rsi, PROBCUT_MARGIN
    neg rsi                         ; -(beta + margin) = child alpha
    mov rdx, rsi
    inc rdx                         ; -(beta + margin) + 1 = child beta
    push rcx                        ; zachovaj index cez negamax+unmake
    xor ecx, ecx
    call negamax
    neg eax
    push rax
    dec qword [search_ply]
    call unmake_move
    pop rax
    pop rcx
    mov edx, dword [rbp - 24]
    add edx, PROBCUT_MARGIN         ; edx = beta + margin
    cmp eax, edx
    jl .pc_no_cut
    mov eax, edx                    ; ProbCut! vraciame beta + margin
    jmp .neg_exit
.pc_no_cut:
    jmp .pc_next_after_undo
.pc_undo:
    push rcx                        ; unmake_move clobberuje caller-saved registre
    dec qword [search_ply]
    call unmake_move
    pop rcx
.pc_next_after_undo:
.pc_next:
    inc rcx
    jmp .pc_loop
.probcut_done:

    ; --- STATICKY EVAL + IMPROVING FLAG ---
    ; eval z pohladu strany na tahu pre kazdy ne-check uzol -> [rbp - 56]
    ; a eval_stack[ply]. improving = ply>=2 && eval > eval_stack[ply-2]
    ; (obe hodnoty musia byt platne, inak improving = 0) -> [rbp - 64]
    mov ecx, EVAL_NONE
    mov dword [rbp - 68], EVAL_NONE ; raw eval pred correction history (diera medzi improving a singular_move)
    cmp dword [rbp - 44], 0
    jne .eval_ready                 ; v sachu: ziadny static eval
    call search_eval_checked
    movzx ecx, byte [side]
    test ecx, ecx
    jz .eval_side_ok
    neg eax
.eval_side_ok:
    mov ecx, eax                    ; raw eval (side-to-move)
    mov dword [rbp - 68], ecx

    ; correction history: jemna korekcia static eval podla hash bucketu
%if ENABLE_CORR_HISTORY = 1
    movzx eax, byte [side]
    shl eax, 10                     ; side * 1024
    mov r8, [position_hash]
    and r8d, 1023                   ; bucket
    add eax, r8d
    lea r8, [corr_history]
    mov edx, dword [r8 + rax*4]
    sar edx, 6                      ; CP*64 -> CP
    add ecx, edx
%endif
.eval_ready:
    mov [rbp - 56], ecx             ; static eval (EVAL_NONE v sachu)
    mov rax, [search_ply]
    lea rsi, [eval_stack]
    mov [rsi + rax*4], ecx
    xor edx, edx
    cmp rax, 2
    jl .improving_done
    cmp ecx, EVAL_NONE
    je .improving_done
    mov r8d, [rsi + rax*4 - 8]      ; eval_stack[ply - 2]
    cmp r8d, EVAL_NONE
    je .improving_done
    cmp ecx, r8d
    setg dl
.improving_done:
    mov [rbp - 64], edx

    ; --- REVERSE FUTILITY PRUNING (static null move) ---
    ; !in_check && depth <= 3: eval - margin >= beta -> return eval - margin
    ; margin = 120*depth; improving (eval stupa) -> 120*(depth-1), prunej menej
%if ENABLE_RFP = 0
    jmp .rfp_done
%endif
    cmp dword [rbp - 44], 0
    jne .rfp_done
    cmp qword [rbp - 8], 3
    jg .rfp_done
    mov ecx, dword [rbp - 56]
    mov rdx, [rbp - 8]
    imul edx, edx, 120              ; margin = 120 * depth
    cmp dword [rbp - 64], 0
    je .rfp_margin_ok
    sub edx, 120                    ; improving: margin = 120 * (depth - 1)
.rfp_margin_ok:
    sub ecx, edx
    cmp ecx, dword [rbp - 24]       ; eval - margin >= beta?
    jl .rfp_done
    mov eax, ecx
    jmp .neg_exit
.rfp_done:

    ; --- RAZORING ---
    ; depth == 1 && !in_check && eval + RAZOR_MARGIN < alpha -> rovno qsearch
    ; (vynechame generovanie/search celeho zoznamu tahov, vratime vysledok qsearch)
%if ENABLE_RAZOR = 0
    jmp .no_razoring
%endif
    cmp qword [rbp - 8], 1
    jne .no_razoring
    cmp dword [rbp - 44], 0
    jne .no_razoring
    mov eax, dword [rbp - 56]
    add eax, RAZOR_MARGIN
    cmp eax, dword [rbp - 16]       ; eval + margin < alpha?
    jge .no_razoring
    mov rdi, 4                      ; maximalna q-hlbka (ako pri prechode do qsearch)
    mov rsi, [rbp - 16]
    mov rdx, [rbp - 24]
    call quiescence
    jmp .neg_exit
.no_razoring:

    ; --- NULL MOVE PRUNING (TT probe je vyssie, po RFP/IIR) ---
    ; ak povolene, depth >= 3, nie v sachu, nie koncovka, ply < 60
%if ENABLE_NULL_PRUNE = 0
    jmp .skip_null
%endif
    cmp qword [rbp - 40], 0
    je .skip_null
    cmp qword [rbp - 8], 3
    jl .skip_null
    cmp dword [rbp - 44], 0
    jne .skip_null
    cmp qword [search_ply], 60
    jge .skip_null
    ; strana na tahu musi mat aspon jednu nepesiacu figuru (zugzwang)
    lea rdi, [board]
    movzx ecx, byte [side]
    shl ecx, 3
    xor edx, edx
.nn_scan:
    movzx eax, byte [rdi + rdx]
    test eax, eax
    jz .nn_next
    mov r8d, eax
    and r8d, COLOR_MASK
    cmp r8d, ecx
    jne .nn_next
    and eax, PIECE_MASK
    cmp eax, PAWN
    je .nn_next
    cmp eax, KING
    je .nn_next
    jmp .nn_ok
.nn_next:
    inc edx
    cmp edx, 64
    jl .nn_scan
    jmp .skip_null              ; same pesiaci -> ziadny null move
.nn_ok:
    ; uloz stav na null_stack[ply]
    mov rax, [search_ply]
    shl rax, 4
    lea rdi, [null_stack]
    add rdi, rax
    mov cl, [side]
    mov [rdi], cl
    mov cl, [enpassant]
    mov [rdi + 1], cl
    mov rdx, [position_hash]
    mov [rdi + 8], rdx
    ; move_stack[ply] = 0: null tah nesmie byt klucom pre countermove
    mov rcx, [search_ply]
    lea rdx, [move_stack]
    mov word [rdx + rcx*2], 0
    ; prehod stranu, zrus en passant, prepocitaj hash
    xor byte [side], 1
    mov byte [enpassant], 255
    call compute_hash
    inc qword [search_ply]
    ; search: -negamax(depth-3, -beta, -beta+1, allow_null=0)
    mov rdi, [rbp - 8]
    sub rdi, 3
    mov rsi, [rbp - 24]
    neg rsi
    mov rdx, rsi
    inc rdx                     ; -beta+1
    xor ecx, ecx
    call negamax
    neg eax
    mov ebx, eax            ; uloz skore (unmake null prepise rax)
    dec qword [search_ply]
    ; unmake null
    mov rax, [search_ply]
    shl rax, 4
    lea rdi, [null_stack]
    add rdi, rax
    mov cl, [rdi]
    mov [side], cl
    mov cl, [rdi + 1]
    mov [enpassant], cl
    mov rdx, [rdi + 8]
    mov [position_hash], rdx
    ; fail high? (ale ne mat - ten by mohol byt falesny kvoli zugzwangu)
    cmp ebx, dword [rbp - 24]
    jl .skip_null
    cmp ebx, MATE_SCORE - 100
    jge .skip_null
    mov eax, ebx
    jmp .neg_exit               ; vracia beta (fail-soft)
.skip_null:

    call generate_all_moves
    movzx r15, word [move_count]
    test r15, r15
    jnz .has_moves

    ; ziadne tahy - mat alebo pat
    movzx eax, byte [side]
    call is_in_check
    test rax, rax
    jz .stalemate
    mov eax, dword [search_ply] ; -MATE + ply: rychlejsi mat = lepsie
    sub eax, MATE_SCORE
    ; store matu do TT (EXACT, tah 0): r12 je volny
%if ENABLE_TT = 0
    jmp .mate_no_tt_store
%endif
    mov r12d, eax
    mov rdi, [position_hash]
    mov rsi, [rbp - 8]
    mov edx, r12d
    xor ecx, ecx
    xor r8d, r8d
    call tt_store
 .mate_no_tt_store:
    mov eax, r12d
    jmp .neg_exit
.stalemate:
    ; store patu do TT (EXACT 0)
%if ENABLE_TT = 0
    jmp .stalemate_no_tt_store
%endif
    mov rdi, [position_hash]
    mov rsi, [rbp - 8]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call tt_store
.stalemate_no_tt_store:
    xor eax, eax
    jmp .neg_exit

.has_moves:
    ; lokalna kopia zoznamu tahov, lebo rekurzia prepise globalny move_list
    lea rsi, [move_list]
    lea rdi, [rbp - 584]
    mov rcx, r15
.copy_loop:
    mov ax, [rsi]
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    dec rcx
    jnz .copy_loop

    ; countermove kluc: tah odohrany na ply-1 (0 = root/null ply)
    mov rax, [search_ply]
    test rax, rax
    jz .no_prev_move
    lea rcx, [move_stack]
    movzx eax, word [rcx + rax*2 - 2]
    jmp .prev_move_done
.no_prev_move:
    xor eax, eax
.prev_move_done:
    mov [rbp - 60], eax

    ; --- predvypocet ordering klucov (jeden SEE pass pre brania) ---
    ; kluce: [rbp-1608 + i*4]; zle brania (SEE<0) = kluc SEE < 0 (pod tiche)
    xor rcx, rcx
.key_loop:
    cmp rcx, r15
    jge .key_done

    movzx rax, word [rbp - 584 + rcx*2]
    xor edx, edx                 ; kluc = 0

    mov r9, rax
    shr r9, 12
    and r9, 0xF                  ; flags

    ; promocia?
    cmp r9, FLAG_PROMO_Q
    jb .key_not_promo
    cmp r9, FLAG_PROMO_N
    ja .key_not_promo
    add edx, 80000
.key_not_promo:

    cmp r9, FLAG_ENPASSANT
    je .key_ep                   ; EP: fixne skore (ako povodne), bez SEE

    ; branie?
    movzx edi, ax
    shr rdi, 6
    and edi, 0x3F                ; to
    lea rsi, [board]
    movzx edi, byte [rsi + rdi]
    test edi, edi
    jz .key_quiet

.key_capture:
    ; SEE ordering zlych brani (see < 0 za tiche tahy) je ZATIAL VYPNUTE:
    ; meranie d8 startpos/e4e5 = 8094/22243 uzlov (+29%/+28%) - quiet
    ; ordering v tomto engine nie je dostatocne silny, aby ich predbehol.
    ; Povodny kod: push rcx / call see / pop rcx / test eax,eax /
    ;   js .key_bad_capture / movzx rax, word [rbp - 584 + rcx*2]
    movzx rax, word [rbp - 584 + rcx*2]
    ; dobre branie: 200000 + MVV-LVA (+ live cap_history v selection)
    movzx edi, ax
    shr rdi, 6
    and edi, 0x3F                ; to
    lea rsi, [board]
    movzx edi, byte [rsi + rdi]
    and edi, PIECE_MASK
    lea r9, [q_capture_value]
    mov edi, dword [r9 + rdi*4]
    imul edi, edi, 10
    add edx, 200000
    add edx, edi
    movzx edi, ax
    and edi, 0x3F                ; from
    movzx edi, byte [rsi + rdi]
    and edi, PIECE_MASK
    sub edx, dword [r9 + rdi*4]
    jmp .key_tt_check

.key_ep:
    add edx, 200900              ; pesiak (EP) berie pesiaka
    jmp .key_tt_check

.key_bad_capture:
    ; kluc = SEE (zaporne): pod vsetky tiche tahy, menej zle prve
    add edx, eax
    jmp .key_tt_check

.key_quiet:
    test edx, edx                ; promo bez brania? nechaj 80000
    jnz .key_tt_check

    ; killer bonus
    mov r9, [search_ply]
    cmp r9, 63
    ja .key_countermove
    lea rdi, [killers]
    cmp eax, dword [rdi + r9*8]
    je .key_killer
    cmp eax, dword [rdi + r9*8 + 4]
    jne .key_countermove
.key_killer:
    add edx, 50000
.key_countermove:
    ; countermove heuristic (ply-1; 0 = root/null ply -> preskoc)
    movzx edi, word [rbp - 60]
    test edi, edi
    jz .key_tt_check
    mov r9d, edi
    and r9d, 0x3F                ; prev from
    shl r9d, 6
    shr edi, 6
    and edi, 0x3F                ; prev to
    add edi, r9d
    lea r9, [countermoves]
    movzx edi, word [r9 + rdi*2]
    cmp edi, eax
    jne .key_cont_history
    add edx, 45000               ; pod killerom, nad history

.key_cont_history:
    ; 1-ply continuation history bonus: [prev_to][from][to]
    movzx edi, word [rbp - 60]
    shr edi, 6
    and edi, 0x3F                ; prev to
    shl edi, 12                  ; prev_to * 4096
    mov r9d, eax
    and r9d, 0x3F                ; from
    shl r9d, 6
    add edi, r9d
    mov r9d, eax
    shr r9d, 6
    and r9d, 0x3F                ; to
    add edi, r9d
    lea r9, [cont_history]
    mov esi, dword [r9 + rdi*4]
    sar esi, 2                   ; 1/4 vahy, nech neprebije history/killer/CM
    add edx, esi

    ; 2-ply continuation history bonus: [prev2_to][from][to]
    ; (tah na ply-2, ak existuje; mensia vaha ako 1-ply)
    mov r9, [search_ply]
    cmp r9, 2
    jb .key_tt_check
    lea r8, [move_stack]
    movzx edi, word [r8 + r9*2 - 4]
    test edi, edi
    jz .key_tt_check
    shr edi, 6
    and edi, 0x3F                ; prev2 to
    shl edi, 12                  ; prev2_to * 4096
    mov r9d, eax
    and r9d, 0x3F                ; from
    shl r9d, 6
    add edi, r9d
    mov r9d, eax
    shr r9d, 6
    and r9d, 0x3F                ; to
    add edi, r9d
    lea r9, [cont_history2]
    mov esi, dword [r9 + rdi*4]
    sar esi, 4                   ; 1/16 vahy
    add edx, esi
.key_tt_check:
    cmp r14w, ax                 ; TT tah ma absolutnu prioritu
    jne .key_store
    add edx, 1000000
.key_store:
    mov [rbp - 1608 + rcx*4], edx
    inc rcx
    jmp .key_loop
.key_done:

    mov rbx, -INF           ; best
    xor r13d, r13d          ; best move
    xor rcx, rcx            ; index

    ; cieleny trace White uzla po d4e5 na ply=1
    mov byte [trace_white_active], 0
    cmp byte [trace_white_enable], 0
    je .trace_node_init_done
    cmp qword [search_ply], 0
    jne .trace_node_init_done
    movzx eax, byte [side]
    cmp eax, WHITE
    jne .trace_node_init_done
    cmp byte [trace_root_target], 1
    jne .trace_node_init_done
    mov byte [trace_white_active], 1

    push rbx
    push r12
    push r13
    push r14
    push r15

    lea rdi, [trace_w_init_prefix]
    call write_cstr
    mov rax, rbx
    call trace_print_signed
    lea rdi, [trace_w_alpha_init]
    call write_cstr
    movsxd rax, dword [rbp - 16]
    call trace_print_signed
    lea rdi, [trace_w_stm]
    call write_cstr
    movzx rax, byte [side]
    call print_number
    lea rdi, [trace_w_fen]
    call write_cstr
    call uci_emit_fen
    call trace_nl

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

.trace_node_init_done:

    ; forced-init diagnostika: explicitne znovu nastav klucovy uzlovy stav
    ; (korektny negamax: bez efektu; rozbita init cesta: moze zmenit vysledok)
    mov rbx, -INF
    xor r13d, r13d
    mov rax, [rbp - 16]
    mov [rbp - 16], rax
    mov dword [rbp - 76], 0

.move_loop:
    cmp rcx, r15
    jge .loop_done

    ; selection ordering podla predvypocitanych klucov (swap tah + kluc)
    mov r10, rcx            ; best index
    mov r11d, -1            ; best score
    mov r8, rcx             ; scan index

.sel_loop:
    cmp r8, r15
    jge .sel_done
    movzx eax, word [rbp - 584 + r8*2]
    mov edx, [rbp - 1608 + r8*4]
    ; live tabulky (history/cap_history): deti/grandeti ich pocas slucky
    ; aktualizuju, zamrznute kluce ich preto neobsahuju:
    ;   quiet (flags==0, prazdny ciel)  -> live history[side][from][to]
    ;   ostatne brania (vc. EP/castle/promo brania) -> live cap_history
    ;   promo bez brania, zle brania (kluc < 0) -> len zamrznuty kluc
    test edx, edx
    js .sel_cmp
    mov r9, rax
    shr r9, 12
    and r9, 0xF                  ; flags
    cmp r9, FLAG_ENPASSANT
    je .sel_caplive_ep
    cmp r9, FLAG_PROMO_Q
    jb .sel_flags0               ; flags == 0
    cmp r9, FLAG_PROMO_N
    jbe .sel_promo               ; promo 1-4
    jmp .sel_caplive_to          ; castle (6): obet = board[to]
.sel_flags0:
    movzx edi, ax
    shr rdi, 6
    and edi, 0x3F                ; to
    lea rsi, [board]
    movzx esi, byte [rsi + rdi]
    test esi, esi
    jnz .sel_caplive_v           ; branie
    ; ---- quiet: live history[side][from][to] ----
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
    lea rsi, [history]
    add edx, dword [rsi + rdi*4]
    jmp .sel_cmp
.sel_promo:
    movzx edi, ax
    shr rdi, 6
    and edi, 0x3F                ; to
    lea rsi, [board]
    movzx esi, byte [rsi + rdi]
    test esi, esi
    jz .sel_cmp                  ; promo bez brania: bez live tabuliek
.sel_caplive_v:
    mov r9d, esi
    and r9d, PIECE_MASK
    dec r9d                      ; obet 0..5
    jmp .sel_caplive
.sel_caplive_ep:
    xor r9d, r9d                 ; EP: obet = PESIAK -> index 0
    jmp .sel_caplive
.sel_caplive_to:
    movzx edi, ax
    shr rdi, 6
    and edi, 0x3F                ; to
    lea rsi, [board]
    movzx r9d, byte [rsi + rdi]
    and r9d, PIECE_MASK
    dec r9d
.sel_caplive:
    ; index = (figura-1)*384 + to*6 + obet; figura = board[from]
    movzx edi, ax
    and edi, 0x3F                ; from
    lea rsi, [board]
    movzx edi, byte [rsi + rdi]
    and edi, PIECE_MASK
    dec edi                      ; figura 0..5
    imul edi, edi, 384
    mov esi, eax
    shr esi, 6
    and esi, 0x3F                ; to
    imul esi, esi, 6
    add edi, esi
    add edi, r9d
    lea rsi, [cap_history]
    add edx, dword [rsi + rdi*4]
.sel_cmp:
    cmp edx, r11d
    jle .sel_next
    mov r11d, edx
    mov r10, r8
.sel_next:
    inc r8
    jmp .sel_loop

.sel_done:
    cmp r10, rcx
    je .sel_picked
    mov ax, [rbp - 584 + rcx*2]
    mov dx, [rbp - 584 + r10*2]
    mov [rbp - 584 + rcx*2], dx
    mov [rbp - 584 + r10*2], ax
    mov edx, [rbp - 1608 + rcx*4]
    mov esi, [rbp - 1608 + r10*4]
    mov [rbp - 1608 + rcx*4], esi
    mov [rbp - 1608 + r10*4], edx

.sel_picked:

    movzx rax, word [rbp - 584 + rcx*2]

    ; --- excluded move skip (singular sub-search) ---
    ; ak singular_excl != 0, preskoc excluded tah
    mov edx, dword [singular_excl]
    test edx, edx
    jz .no_excl_skip
    cmp dx, ax                      ; porovnaj 16-bit tah
    jne .no_excl_skip
    inc rcx
    jmp .move_loop
.no_excl_skip:

    ; r12 = 1 ak je to QUIET tah (flags==0 && board[to]==EMPTY) - pre LMR
    xor r12d, r12d
    mov r9d, eax
    shr r9d, 12
    test r9d, r9d
    jnz .quiet_done
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    bt qword [bb_occ], rdi
    jc .quiet_done
    mov r12d, 1
.quiet_done:

    ; --- SEE PRUNING BRANI v hlavnom searchi ---
    ; Pri !in_check preskoc zjavne prehravajuce brania (negativne SEE),
    ; aby sa nefixovali samovrazedne obete do PV.
    cmp dword [rbp - 76], 0
    je .no_cap_see_prune
    cmp dword [rbp - 44], 0
    jne .no_cap_see_prune
    cmp r12d, 1                 ; quiet tahy riesi nizsie quiet SEE prune
    je .no_cap_see_prune
    mov rdx, [rbp - 8]
    cmp rdx, 12
    jg .no_cap_see_prune

    ; rozlis promo non-capture vs capture/EP
    mov r9d, eax
    shr r9d, 12
    and r9d, 0xF
    cmp r9d, FLAG_ENPASSANT
    je .cap_see_is_capture
    cmp r9d, FLAG_PROMO_Q
    jb .cap_see_check_to
    cmp r9d, FLAG_PROMO_N
    ja .cap_see_check_to
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    bt qword [bb_occ], rdi
    jnc .no_cap_see_prune       ; promo bez brania
    jmp .cap_see_is_capture

.cap_see_check_to:
    movzx edi, ax
    shr edi, 6
    and edi, 0x3F
    bt qword [bb_occ], rdi
    jnc .no_cap_see_prune

.cap_see_is_capture:
    imul edx, edx, -120         ; prah = -120 * depth
    push rcx
    push rdx
    call see
    mov esi, eax
    pop rdx
    pop rcx
    movzx rax, word [rbp - 584 + rcx*2]   ; obnov tah pre make_move
    cmp esi, edx
    jge .no_cap_see_prune
    inc rcx
    jmp .move_loop

.no_cap_see_prune:

    ; --- LMP: neskore tiche tahy pri nizkej hlbke preskoc ---
    ; !in_check && quiet && depth <= 2 && index >= 3 + depth^2
%if ENABLE_LMP = 0
    jmp .no_lmp
%endif
    cmp dword [rbp - 76], 0
    je .no_lmp
    cmp r12d, 1
    jne .no_lmp
    cmp dword [rbp - 44], 0
    jne .no_lmp
    mov rdx, [rbp - 8]      ; pozor: rax = aktualny tah pre make_move!
    cmp rdx, 2
    jg .no_lmp
    imul rdx, rdx           ; depth^2
    add rdx, 3
    cmp rcx, rdx
    jl .no_lmp
    inc rcx                 ; preskoc tah
    jmp .move_loop
.no_lmp:

    ; --- FUTILITY PRUNING: beznadejne tiche tahy pri nizkej hlbke preskoc ---
    ; !in_check && quiet && depth <= 2 && index >= 1 &&
    ; static_eval + FUTILITY_MARGIN*depth <= alpha && alpha daleko od matu
%if ENABLE_FUTILITY = 0
    jmp .no_futility
%endif
    cmp dword [rbp - 76], 0
    je .no_futility
    cmp r12d, 1
    jne .no_futility
    cmp dword [rbp - 44], 0
    jne .no_futility
    mov rdx, [rbp - 8]      ; pozor: rax = aktualny tah pre make_move!
    cmp rdx, 2
    jg .no_futility
    test rcx, rcx           ; prvy tah vzdy hladaj (mat/pat detekcia)
    jz .no_futility
    imul edx, edx, FUTILITY_MARGIN  ; margin = 150 * depth (d1: 150, d2: 300)
    cmp dword [rbp - 64], 0         ; improving: eval stupa, prunej menej
    je .fut_margin_ok
    sub edx, FUTILITY_MARGIN        ; margin = 150 * (depth - 1)
.fut_margin_ok:
    add edx, dword [rbp - 56]       ; static eval + margin
    cmp edx, dword [rbp - 16]       ; eval + margin <= alpha?
    jg .no_futility
    cmp dword [rbp - 16], MATE_SCORE - 60
    jge .no_futility        ; alpha blizko matu: neprunej
    inc rcx                 ; preskoc tah
    jmp .move_loop
.no_futility:

    ; --- SEE PRUNING tichych tahov: tiche tahy stracajuce material ---
    ; !in_check && quiet && depth <= 4 && index >= 1 && alpha daleko od
    ; matu && see(tah) < -50*depth (figura skonci en prise bez kompenzacie)
    cmp dword [rbp - 76], 0
    je .no_see_prune
    cmp r12d, 1
    jne .no_see_prune
    cmp dword [rbp - 44], 0
    jne .no_see_prune
    mov rdx, [rbp - 8]      ; pozor: rax = aktualny tah pre make_move!
    cmp rdx, 4
    jg .no_see_prune
    test rcx, rcx           ; prvy tah vzdy hladaj (mat/pat detekcia)
    jz .no_see_prune
    cmp dword [rbp - 16], MATE_SCORE - 60
    jge .no_see_prune       ; alpha blizko matu: neprunej
    imul edx, edx, -100     ; prah = -100 * depth (d4: -400)
    push rcx
    push rdx
    call see                ; ax = tah (tichy; gain[0] = 0)
    mov esi, eax            ; SEE vysledok (see prepisalo rax aj rdx)
    pop rdx                 ; prah
    pop rcx
    movzx rax, word [rbp - 584 + rcx*2]   ; obnov tah pre make_move
    cmp esi, edx
    jge .no_see_prune
    inc rcx                 ; preskoc tah
    jmp .move_loop
.no_see_prune:

    ; --- SINGULAR EXTENSIONS (depth >= 8, TT tah, nie v sachu na tomto uzle) ---
    ; Ak je tento tah TT tahom a TT score je platny, skus singular search:
    ; re-search ostatnych tahov (excluded = tento tah) na depth/2 s oknom
    ; (ttScore - SING_MARGIN, ttScore - SING_MARGIN + 1). Ak fail-low -> extend.
    ; Ak fail-high -> multi-cut prune (beta cutoff).
    ; rcx = index tahov; rax = aktualny tah (pre make_move)
    mov dword [rbp - 72], 0         ; vycisti extension flag
%if ENABLE_SINGULAR = 0
    jmp .no_singular
%endif
    cmp qword [rbp - 8], 8
    jl .no_singular
    cmp dword [rbp - 44], 0         ; nie v sachu
    jne .no_singular
    cmp dword [singular_excl], 0    ; nie v singular sub-searchi
    jne .no_singular
    cmp r14d, 0                     ; mame TT tah
    je .no_singular
    cmp r14w, ax                    ; je to TT tah?
    jne .no_singular
    mov edx, dword [rbp - 48]       ; tt_score
    cmp edx, -31000                 ; platny TT score?
    jle .no_singular
    cmp edx, MATE_SCORE - 200       ; nie mat
    jge .no_singular
    ; sBeta = ttScore - 64
    sub edx, 64
    mov [singular_excl], eax        ; uloz excluded move (tento tah)
    push rax                        ; zachovaj tah
    push rcx                        ; zachovaj index
