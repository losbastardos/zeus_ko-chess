quiescence:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbp, rsp

    inc qword [nodes_searched]
    inc qword [prof_qnodes]
    ; check_time nevolaj na kazdom node: staci periodicky
    mov rax, [nodes_searched]
    and rax, 2047
    jnz .qs_continue
    call check_time
    test eax, eax
    jz .qs_continue
    xor eax, eax
    jmp .qs_exit

.qs_continue:

    ; vynuluj PV pre aktualny ply (qsearch nema pokracovanie)
    mov rax, [search_ply]
    mov qword [pv_len + rax*8], 0

    sub rsp, 544            ; 512B move copy + 32B locals

    mov [rbp - 8], rdi      ; q-depth
    mov [rbp - 16], rsi     ; alpha
    mov [rbp - 24], rdx     ; beta
    mov [rbp - 48], rsi     ; alpha_orig (pre TT bound flag)

    ; je strana na tahu v sachu?
    movzx eax, byte [side]
    call is_in_check
    mov [rbp - 40], rax     ; in_check flag (pozor: nepouzivat rbp-36, prekryva stand-pat)

    ; bezpecnostna podlaha: q-depth nechceme do nekonecna (sachove honenie)
    cmp qword [rbp - 8], -32
    jge .qs_floor_ok
    mov qword [rbp - 8], -32
.qs_floor_ok:

    ; bezpecnostny cap ply: undo_stack ma 64 zaznamov (sachove honenie
    ; v qsearch ply nemusi zastavit ani pri q-depth floor)
    cmp qword [search_ply], 60
    jl .qs_ply_ok
    call search_eval_checked
    movzx ebx, byte [side]
    test ebx, ebx
    jz .qs_ply_done
    neg eax
.qs_ply_done:
    jmp .qs_exit
.qs_ply_ok:
    mov rax, [rbp - 40]     ; obnov in_check (evaluate prepisalo rax)

    ; --- TT PROBE v qsearch ---
    ; depth = 0 marker pre qsearch entries; aj move_only je vzorny
%if ENABLE_TT = 0
    jmp .qs_no_tt_hit
%endif
    mov rdi, [position_hash]
    xor esi, esi            ; depth = 0 (qsearch marker)
    mov rdx, [rbp - 16]
    mov rcx, [rbp - 24]
    call tt_probe
    cmp edx, 1
    jne .qs_tt_probe_move
    ; v sachu sa stand-pat nesmie pouzit (ani z TT score)
    mov rax, [rbp - 40]
    test rax, rax
    jnz .qs_gen
    jmp .qs_tt_score
.qs_tt_probe_move:
    cmp edx, 2
    jne .qs_no_tt_hit
    ; TODO: move-only hint ak bude patria
.qs_no_tt_hit:

    mov rax, [rbp - 40]     ; obnov in_check (tt_probe prepisuje rax)
    test rax, rax
    jnz .qs_gen             ; v sachu: ziadny stand-pat, hladaj evasions

    ; stand-pat evaluacia z pohladu strany na tahu
    call search_eval_checked
    movzx ebx, byte [side]
    test ebx, ebx
    jz .qs_eval_done
    neg eax
.qs_eval_done:
    mov ebx, eax
    mov dword [rbp - 32], eax
    jmp .qs_after_standpat

.qs_tt_score:
    ; TT usable score
    mov ebx, eax
    mov dword [rbp - 32], eax
    jmp .qs_check_standpat

.qs_after_standpat:

.qs_check_standpat:
    cmp ebx, dword [rbp - 24]
    jge .qs_return_standpat

    cmp ebx, dword [rbp - 16]
    jle .qs_after_alpha2
    movsxd rdx, ebx         ; 64-bit ciste ulozenie alpha (hore bez smeti)
    mov [rbp - 16], rdx
.qs_after_alpha2:

    ; q-depth vycerpana a nie v sachu: koniec (stand-pat v alpha)
    cmp qword [rbp - 8], 0
    jg .qs_gen
    mov eax, dword [rbp - 16]
    jmp .qs_exit

.qs_gen:
    call generate_all_moves
    movzx r15, word [move_count]
    test r15, r15
    jz .qs_no_moves

    lea rsi, [move_list]
    lea rdi, [rbp - 544]
    mov rcx, r15
.qs_copy_loop:
    mov ax, [rsi]
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    dec rcx
    jnz .qs_copy_loop

    ; fail-soft qsearch: best inicializuj realnym kandidatom, nie alpha boundom
    mov rax, [rbp - 40]        ; in_check flag
    test rax, rax
    jnz .qs_best_init_check
    mov ebx, dword [rbp - 32]  ; stand-pat ako aktualny best (ak nie sme v sachu)
    jmp .qs_best_init_done
.qs_best_init_check:
    mov ebx, -INF              ; v sachu stand-pat neexistuje
.qs_best_init_done:
    xor rcx, rcx

.qs_move_loop:
    cmp rcx, r15
    jge .qs_done

    ; --- selection ordering: brania (MVV-LVA + cap_history) dopredu ---
    ; (drive sa qsearch prehraval v poradi generovania)
    mov r10, rcx            ; best index
    mov r11d, -1            ; best score
    mov r8, rcx             ; scan index
    lea rsi, [board]

.qs_sel_loop:
    cmp r8, r15
    jge .qs_sel_done

    movzx eax, word [rbp - 544 + r8*2]
    xor edx, edx

    mov r9d, eax
    shr r9d, 12
    and r9d, 0xF

    cmp r9, FLAG_ENPASSANT
    je .qs_sel_ep

    lea edi, [r9d - FLAG_PROMO_Q]
    cmp edi, FLAG_PROMO_N - FLAG_PROMO_Q
    ja .qs_sel_cap_test
    add edx, 80000          ; promocia
.qs_sel_cap_test:
    movzx edi, ax
    shr rdi, 6
    and edi, 0x3F           ; to
    movzx edi, byte [rsi + rdi]
    test edi, edi
    jz .qs_sel_cmp          ; tichy tah: skore 0
    ; MVV-LVA: 200000 + 10*obet - utocnik (zaklad bezpecne nad max.
    ; quiet skore 50k+45k+40k, tiche tahy sa nikdy nemiesaju pred brania)
    and edi, PIECE_MASK
    lea r9, [q_capture_value]
    mov edi, dword [r9 + rdi*4]
    imul edi, edi, 10
    add edx, 200000
    add edx, edi
    movzx edi, ax
    and edi, 0x3F           ; from
    movzx edi, byte [rsi + rdi]
    and edi, PIECE_MASK
    sub edx, dword [r9 + rdi*4]
    ; capture history: cap_history[figura][to][obet]
    movzx edi, ax
    and edi, 0x3F           ; from
    movzx edi, byte [rsi + rdi]
    and edi, PIECE_MASK
    dec edi
    imul edi, edi, 384
    mov r9d, eax
    shr r9d, 6
    and r9d, 0x3F           ; to
    imul r9d, r9d, 6
    add edi, r9d
    mov r9d, eax
    shr r9d, 6
    and r9d, 0x3F
    movzx r9d, byte [rsi + r9]  ; obet
    and r9d, PIECE_MASK
    dec r9d
    add edi, r9d
    lea r9, [cap_history]
    add edx, dword [r9 + rdi*4]
    jmp .qs_sel_cmp

.qs_sel_ep:
    add edx, 200900         ; pesiak (EP) berie pesiaka
    mov r9d, eax
    shr r9d, 6
    and r9d, 0x3F           ; to
    imul r9d, r9d, 6        ; (PAWN-1)*384 + to*6 + (PAWN-1)
    lea rdi, [cap_history]
    add edx, dword [rdi + r9*4]

.qs_sel_cmp:
    cmp edx, r11d
    jle .qs_sel_next
    mov r11d, edx
    mov r10, r8

.qs_sel_next:
    inc r8
    jmp .qs_sel_loop

.qs_sel_done:
    cmp r10, rcx
    je .qs_sel_picked
    mov ax, [rbp - 544 + rcx*2]
    mov dx, [rbp - 544 + r10*2]
    mov [rbp - 544 + rcx*2], dx
    mov [rbp - 544 + r10*2], ax

.qs_sel_picked:
    movzx rax, word [rbp - 544 + rcx*2]

    ; v sachu su vsetky tahy evasions (bez delta pruning)
    cmp qword [rbp - 40], 0
    jne .qs_tactical

    xor edx, edx               ; tactical = 0

    mov r9, rax
    shr r9, 12
    and r9, 0xF
    cmp r9, FLAG_ENPASSANT
    jne .qs_check_promo

    ; delta pruning pre en-passant (zisk pesiaka + rezerva)
%if ENABLE_QDELTA = 0
    jmp .qs_tactical
%endif
    mov r11d, dword [rbp - 32]
    add r11d, 150
    cmp r11d, dword [rbp - 16]
    jle .qs_next
    jmp .qs_tactical

.qs_check_promo:

    cmp r9, FLAG_PROMO_Q
    jb .qs_check_capture
    cmp r9, FLAG_PROMO_N
    jbe .qs_tactical

.qs_check_capture:
    mov r9, rax
    shr r9, 6
    and r9, 0x3F
    lea rsi, [board]
    movzx edx, byte [rsi + r9]
    test edx, edx
    jz .qs_next

    ; delta pruning pre beznu branu figurku
%if ENABLE_QDELTA = 0
    jmp .qs_tactical
%endif
    mov r10d, edx
    and r10d, PIECE_MASK
    lea r11, [q_capture_value]
    mov r10d, dword [r11 + r10*4]
    mov r11d, dword [rbp - 32]
    add r11d, r10d
    add r11d, 50
    cmp r11d, dword [rbp - 16]
    jle .qs_next

.qs_tactical:
    ; SEE pruning: zle vymenne tahy (see < 0) preskoc; v sachu (evasions) nie
    cmp qword [rbp - 40], 0
    jne .qs_do_move
%if ENABLE_SEE_AUDIT = 1
    push rcx
    inc qword [see_audit_calls]
    movzx rax, word [rbp - 544 + rcx*2]
    mov rdx, [position_hash]
    rol rdx, 17
    xor rax, rdx
    or rax, 1
    call see_audit_mark_key
    test eax, eax
    jz .qs_audit_done
    inc qword [see_audit_repeats]
.qs_audit_done:
    pop rcx
%endif
    movzx rax, word [rbp - 544 + rcx*2] ; SEE musi dostat povodny tah v AX
    push rcx
    call see                ; vstup: ax = aktualny tah
    pop rcx
    test eax, eax
    js .qs_next             ; see < 0: zla vymena, preskoc tah
    movzx rax, word [rbp - 544 + rcx*2] ; obnov tah (see vracia skore v eax)
.qs_do_move:
    push rcx
    call make_move
    inc qword [search_ply]

    mov rdi, [rbp - 8]
    dec rdi                 ; q-depth vzdy klesa (ukoncenie aj pri sachovych honoch)
    mov rsi, [rbp - 24]
    neg rsi
    mov rdx, [rbp - 16]
    neg rdx
    call quiescence
    neg eax
    dec qword [search_ply]

    call unmake_move
    pop rcx

    cmp eax, ebx
    jle .qs_alpha_update
    mov ebx, eax

.qs_alpha_update:
    cmp eax, dword [rbp - 16]
    jle .qs_check_cutoff
    movsxd rdx, eax         ; 64-bit ciste ulozenie alpha (hore bez smeti)
    mov [rbp - 16], rdx

.qs_check_cutoff:
    mov edx, dword [rbp - 16]
    cmp edx, dword [rbp - 24]
    jge .qs_done

.qs_next:
    inc rcx
    jmp .qs_move_loop

.qs_no_moves:
    ; ziaden tah: mat (kral v sachu) alebo pat (stand-pat)
    movzx eax, byte [side]
    call is_in_check
    test rax, rax
    jz .qs_stalemate
    mov eax, dword [search_ply]
    sub eax, MATE_SCORE
    jmp .qs_exit
.qs_stalemate:
    mov eax, dword [rbp - 32]
    jmp .qs_exit

.qs_done:
    mov eax, ebx
    jmp .qs_store_tt

.qs_return_standpat:
    mov eax, dword [rbp - 32]

.qs_store_tt:
    ; Store do TT (depth=0 pre qsearch, flag = EXACT/LOWER/UPPER)
%if ENABLE_TT = 0
    jmp .qs_exit
%endif
    mov ecx, TT_EXACT
    cmp eax, dword [rbp - 24]
    jge .qs_tt_lower
    cmp eax, dword [rbp - 48]
    jle .qs_tt_upper
    jmp .qs_tt_flag_done
.qs_tt_upper:
    mov ecx, TT_UPPER
    jmp .qs_tt_flag_done
.qs_tt_lower:
    mov ecx, TT_LOWER
.qs_tt_flag_done:
    push rax
    mov rdi, [position_hash]
    xor esi, esi            ; depth = 0 (qsearch marker)
    mov edx, eax            ; score
    xor r8d, r8d            ; move
    call tt_store
    pop rax

.qs_exit:
    mov rsp, rbp
.qs_fast_exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; negamax - rekurzivny negamax s alpha-beta pruningom
; ============================================================
