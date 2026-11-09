tb_probe_wdl:
    mov byte [tb_dec_override_ptrs], 0
    lea rdi, [tb_sym_cache_state]
    mov ecx, 4096/8
    xor eax, eax
    rep stosq
    lea rdi, [tb_dec_symlen]
    mov ecx, 4096/8
    rep stosq
    push rbx
    push rcx
    push r15
    push r12
    push r13
    push r14

    mov byte [tb_wdl_payload_probe_byte], 0
    mov qword [tb_wdl_payload_probe_off], 0
    mov byte [tb_wdl_header_flags], 0
    mov qword [tb_wdl_pairs_header_off], 0
    mov dword [tb_wdl_pairs_num_blocks], 0
    mov dword [tb_wdl_pairs_num_syms], 0
    mov byte [tb_wdl_pairs_blocksize], 0
    mov byte [tb_wdl_pairs_idxbits], 0
    mov byte [tb_wdl_pairs_is_const], 0
    mov dword [tb_wdl_debug_wk], -1
    mov dword [tb_wdl_debug_bk], -1
    mov dword [tb_wdl_debug_extra], -1
    mov dword [tb_wdl_debug_order], -1
    mov qword [tb_wdl_debug_idx], 0
    mov byte [tb_wdl_debug_order_byte], 0
    mov byte [tb_file_path], 0

    ; Tento krok je zamerany na male (2-4 figurkove) koncovky.
    ; Pri nepoznanych typoch vratime TB_NOT_FOUND.
    call tb_piece_count
    mov [tb_num], eax
    cmp eax, 4
    jg .not_found

    ; Krok 1: legal no-moves guard pred akymkolvek decode.
    ; - stalemate: draw
    ; - checkmate: loss
    call generate_all_moves
    call filter_legal_moves
    movzx eax, word [move_count]
    test eax, eax
    jnz .scan_setup
    movzx eax, byte [side]
    call is_in_check
    test eax, eax
    jnz .loss
    jmp .draw

.scan_setup:
    call tb_material_scan
    mov [tb_nonking], eax
    movzx r13d, byte [tb_board_pieces]
    movzx r14d, byte [tb_board_pieces + 8]

.scan_done:
    ; skus otvorit/mapovat relevantny WDL subor (ak je nastavena cesta)
    call tb_build_wdl_path
    test eax, eax
    jz .not_found
    lea rdi, [tb_file_path]
    call tb_ensure_loaded_path
    test eax, eax
    jnz .not_found

    ; priprav pieces/norm/factor metadata z hlavicky pre dalsi full decode krok
    mov rdi, [tb_map]
    mov rsi, [tb_map_size]
    call tb_setup_pieces_piece
    ; priprava metadata je pre nasledujuce full decode kroky,
    ; aktualny 3-piece tok nesmie padnut ak parser vrati fail

    ; Syzygy regular WDL magic guard + payload probe byte
    mov rdi, [tb_map]
    mov rsi, [tb_map_size]
    mov edx, TB_WDL_MAGIC
    call tb_validate_map_and_probe
    test eax, eax
    jz .not_found
    mov [tb_wdl_payload_probe_off], r8
    mov [tb_wdl_payload_probe_byte], dl

    ; metadata setup_pairs parsera pre dalsi decode krok
    mov rdi, [tb_map]
    mov rsi, [tb_map_size]
    call tb_find_pairs_probe
    test eax, eax
    jz .wdl_meta_done
    mov [tb_wdl_pairs_header_off], r8
    mov [tb_wdl_pairs_num_blocks], r10d
    mov [tb_wdl_pairs_num_syms], r11d
    mov [tb_wdl_pairs_blocksize], bl
    mov [tb_wdl_pairs_idxbits], cl
    cmp eax, 1
    jne .wdl_not_const
    mov byte [tb_wdl_pairs_is_const], 1
    jmp .wdl_meta_done
.wdl_not_const:
    mov byte [tb_wdl_pairs_is_const], 0
.wdl_meta_done:

    mov rax, [tb_map]
    mov dl, byte [rax + 4]
    mov [tb_wdl_header_flags], dl

    ; Prvy realny decode slice: constant setup_pairs tabulky dekodujeme priamo
    ; zo Syzygy streamu (raw symbol -> TB class), bez material heuristik.
    call tb_try_constant_wdl
    cmp eax, TB_NOT_FOUND
    jne .done

.wdl_eval:
    ; legal/stalemate guard pre male koncovky (nutne cez legal moves)
    call generate_all_moves
    call filter_legal_moves
    movzx eax, word [move_count]
    test eax, eax
    jnz .classify
    movzx eax, byte [side]
    call is_in_check
    test eax, eax
    jnz .loss
    jmp .draw

.classify:
    cmp dword [tb_nonking], 1
    ja .not_found

    ; KvK -> draw
    test r13d, r13d
    jnz .white_has_piece
    test r14d, r14d
    jnz .black_has_piece
    mov eax, TB_DRAW
    jmp .done

.white_has_piece:
    test r14d, r14d
    jnz .not_found
    cmp r13d, BISHOP
    je .draw
    cmp r13d, KNIGHT
    je .draw
    cmp r13d, PAWN
    je .pawn_vs_king
    cmp r13d, QUEEN
    je .white_queen
    cmp r13d, ROOK
    je .white_strong
    jmp .not_found

.black_has_piece:
    test r13d, r13d
    jnz .not_found
    cmp r14d, BISHOP
    je .draw
    cmp r14d, KNIGHT
    je .draw
    cmp r14d, PAWN
    je .king_vs_pawn
    cmp r14d, QUEEN
    je .black_queen
    cmp r14d, ROOK
    je .black_strong
    jmp .not_found

.white_queen:
    ; KQvK: zatial klasifikacia heuristikou, payload probe bezi globalne vyssie.
    jmp .white_strong

.black_queen:
    ; KvQK: zatial klasifikacia heuristikou, payload probe bezi globalne vyssie.
    jmp .black_strong

.pawn_vs_king:
    ; KPvK prakticka klasifikacia (bez plneho WDL decode):
    ; ak obranca stihne promotivne policko, povazuj za draw, inak win.
    lea rbx, [board]
    mov r8d, -1              ; white pawn sq
    mov r9d, -1              ; black king sq
    mov r15d, -1             ; white king sq
    xor ecx, ecx
.kpvk_scan:
    cmp ecx, 64
    jae .kpvk_have
    movzx eax, byte [rbx + rcx]
    test eax, eax
    jz .kpvk_next
    mov edx, eax
    and edx, PIECE_MASK
    cmp edx, PAWN
    jne .kpvk_try_king
    test eax, COLOR_MASK
    jnz .kpvk_next
    mov r8d, ecx
    jmp .kpvk_next
.kpvk_try_king:
    cmp edx, KING
    jne .kpvk_next
    test eax, COLOR_MASK
    jz .kpvk_white_king
    mov r9d, ecx
    jmp .kpvk_next
.kpvk_white_king:
    mov r15d, ecx
.kpvk_next:
    inc ecx
    jmp .kpvk_scan

.kpvk_have:
    cmp r8d, 0
    jl .draw
    cmp r9d, 0
    jl .draw
    cmp r15d, 0
    jl .draw

    ; pawn file/rank
    mov eax, r8d
    and eax, 7
    mov r10d, eax            ; pawn file
    mov eax, r8d
    shr eax, 3
    mov r11d, eax            ; pawn rank

    ; black king file/rank
    mov eax, r9d
    and eax, 7
    mov r12d, eax            ; king file
    mov eax, r9d
    shr eax, 3
    mov r13d, eax            ; king rank

    ; okamzita blokada pred pesiakom na rovnakom file = draw
    cmp r12d, r10d
    jne .kpvk_steps
    cmp r13d, r11d
    jle .kpvk_steps
    jmp .draw

.kpvk_steps:
    ; steps do premeny white pawnu
    mov eax, 7
    sub eax, r11d
    mov r14d, eax

    ; king distance ku promotivnemu polu (file pawnu, rank 7)
    mov eax, r12d
    sub eax, r10d
    jns .kpvk_abs_file
    neg eax
.kpvk_abs_file:
    mov edx, eax
    mov eax, r13d
    sub eax, 7
    jns .kpvk_abs_rank
    neg eax
.kpvk_abs_rank:
    cmp edx, eax
    jge .kpvk_have_dist
    mov edx, eax
.kpvk_have_dist:

    ; key-square like guard: ak je white king vysoko pred pesiakom
    ; (6-7 rad) a blizko jeho file, casto ide o forced win.
    cmp r10d, 0
    je .kpvk_skip_keysq
    cmp r10d, 7
    je .kpvk_skip_keysq
    mov eax, r15d
    and eax, 7
    mov ecx, eax                  ; white king file
    mov eax, r15d
    shr eax, 3
    cmp eax, 6
    jb .kpvk_skip_keysq
    mov eax, ecx
    sub eax, r10d
    jns .kpvk_key_abs_wf
    neg eax
.kpvk_key_abs_wf:
    cmp eax, 1
    ja .kpvk_skip_keysq
    mov eax, r12d
    sub eax, r10d
    jns .kpvk_key_abs_bf
    neg eax
.kpvk_key_abs_bf:
    cmp eax, 2
    jl .kpvk_skip_keysq
    jmp .white_strong

.kpvk_skip_keysq:

    ; rook pawn guard: bez blizkeho utocneho krala pri promotivnom poli
    ; su a/h-pesiakove koncovky casto remizove.
    cmp r10d, 0
    je .kpvk_rook_guard
    cmp r10d, 7
    jne .kpvk_after_rook_guard
.kpvk_rook_guard:
    mov eax, r15d
    and eax, 7
    sub eax, r10d
    jns .kpvk_rook_abs_file
    neg eax
.kpvk_rook_abs_file:
    mov ecx, eax
    mov eax, r15d
    shr eax, 3
    sub eax, 7
    jns .kpvk_rook_abs_rank
    neg eax
.kpvk_rook_abs_rank:
    cmp ecx, eax
    jge .kpvk_rook_have_dist
    mov ecx, eax
.kpvk_rook_have_dist:
    cmp ecx, 1
    jbe .kpvk_rook_defender_near
    jmp .kpvk_after_rook_guard

.kpvk_rook_defender_near:
    mov eax, r12d
    sub eax, r10d
    jns .kpvk_rook_bk_abs_file
    neg eax
.kpvk_rook_bk_abs_file:
    mov edx, eax
    mov eax, r13d
    sub eax, 7
    jns .kpvk_rook_bk_abs_rank
    neg eax
.kpvk_rook_bk_abs_rank:
    cmp edx, eax
    jge .kpvk_rook_bk_have_dist
    mov edx, eax
.kpvk_rook_bk_have_dist:
    cmp edx, 1
    jbe .draw

.kpvk_after_rook_guard:

    ; ak white na tahu, obranca ma efektivne o tempo menej
    movzx eax, byte [side]
    test eax, eax
    jnz .kpvk_no_tempo
    dec r14d
.kpvk_no_tempo:
    cmp r14d, 0
    jl .white_strong

    ; Pri blizkom utocnom kralovi nechajme ostrejsiu klasifikaciu.
    mov eax, r15d
    and eax, 7
    sub eax, r10d
    jns .kpvk_atk_absf
    neg eax
.kpvk_atk_absf:
    mov ecx, eax
    mov eax, r15d
    shr eax, 3
    sub eax, r11d
    jns .kpvk_atk_absr
    neg eax
.kpvk_atk_absr:
    cmp ecx, eax
    jge .kpvk_atk_dist_ready
    mov ecx, eax
.kpvk_atk_dist_ready:

    mov eax, r14d
    cmp edx, 4
    jg .kpvk_cmp_ready
    cmp ecx, 1
    jle .kpvk_cmp_ready
    inc eax
.kpvk_cmp_ready:
    cmp edx, eax
    jle .draw
    jmp .white_strong

.king_vs_pawn:
    ; KvPK prakticka klasifikacia, symetria pre cierneho pesiaka.
    lea rbx, [board]
    mov r8d, -1              ; black pawn sq
    mov r9d, -1              ; white king sq
    mov r15d, -1             ; black king sq
    xor ecx, ecx
.kvpk_scan:
    cmp ecx, 64
    jae .kvpk_have
    movzx eax, byte [rbx + rcx]
    test eax, eax
    jz .kvpk_next
    mov edx, eax
    and edx, PIECE_MASK
    cmp edx, PAWN
    jne .kvpk_try_king
    test eax, COLOR_MASK
    jz .kvpk_next
    mov r8d, ecx
    jmp .kvpk_next
.kvpk_try_king:
    cmp edx, KING
    jne .kvpk_next
    test eax, COLOR_MASK
    jz .kvpk_white_king
    mov r15d, ecx
    jmp .kvpk_next
.kvpk_white_king:
    test eax, COLOR_MASK
    jnz .kvpk_next
    mov r9d, ecx
.kvpk_next:
    inc ecx
    jmp .kvpk_scan

.kvpk_have:
    cmp r8d, 0
    jl .draw
    cmp r9d, 0
    jl .draw
    cmp r15d, 0
    jl .draw

    ; pawn file/rank
    mov eax, r8d
    and eax, 7
    mov r10d, eax            ; pawn file
    mov eax, r8d
    shr eax, 3
    mov r11d, eax            ; pawn rank

    ; white king file/rank
    mov eax, r9d
    and eax, 7
    mov r12d, eax            ; king file
    mov eax, r9d
    shr eax, 3
    mov r13d, eax            ; king rank

    ; okamzita blokada pred pesiakom na rovnakom file = draw
    cmp r12d, r10d
    jne .kvpk_steps
    cmp r13d, r11d
    jge .kvpk_steps
    jmp .draw

.kvpk_steps:
    ; steps do premeny black pawnu (na rank 0)
    mov eax, r11d
    mov r14d, eax

    ; king distance ku promotivnemu polu (file pawnu, rank 0)
    mov eax, r12d
    sub eax, r10d
    jns .kvpk_abs_file
    neg eax
.kvpk_abs_file:
    mov edx, eax
    mov eax, r13d
    cmp edx, eax
    jge .kvpk_have_dist
    mov edx, eax
.kvpk_have_dist:

    ; black king file/rank (utocnik)
    mov eax, r15d
    and eax, 7
    mov r8d, eax
    mov eax, r15d
    shr eax, 3
    mov r9d, eax

    ; rook pawn guard: pri a/h pesiakovi bez blizkeho utocneho krala
    ; pri promotivnom poli radsej remiza.
    cmp r10d, 0
    je .kvpk_rook_guard
    cmp r10d, 7
    jne .kvpk_after_rook_guard
.kvpk_rook_guard:
    mov eax, r8d
    sub eax, r10d
    jns .kvpk_rook_abs_file
    neg eax
.kvpk_rook_abs_file:
    mov ecx, eax
    mov eax, r9d
    jns .kvpk_rook_abs_rank
    neg eax
.kvpk_rook_abs_rank:
    cmp ecx, eax
    jge .kvpk_rook_have_dist
    mov ecx, eax
.kvpk_rook_have_dist:
    cmp ecx, 1
    jbe .kvpk_rook_defender_near
    jmp .kvpk_after_rook_guard

.kvpk_rook_defender_near:
    mov eax, r12d
    sub eax, r10d
    jns .kvpk_rook_wk_abs_file
    neg eax
.kvpk_rook_wk_abs_file:
    mov edx, eax
    mov eax, r13d
    jns .kvpk_rook_wk_abs_rank
    neg eax
.kvpk_rook_wk_abs_rank:
    cmp edx, eax
    jge .kvpk_rook_wk_have_dist
    mov edx, eax
.kvpk_rook_wk_have_dist:
    cmp edx, 1
    jbe .draw

.kvpk_after_rook_guard:

    ; ak black na tahu, obranca ma efektivne o tempo menej
    movzx eax, byte [side]
    test eax, eax
    jz .kvpk_no_tempo
    dec r14d
.kvpk_no_tempo:
    cmp r14d, 0
    jl .black_strong
    movzx eax, byte [side]
    test eax, eax
    jnz .kvpk_cmp_strict
    cmp r11d, 5
    jb .kvpk_cmp_white

    ; attacker support near pawn: chebyshev(bk,pawn)
    mov eax, r8d
    sub eax, r10d
    jns .kvpk_bk_absf_ok
    neg eax
.kvpk_bk_absf_ok:
    mov ecx, eax
    mov eax, r9d
    sub eax, r11d
    jns .kvpk_bk_absr_ok
    neg eax
.kvpk_bk_absr_ok:
    cmp ecx, eax
    jge .kvpk_bk_have_dist
    mov ecx, eax
.kvpk_bk_have_dist:
    ; pre pokrocilych pesiakov (rank 6-7) povol decisive iba ked
    ; utocny kral realne vie podporit prechod.
    cmp r11d, 6
    jb .kvpk_rank5_support
    cmp ecx, 3
    jle .black_strong
    jmp .kvpk_cmp_white

.kvpk_rank5_support:
    cmp ecx, 2
    ja .kvpk_cmp_white
    cmp edx, r14d
    jl .kvpk_cmp_white
    jmp .black_strong

.kvpk_cmp_white:
    mov eax, r14d
    inc eax
    cmp edx, eax
    jle .draw
    jmp .black_strong
.kvpk_cmp_strict:
    cmp r11d, 6
    jb .kvpk_cmp_strict_basic

    ; black-to-move advanced pawn: nutna podpora utocneho krala
    mov eax, r8d
    sub eax, r10d
    jns .kvpk_bk_absf_ok_b
    neg eax
.kvpk_bk_absf_ok_b:
    mov ecx, eax
    mov eax, r9d
    sub eax, r11d
    jns .kvpk_bk_absr_ok_b
    neg eax
.kvpk_bk_absr_ok_b:
    cmp ecx, eax
    jge .kvpk_bk_have_dist_b
    mov ecx, eax
.kvpk_bk_have_dist_b:
    cmp ecx, 3
    jle .black_strong

    mov eax, r8d
    sub eax, r10d
    jns .kvpk_bkpromo_absf_ok_b
    neg eax
.kvpk_bkpromo_absf_ok_b:
    mov esi, eax
    mov eax, r9d
    cmp esi, eax
    jge .kvpk_bkpromo_have_b
    mov esi, eax
.kvpk_bkpromo_have_b:
    cmp esi, 2
    jle .black_strong

.kvpk_cmp_strict_basic:

    ; Pri blizkom utocnom kralovi nechajme ostrejsiu klasifikaciu.
    mov eax, r8d
    sub eax, r10d
    jns .kvpk_atk_absf
    neg eax
.kvpk_atk_absf:
    mov ecx, eax
    mov eax, r9d
    sub eax, r11d
    jns .kvpk_atk_absr
    neg eax
.kvpk_atk_absr:
    cmp ecx, eax
    jge .kvpk_atk_dist_ready
    mov ecx, eax
.kvpk_atk_dist_ready:

    mov eax, r14d
    cmp edx, 4
    jg .kvpk_cmp_ready
    cmp ecx, 1
    jle .kvpk_cmp_ready
    inc eax
.kvpk_cmp_ready:
    cmp edx, eax
    jle .draw
    jmp .black_strong

.white_strong:
    movzx eax, byte [side]
    test eax, eax
    jz .win
    jmp .loss

.black_strong:
    movzx eax, byte [side]
    test eax, eax
    jz .loss
    jmp .win

.draw:
    mov eax, TB_DRAW
    jmp .done
.win:
    mov eax, TB_WIN
    jmp .done
.loss:
    mov eax, TB_LOSS
    jmp .done

.not_found:
    mov eax, TB_NOT_FOUND

.done:
    pop r14
    pop r13
    pop r12
    pop r15
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_probe_dtz - DTZ probe (bootstrap)
; Vystup: eax = DTZ alebo TB_NOT_FOUND
; ============================================================
