; ============================================================
; piece-list helpery (commit 1 infra)
; ============================================================

pl_piece_index_from_piece:
    ; vstup: al = figurka (typ|farba), vystup: eax = [0..11]
    movzx eax, al
    mov edx, eax
    and eax, PIECE_MASK
    dec eax
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add eax, edx
    ret

pl_add_square:
    ; vstup: rdi = piece index [0..11], rsi = square [0..63]
    lea rax, [pl_counts]
    movzx ecx, byte [rax + rdi]
    cmp ecx, 16
    jb .add_ok
    mov rax, SYS_EXIT
    mov rdi, 72
    syscall
.add_ok:
    lea rdx, [pl_lists]
    mov r8, rdi
    shl r8, 4
    add rdx, r8
    mov [rdx + rcx], sil
    inc cl
    mov [rax + rdi], cl
    ret

pl_remove_square:
    ; vstup: rdi = piece index [0..11], rsi = square [0..63]
    push rbx
    lea rax, [pl_counts]
    movzx ecx, byte [rax + rdi]
    test ecx, ecx
    jnz .rm_has
    mov rax, SYS_EXIT
    mov rdi, 73
    syscall
.rm_has:
    lea rdx, [pl_lists]
    mov r8, rdi
    shl r8, 4
    add rdx, r8
    xor r9d, r9d
.rm_scan:
    cmp r9d, ecx
    jl .rm_cmp
    movzx rdi, byte [pl_dbg_stage]
    add rdi, 100
    mov rax, SYS_EXIT
    syscall
.rm_cmp:
    movzx r8d, byte [rdx + r9]
    cmp r8d, esi
    je .rm_found
    inc r9d
    jmp .rm_scan
.rm_found:
    dec ecx
    mov [rax + rdi], cl
    cmp r9d, ecx
    jae .rm_done
    mov r8b, [rdx + rcx]
    mov [rdx + r9], r8b
.rm_done:
    pop rbx
    ret

pl_rebuild_from_board:
    push rbx
    push r12
    ; nulovanie lists+counts+pad (kontig. 240B)
    lea rdi, [pl_lists]
    mov ecx, PL_STATE_SIZE/8
    xor eax, eax
    rep stosq

    lea rbx, [board]
    xor r12d, r12d
.rebuild_loop:
    cmp r12d, 64
    jge .rebuild_done
    movzx eax, byte [rbx + r12]
    test eax, eax
    jz .rebuild_next
    mov edi, eax
    and edi, PIECE_MASK
    dec edi
    mov edx, eax
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add edi, edx
    mov esi, r12d
    call pl_add_square
.rebuild_next:
    inc r12d
    jmp .rebuild_loop
.rebuild_done:
    mov byte [pl_dirty], 0
    pop r12
    pop rbx
    ret

pl_apply_undo_entry:
    ; vstup: rdi = ptr na undo zaznam (base 16B uz vyplnene)
    push rbx
    push r12
    push r13
    push r14
    push r15

    movzx r12d, byte [rdi + 0]  ; from
    movzx r13d, byte [rdi + 1]  ; to
    movzx r14d, byte [rdi + 2]  ; flags
    movzx r15d, byte [rdi + 3]  ; moved_piece
    movzx ebx, byte [rdi + 4]   ; captured_piece

    ; moved remove from
    mov eax, r15d
    and eax, PIECE_MASK
    dec eax
    mov edx, r15d
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add eax, edx
    mov edi, eax
    mov esi, r12d
    mov byte [pl_dbg_stage], 1
    call pl_remove_square

    cmp r14d, FLAG_CASTLE
    je .pl_castle
    cmp r14d, FLAG_ENPASSANT
    je .pl_ep
    cmp r14d, FLAG_PROMO_Q
    jb .pl_normal
    cmp r14d, FLAG_PROMO_N
    jbe .pl_promo

.pl_normal:
    ; moved append to
    mov eax, r15d
    and eax, PIECE_MASK
    dec eax
    mov edx, r15d
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add eax, edx
    mov edi, eax
    mov esi, r13d
    call pl_add_square

    ; capture remove on to (ak existuje)
    test ebx, ebx
    jz .pl_done
    mov eax, ebx
    and eax, PIECE_MASK
    dec eax
    mov edx, ebx
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add eax, edx
    mov edi, eax
    mov esi, r13d
    mov byte [pl_dbg_stage], 2
    call pl_remove_square
    jmp .pl_done

.pl_promo:
    ; pri promocii je moved stale pesiak; na ciel pridaj novu figurku
    ; a pripadne odstran capturovanu figurku na to
    test ebx, ebx
    jz .pl_promo_add
    mov eax, ebx
    and eax, PIECE_MASK
    dec eax
    mov edx, ebx
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add eax, edx
    mov edi, eax
    mov esi, r13d
    mov byte [pl_dbg_stage], 3
    call pl_remove_square

.pl_promo_add:
    ; farebna zlozka podla moved_piece
    mov edx, r15d
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    mov eax, edx
    cmp r14d, FLAG_PROMO_Q
    je .promo_q
    cmp r14d, FLAG_PROMO_R
    je .promo_r
    cmp r14d, FLAG_PROMO_B
    je .promo_b
    ; FLAG_PROMO_N
    add eax, (KNIGHT - 1)
    jmp .promo_add
.promo_q:
    add eax, (QUEEN - 1)
    jmp .promo_add
.promo_r:
    add eax, (ROOK - 1)
    jmp .promo_add
.promo_b:
    add eax, (BISHOP - 1)
.promo_add:
    mov edi, eax
    mov esi, r13d
    call pl_add_square
    jmp .pl_done

.pl_ep:
    ; moved append to
    mov eax, r15d
    and eax, PIECE_MASK
    dec eax
    mov edx, r15d
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add eax, edx
    mov edi, eax
    mov esi, r13d
    call pl_add_square

    ; captured pawn sa odobera z ep square (nie z to)
    mov eax, ebx
    and eax, PIECE_MASK
    dec eax
    mov edx, ebx
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add eax, edx
    mov edi, eax
    mov esi, r13d
    mov edx, r15d
    and edx, COLOR_MASK
    test edx, edx
    jz .ep_white
    add esi, 8
    jmp .ep_rm
.ep_white:
    sub esi, 8
.ep_rm:
    mov byte [pl_dbg_stage], 4
    call pl_remove_square
    jmp .pl_done

.pl_castle:
    ; king append to
    mov eax, r15d
    and eax, PIECE_MASK
    dec eax
    mov edx, r15d
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add eax, edx
    mov edi, eax
    mov esi, r13d
    call pl_add_square

    ; rook presun podla ciela rošády
    mov eax, r15d
    and eax, COLOR_MASK
    shr eax, 3
    imul eax, eax, 6
    add eax, (ROOK - 1)
    mov edi, eax
    cmp r13d, 6
    je .castle_wk
    cmp r13d, 2
    je .castle_wq
    cmp r13d, 62
    je .castle_bk
    ; inak 58
    mov esi, 56
    mov byte [pl_dbg_stage], 8
    call pl_remove_square
    mov esi, 59
    call pl_add_square
    jmp .pl_done
.castle_wk:
    mov esi, 7
    mov byte [pl_dbg_stage], 5
    call pl_remove_square
    mov esi, 5
    call pl_add_square
    jmp .pl_done
.castle_wq:
    mov esi, 0
    mov byte [pl_dbg_stage], 6
    call pl_remove_square
    mov esi, 3
    call pl_add_square
    jmp .pl_done
.castle_bk:
    mov esi, 63
    mov byte [pl_dbg_stage], 7
    call pl_remove_square
    mov esi, 61
    call pl_add_square

.pl_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%if ENABLE_PL_INVARIANT = 1
pl_verify_or_die:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; rebuild do verify buffer
    lea rdi, [pl_verify_lists]
    mov ecx, PL_STATE_SIZE/8
    xor eax, eax
    rep stosq

    lea rbx, [board]
    xor r12d, r12d
.v_build_loop:
    cmp r12d, 64
    jge .v_compare
    movzx eax, byte [rbx + r12]
    test eax, eax
    jz .v_build_next

    mov r13d, eax
    and r13d, PIECE_MASK
    dec r13d
    mov edx, eax
    and edx, COLOR_MASK
    shr edx, 3
    imul edx, edx, 6
    add r13d, edx

    lea r14, [pl_verify_counts]
    movzx r15d, byte [r14 + r13]
    cmp r15d, 16
    jl .v_add_ok
    mov rax, SYS_EXIT
    mov rdi, 75
    syscall
.v_add_ok:
    lea r14, [pl_verify_lists]
    mov eax, r13d
    shl eax, 4
    add r14, rax
    mov [r14 + r15], r12b
    inc r15b
    lea r14, [pl_verify_counts]
    mov [r14 + r13], r15b

.v_build_next:
    inc r12d
    jmp .v_build_loop

.v_compare:
    xor r12d, r12d
.v_piece_loop:
    cmp r12d, 12
    jge .v_ok

    movzx r13d, byte [pl_counts + r12]
    movzx r14d, byte [pl_verify_counts + r12]
    cmp r13d, r14d
    je .v_members
    movzx rdi, byte [pl_dbg_stage]
    add rdi, 200
    mov rax, SYS_EXIT
    syscall

.v_members:
    xor r15d, r15d
.v_mem_loop:
    cmp r15d, r14d
    jge .v_next_piece

    lea rax, [pl_verify_lists]
    mov edx, r12d
    shl edx, 4
    add rax, rdx
    movzx ebx, byte [rax + r15]

    lea rax, [pl_lists]
    mov edx, r12d
    shl edx, 4
    add rax, rdx
    xor ecx, ecx
.v_find_loop:
    cmp ecx, r13d
    jl .v_find_cmp
    movzx rdi, byte [pl_dbg_stage]
    add rdi, 220
    mov rax, SYS_EXIT
    syscall
.v_find_cmp:
    movzx edx, byte [rax + rcx]
    cmp edx, ebx
    je .v_found
    inc ecx
    jmp .v_find_loop
.v_found:
    inc r15d
    jmp .v_mem_loop

.v_next_piece:
    inc r12d
    jmp .v_piece_loop

.v_ok:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
%endif

make_move:
    inc qword [prof_makes]
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r15, rax            ; uloz cely tah

%if ENABLE_PL_INFRA = 1
    ; pri root undo stave synchronizuj piece-list stav z board[64]
    ; (garant korektnosti pre cesty, ktore volaju make_move mimo search root initu)
    cmp qword [undo_sp], 0
    jne .pl_ready
    call pl_rebuild_from_board
.pl_ready:
%endif

    ; vypocitaj adresu undo zaznamu
    lea r14, [undo_stack]
    mov r13, [undo_sp]
    cmp r13, 64*UNDO_ENTRY_SIZE
    jb .undo_space_ok
    ; fail-fast: ochrana proti prepisu pamate za undo_stack
    mov rax, SYS_EXIT
    mov rdi, 70
    syscall
.undo_space_ok:
    lea r12, [r14 + r13]

    ; uloz from, to, flags
    movzx rax, r15w
    and rax, 0x3F
    mov [r12 + 0], al       ; from
    movzx rax, r15w
    shr rax, 6
    and rax, 0x3F
    mov [r12 + 1], al       ; to
    movzx rax, r15w
    shr rax, 12
    mov [r12 + 2], al       ; flags

    ; uloz staru poziciu
    mov al, [side]
    mov [r12 + 5], al
    mov al, [castle]
    mov [r12 + 6], al
    mov al, [enpassant]
    mov [r12 + 7], al
    mov al, [halfmove]
    mov [r12 + 8], al
    mov ax, [fullmove]
    mov [r12 + 9], ax

%if ENABLE_PL_INFRA = 1
    ; scoped snapshot piece-list stavu (240B) do undo entry
    lea rsi, [pl_lists]
    lea rdi, [r12 + UNDO_PL_SNAPSHOT_OFF]
    mov ecx, PL_STATE_SIZE/8
    rep movsq
%endif

    mov rax, r15
    call apply_move

    mov al, [moved_piece]
    mov [r12 + 3], al
    mov al, [captured_piece]
    mov [r12 + 4], al

%if ENABLE_PL_INFRA = 1
    ; update piece-list podla aktualneho undo zaznamu
    mov rdi, r12
    call pl_apply_undo_entry
    mov byte [pl_dirty], 0
%endif

    ; E10/F2: NNUE acc delta (+ undo +11..15); MUSI byt pred akymkolvek
    ; zasahom do position_hash (kontroluje acc_hash == position_hash)
    mov rax, r15
    mov rdi, r12
    call nnue2_move_delta
    mov [nnue_delta_applied], al

    ; E10/F2: hash delta — XOR out stare stavove kluce (side/castle/EP sa
    ; zmeni az v update_position_state)
    call hash_delta_state
    mov rax, r15
    call hash_delta_pieces

    mov rax, r15
    call update_position_state

    ; E10/F2: hash delta — XOR in nove stavove kluce; plny compute_hash
    ; netreba. acc_hash synchronizujeme LEN ak sa NNUE delta aplikovala
    ; (inak acc zostava nepplatny a eval spravi refresh).
    call hash_delta_state
    cmp byte [nnue_delta_applied], 0
    je .acc_sync_done            ; delta sa NEaplikovala -> acc nepplatny
    mov rax, [position_hash]
    mov [nnue_acc_hash], rax
.acc_sync_done:

    ; move_stack[ply] = tah (countermove heuristic; null ply nuluje negamax)
    mov rcx, [search_ply]
    cmp rcx, 64
    jae .skip_move_stack
    lea rdx, [move_stack]
    mov [rdx + rcx*2], r15w
.skip_move_stack:

%if ENABLE_PL_INFRA = 1 && ENABLE_PL_INVARIANT = 1
    movzx eax, r15w
    shr eax, 12
    and eax, 0xF
    add eax, 30
    mov [pl_dbg_stage], al
    call pl_verify_or_die
%endif

    add r13, UNDO_ENTRY_SIZE
    mov [undo_sp], r13

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; unmake_move - obnovi poziciu z undo_stack
; ============================================================
unmake_move:
    inc qword [prof_unmakes]
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rax                ; zachovaj vysledok pre volajuceho (telo ho prepise)

    ; posun sa na posledny undo zaznam
    mov r13, [undo_sp]
    cmp r13, UNDO_ENTRY_SIZE
    jae .undo_has_entry
    ; fail-fast: underflow undo zasobnika
    mov rax, SYS_EXIT
    mov rdi, 71
    syscall
.undo_has_entry:
    sub r13, UNDO_ENTRY_SIZE
    mov [undo_sp], r13
    lea r14, [undo_stack]
    lea r12, [r14 + r13]

    ; najprv nacitaj flags a stav (este mame platny base v r12)
    movzx r8, byte [r12 + 2]    ; flags
    movzx r9, byte [r12 + 5]    ; side
    movzx r10, byte [r12 + 6]   ; castle
    movzx r11, byte [r12 + 7]   ; enpassant
    movzx rbx, byte [r12 + 8]   ; halfmove
    movzx rax, word [r12 + 9]   ; fullmove

    ; nacitaj tahove informacie
    movzx r15, byte [r12 + 3]   ; moved_piece
    movzx r14, byte [r12 + 4]   ; captured_piece

    mov [moved_piece], r15b
    mov [captured_piece], r14b

    ; zrekonstruuj tah (from/to/flags) do r14 — len rcx/r13, rax (fullmove)
    ; sa nesmie prepisat (captured_piece je globalne aj v undo +4)
    movzx r13, byte [r12 + 0]   ; from
    movzx ecx, byte [r12 + 1]   ; to (base v r12 este pouzitelny)
    shl ecx, 6
    mov r14d, r13d
    or r14d, ecx
    mov ecx, r8d
    shl ecx, 12
    or r14d, ecx                ; tah

    ; E10/F2: inverzny NNUE acc delta — MUSI byt pred hash zmenami
    ; (position_hash je este post-move == acc_hash); rdi = undo base.
    ; delta funkcie clobruju r8-r11 -> push okolo (r8=flags, r9-r11=stav).
    mov rdi, r12
    push r8
    push r9
    push r10
    push r11
    push rax                     ; zarovnanie (11 pushov -> 16B)
    mov eax, r14d
    call nnue2_move_delta_inv
    mov [nnue_delta_applied], al
    mov eax, r14d
    call hash_delta_pieces      ; XOR figurkovych klucov (samoinverzne)
    pop rax
    pop r11
    pop r10
    pop r9
    pop r8

    movzx r14, byte [r12 + 4]   ; captured_piece (znova)
    movzx r12d, byte [r12 + 1]  ; to (prepise base)

    ; E10/F2: hash delta — XOR out post-move stavove kluce
    ; POZOR: hash_delta_state clobruje rax (ep vetva necha v eax 255 alebo
    ; ep stlpec) — ax drzi ulozeny fullmove pre restore nizsie, chranit!
    push r8
    push rax
    call hash_delta_state
    pop rax
    pop r8

    ; uloz stav spat do pamate
    mov [side], r9b
    mov [castle], r10b
    mov [enpassant], r11b
    mov [halfmove], bl
    mov [fullmove], ax

    ; inverzna delta eval cache (ax = zrekonstruovany tah z undo zaznamu;
    ; revert sa musi urobit tu, lebo .undo_ep/.undo_castle menia r12)
    mov eax, r13d               ; from
    mov edx, r12d               ; to
    shl edx, 6
    or eax, edx
    mov edx, r8d                ; flags
    shl edx, 12
    or eax, edx

    ; obnov sachovnicu
    lea rsi, [board]
    mov [rsi + r13], r15b       ; board[from] = moved_piece

    cmp r8, FLAG_ENPASSANT
    je .undo_ep
    cmp r8, FLAG_CASTLE
    je .undo_castle

    ; normalny tah / promocia
    mov [rsi + r12], r14b
    jmp .done

.undo_ep:
    mov byte [rsi + r12], EMPTY
    movzx rax, byte [side]
    test rax, rax
    jz .white_ep
    add r12, 8                  ; cierny bral pesiaca na to + 8
    jmp .do_ep
.white_ep:
    sub r12, 8                  ; biely bral pesiaca na to - 8
.do_ep:
    mov [rsi + r12], r14b
    jmp .done

.undo_castle:
    mov byte [rsi + r12], EMPTY
    cmp r12, 6
    je .castle_wk
    cmp r12, 2
    je .castle_wq
    cmp r12, 62
    je .castle_bk
    cmp r12, 58
    je .castle_bq
    jmp .done

.castle_wk:
    mov byte [rsi + 7], ROOK|WHITE
    mov byte [rsi + 5], EMPTY
    jmp .done
.castle_wq:
    mov byte [rsi + 0], ROOK|WHITE
    mov byte [rsi + 3], EMPTY
    jmp .done
.castle_bk:
    mov byte [rsi + 63], ROOK|BLACK
    mov byte [rsi + 61], EMPTY
    jmp .done
.castle_bq:
    mov byte [rsi + 56], ROOK|BLACK
    mov byte [rsi + 59], EMPTY

.done:
    ; E10/F3 invariant: bb stav konzistentny s obnovenym board[64] cez
    ; inkrementalnu xor delta (samoinverzna, side uz je mover).
    ; from/to/flags/moved/captured citame z undo zaznamu (registre
    ; r12-r15 boli na tejto ceste prepisane).
    lea rcx, [undo_stack]
    add rcx, [undo_sp]          ; undo_sp uz ukazuje na platny zaznam
    movzx eax, byte [rcx + 0]   ; from
    movzx edx, byte [rcx + 1]   ; to
    shl edx, 6
    or eax, edx
    movzx edx, byte [rcx + 2]   ; flags
    shl edx, 12
    or eax, edx                 ; 16-bitovy tah
    movzx esi, byte [rcx + 3]   ; moved_piece
    movzx edi, byte [rcx + 4]   ; captured_piece
    call pos_bb_move_delta
    ; E10/F2: hash delta — XOR in obnovene (stare) stavove kluce; plny
    ; compute_hash netreba. acc_hash synchronizujeme len ak sa inverzna
    ; NNUE delta aplikovala (inak acc zostava nepplatny -> refresh v eval).
    push rax
    call hash_delta_state
    cmp byte [nnue_delta_applied], 0
    je .acc_sync_done            ; delta sa NEaplikovala -> acc nepplatny
    mov rax, [position_hash]
    mov [nnue_acc_hash], rax
.acc_sync_done:
%if ENABLE_PL_INFRA = 1
    ; scoped restore piece-list stavu z undo snapshotu
    lea rsi, [undo_stack]
    add rsi, [undo_sp]
    add rsi, UNDO_PL_SNAPSHOT_OFF
    lea rdi, [pl_lists]
    mov ecx, PL_STATE_SIZE/8
    rep movsq
    mov byte [pl_dirty], 0
%endif

%if ENABLE_PL_INFRA = 1 && ENABLE_PL_INVARIANT = 1
    mov byte [pl_dbg_stage], 21
    call pl_verify_or_die
%endif

    pop rax                     ; sparovanie s push rax pred state delta
    pop rax                     ; entry: povodna hodnota pre volajuceho

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; quiescence - alpha-beta na tactical tahoch (capture/promo/ep)
; Vstup:  rdi = q-hlbka, rsi = alpha, rdx = beta
; Vystup: eax = skore
; ============================================================
