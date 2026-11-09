tb_probe_dtz:
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
    push r12
    push r13
    push r14

    mov byte [tb_dtz_payload_probe_byte], 0
    mov qword [tb_dtz_payload_probe_off], 0
    mov byte [tb_dtz_header_flags], 0
    mov qword [tb_dtz_pairs_header_off], 0
    mov dword [tb_dtz_pairs_num_blocks], 0
    mov dword [tb_dtz_pairs_num_syms], 0
    mov byte [tb_dtz_pairs_blocksize], 0
    mov byte [tb_dtz_pairs_idxbits], 0
    mov byte [tb_dtz_pairs_is_const], 0
    mov dword [tb_dtz_debug_wk], -1
    mov dword [tb_dtz_debug_bk], -1
    mov dword [tb_dtz_debug_extra], -1
    mov dword [tb_dtz_debug_target_code], -1
    mov dword [tb_dtz_debug_order], -1
    mov byte [tb_dtz_debug_order_byte], 0
    mov qword [tb_dtz_debug_idx], 0
    mov dword [tb_dtz_debug_raw_symbol], 0
    mov dword [tb_dtz_debug_helper_ret], TB_NOT_FOUND
    mov byte [tb_dtz_debug_helper_ok], 0
    mov dword [tb_dtz_debug_nf_code], 0
    mov dword [tb_dtz_debug_bside_used], -1
    mov dword [tb_dtz_debug_flags1], -1
    mov dword [tb_dtz_debug_slot_count], 1
    mov dword [tb_dtz_debug_tb_size], 0
    mov dword [tb_dtz_debug_min_len], 0
    mov dword [tb_dtz_debug_flags], 0
    mov qword [tb_dtz_debug_ptr_wdl_index], 0
    mov qword [tb_dtz_debug_ptr_wdl_size], 0
    mov qword [tb_dtz_debug_ptr_wdl_data], 0
    mov qword [tb_dtz_debug_ptr_dtz_index], 0
    mov qword [tb_dtz_debug_ptr_dtz_size], 0
    mov qword [tb_dtz_debug_ptr_dtz_data], 0
    mov qword [tb_dtz_debug_headers_start], 0
    mov byte [tb_file_path], 0

    ; DTZ bootstrap zatial len pre male 2-3 figurkove koncovky.
    call tb_piece_count
    mov [tb_num], eax
    cmp eax, 4
    jg .not_found

    ; Krok 1: legal no-moves guard pred decode.
    ; - stalemate: dtz class draw (0)
    ; - checkmate: dtz class loss (2)
    call generate_all_moves
    call filter_legal_moves
    movzx eax, word [move_count]
    test eax, eax
    jnz .scan_setup
    movzx eax, byte [side]
    call is_in_check
    test eax, eax
    jnz .nomoves_loss
    xor eax, eax
    jmp .done

.nomoves_loss:
    mov eax, 2
    jmp .done

.scan_setup:

    lea rbx, [board]
    xor r13d, r13d          ; white non-king piece type
    xor r14d, r14d          ; black non-king piece type
    xor ecx, ecx
.scan:
    cmp ecx, 64
    jae .scan_done
    movzx eax, byte [rbx + rcx]
    test eax, eax
    jz .next
    mov edx, eax
    and edx, PIECE_MASK
    cmp edx, KING
    je .next
    test eax, COLOR_MASK
    jz .white_piece
    test r14d, r14d
    jnz .black_more
    mov r14d, edx
    jmp .next
.black_more:
    cmp dword [tb_num], 4
    je .next
    jmp .not_found
.white_piece:
    test r13d, r13d
    jnz .white_more
    mov r13d, edx
    jmp .next
.white_more:
    cmp dword [tb_num], 4
    je .next
    jmp .not_found
.next:
    inc ecx
    jmp .scan

.scan_done:
    ; Pred DTZ mapovanim si zober WDL klasifikaciu rovnakej pozicie.
    ; Vdaka tomu sa DTZ bootstrap vie riadit realnym WDL bez rozbitia
    ; DTZ map_bytes/path diagnostiky.
    call tb_probe_wdl
    mov r12d, eax
    mov rax, [tb_dec_indextable]
    mov [tb_dtz_debug_ptr_wdl_index], rax
    mov rax, [tb_dec_sizetable]
    mov [tb_dtz_debug_ptr_wdl_size], rax
    mov rax, [tb_dec_data]
    mov [tb_dtz_debug_ptr_wdl_data], rax

    ; Postav cestu podla materialu, potom prepni suffix na .rtbz.
    call tb_build_wdl_path
    test eax, eax
    jz .not_found

    lea rbx, [tb_file_path]

    xor rcx, rcx
.len_loop:
    cmp rcx, TB_PATH_MAX - 1
    jae .not_found
    cmp byte [rbx + rcx], 0
    je .have_len
    inc rcx
    jmp .len_loop

.have_len:
    cmp rcx, 1
    jb .not_found
    cmp byte [rbx + rcx - 1], 'w'
    je .to_rtbz
    cmp byte [rbx + rcx - 1], 'z'
    je .load
    jmp .not_found

.to_rtbz:
    mov byte [rbx + rcx - 1], 'z'

.load:
    lea rdi, [tb_file_path]
    call tb_ensure_loaded_path
    test eax, eax
    jnz .not_found

    ; priprav metadata pre dalsi full decode krok (zatial neblokuje fallback tok)
    mov rdi, [tb_map]
    mov rsi, [tb_map_size]
    call tb_setup_pieces_piece

    mov rax, [tb_dec_indextable]
    mov [tb_dtz_debug_ptr_dtz_index], rax
    mov rax, [tb_dec_sizetable]
    mov [tb_dtz_debug_ptr_dtz_size], rax
    mov rax, [tb_dec_data]
    mov [tb_dtz_debug_ptr_dtz_data], rax

    ; Syzygy regular DTZ magic guard + payload probe byte
    mov rdi, [tb_map]
    mov rsi, [tb_map_size]
    mov edx, TB_DTZ_MAGIC
    call tb_validate_map_and_probe
    test eax, eax
    jz .not_found
    mov [tb_dtz_payload_probe_off], r8
    mov [tb_dtz_payload_probe_byte], dl

    ; metadata setup_pairs parsera pre dalsi decode krok
    mov rdi, [tb_map]
    mov rsi, [tb_map_size]
    call tb_find_pairs_probe
    test eax, eax
    jz .dtz_meta_done
    mov [tb_dtz_pairs_header_off], r8
    mov [tb_dtz_pairs_num_blocks], r10d
    mov [tb_dtz_pairs_num_syms], r11d
    mov [tb_dtz_pairs_blocksize], bl
    mov [tb_dtz_pairs_idxbits], cl
    cmp eax, 1
    jne .dtz_not_const
    mov byte [tb_dtz_pairs_is_const], 1
    jmp .dtz_meta_done
.dtz_not_const:
    mov byte [tb_dtz_pairs_is_const], 0
.dtz_meta_done:

    mov rax, [tb_map]
    mov dl, byte [rax + 4]
    mov [tb_dtz_header_flags], dl

    ; Pokus o realny .rtbz decode pre 3-piece pawnless tabulky.
    ; Ak decode zlyha, fallback je konzervativna klasifikacia podla WDL
    ; (bez threshold heuristik pre KPvK/KvPK).
    call tb_try_decode_dtz_3pc
    mov [tb_dtz_debug_helper_ret], eax
    cmp eax, TB_NOT_FOUND
    sete byte [tb_dtz_debug_helper_ok]
    xor byte [tb_dtz_debug_helper_ok], 1
    cmp eax, TB_NOT_FOUND
    je .dtz_3pc_fallback
    cmp eax, DTZ_UNSUPPORTED
    je .dtz_3pc_fallback
    ; signed DTZ -> class (win=1, draw=0, loss=2), konzistentne s fallbackmi
    test eax, eax
    jg .dtz_3pc_win
    jl .dtz_3pc_loss
    xor eax, eax
    jmp .done
.dtz_3pc_win:
    mov eax, 1
    jmp .done
.dtz_3pc_loss:
    mov eax, 2
    jmp .done
.dtz_3pc_fallback:

    cmp r12d, TB_WIN
    je .dtz_win_fallback
    cmp r12d, TB_LOSS
    je .dtz_loss_fallback
    cmp r12d, TB_DRAW
    je .dtz_draw_fallback
    jmp .not_found

.dtz_draw_fallback:
    xor eax, eax
    jmp .done

.dtz_win_fallback:
    mov eax, 1
    jmp .done

.dtz_loss_fallback:
    mov eax, 2
    jmp .done

.not_found:
    mov eax, TB_NOT_FOUND

.done:
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_try_decode_dtz_3pc - realny decode pre 3-piece pawnless DTZ
; Vstup: r12d = WDL class (TB_LOSS/TB_DRAW/TB_WIN), r13d/r14d material
; Vystup: eax = signed DTZ v semantics python-chess probe_dtz (recursive,
;          STM perspektiva), alebo TB_NOT_FOUND/DTZ_UNSUPPORTED
; ============================================================
tb_try_decode_dtz_3pc:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r13
    push r14
    push r15
    push rbp

    ; scope: pawnless 3-4 piece DTZ decode
    mov eax, [tb_num]
    cmp eax, 3
    je .scope3
    cmp eax, 4
    jne .nf

    ; pre 4-piece iba bez pesiakov
    lea rdi, [board]
    xor ecx, ecx
.scope4_scan_pawn:
    cmp ecx, 64
    jae .scope_ok
    movzx eax, byte [rdi + rcx]
    and eax, PIECE_MASK
    cmp eax, PAWN
    je .nf
    inc ecx
    jmp .scope4_scan_pawn

.scope3:
    cmp r13d, PAWN
    je .nf
    cmp r14d, PAWN
    je .nf
    call tb_wdl_is_target_3pc_pawnless
    test eax, eax
    jz .nf

.scope_ok:

    mov r15, [tb_map]
    test r15, r15
    jz .nf
    mov rax, [tb_map_size]
    cmp rax, 16
    jb .nf
    lea r14, [r15 + rax]          ; map_end

    ; Header flags (.rtbz data[4])
    movzx eax, byte [r15 + 4]
    mov ebx, eax
    mov dword [tb_dtz_debug_slot_count], 1

    ; default orientacia (3-piece): bside = side, cmirror = 0
    movzx ecx, byte [side]
    mov r9d, ecx
    mov byte [tb_dec_cmirror_tmp], 0

    ; 4-piece orientacia kopiruje WDL full4 vetvu (symmetric/key-match)
    cmp dword [tb_num], 4
    jne .orient_ready

    lea r8, [tb_piece_key]
    lea rdx, [board]
    xor r10, r10                  ; board key
    xor eax, eax
.f4_key_board_loop:
    cmp eax, 64
    jae .f4_key_board_done
    movzx ecx, byte [rdx + rax]
    test ecx, ecx
    jz .f4_key_board_next
    add r10, [r8 + rcx*8]
.f4_key_board_next:
    inc eax
    jmp .f4_key_board_loop
.f4_key_board_done:

    xor r11, r11                  ; ptr key (pieces[0])
    xor eax, eax
.f4_key_ptr_loop:
    cmp eax, [tb_num]
    jae .f4_key_ptr_done
    movzx ecx, byte [tb_pieces + rax]
    add r11, [r8 + rcx*8]
    inc eax
    jmp .f4_key_ptr_loop
.f4_key_ptr_done:

    ; symmetric test
    mov r8d, 1
    xor eax, eax
.f4_sym_loop:
    cmp eax, [tb_num]
    jae .f4_sym_done
    movzx ecx, byte [tb_pieces + rax]
    xor ecx, 8
    movzx edx, byte [tb_pieces + 8 + rax]
    cmp ecx, edx
    je .f4_sym_next
    xor r8d, r8d
    jmp .f4_sym_done
.f4_sym_next:
    inc eax
    jmp .f4_sym_loop
.f4_sym_done:

    movzx eax, byte [side]
    xor ecx, ecx                  ; cmirror
    xor edx, edx                  ; bside
    test r8d, r8d
    jz .f4_not_sym
    test eax, eax
    jz .f4_orient_store
    mov ecx, 8
    jmp .f4_orient_store

.f4_not_sym:
    cmp r10, r11
    je .f4_key_match
    mov ecx, 8
    mov edx, eax
    xor edx, 1
    jmp .f4_orient_store

.f4_key_match:
    mov edx, eax

.f4_orient_store:
    mov r9d, edx
    mov [tb_dec_cmirror_tmp], cl

.orient_ready:
    mov [tb_dec_bside_tmp], r9b
    mov [tb_dtz_debug_bside_used], r9d

    ; target piece code ako vo WDL full-decode vetve:
    ; white extra -> TYPE, black extra -> TYPE|BLACK
    mov ecx, r13d
    test ecx, ecx
    jnz .target_ready
    mov ecx, r14d
    or ecx, BLACK
.target_ready:
    mov [tb_dtz_debug_target_code], ecx

    ; p_data pre DTZ piece metadata (python init_table_dtz, non-pawn):
    ; start = map+5 (bez split precomp streamu pred pieces).
    lea rbx, [r15 + 5]
    cmp rbx, r14
    jae .nf_102

    cmp rbx, r14
    jae .nf_102
    mov [tb_dtz_debug_headers_start], rbx

    movzx eax, byte [rbx]
    mov [tb_dtz_debug_order_byte], al
    and eax, 0x0f
    mov [tb_dtz_debug_order], eax

    ; precomp setup_pairs zacina za piece metadata: num+1 bajt, align na parny offset
    mov eax, [tb_num]
    lea rdi, [rbx + rax + 1]
    mov rax, rdi
    sub rax, r15
    test al, 1
    jz .have_setup
    inc rdi

.have_setup:
    cmp rdi, r14
    jae .nf_102
    mov rbx, rdi                  ; setup_pairs ptr pre decode

    ; split=1: slot 1 je za prvym setup_pairs streamom
    mov eax, ebx
    and eax, 1
    test eax, eax
    jz .setup_slot_ready
    mov dword [tb_dtz_debug_slot_count], 2
    test r9d, r9d
    jz .setup_slot_ready
    mov rdi, rbx
    mov rsi, r14
    call tb_parse_pairs_minlen
    test eax, eax
    jz .nf_109
    mov rbx, r8

.setup_slot_ready:

    ; p_map = next pointer za precomp setup_pairs streamom
    mov rdi, rbx
    mov rsi, r14
    call tb_parse_pairs_minlen
    test eax, eax
    jz .nf_109
    mov r9, r8
    test r9, r9
    jz .nf_109
    cmp r9, r14
    jae .nf_109
    cmp r9, r15
    jb .nf_109

    ; split + bside0: r9 momentalne ukazuje na druhy setup header, posun na map start
    mov eax, ebx
    and eax, 1
    test eax, eax
    jz .map_start_ready
    movzx ecx, byte [tb_dec_bside_tmp]
    test ecx, ecx
    jnz .map_start_ready
    mov rdi, r9
    mov rsi, r14
    call tb_parse_pairs_minlen
    test eax, eax
    jz .nf_109
    mov r9, r8
    test r9, r9
    jz .nf_109
    cmp r9, r14
    jae .nf_109
    cmp r9, r15
    jb .nf_109

.map_start_ready:

    ; vypocitaj realne pointery pre indextable/sizetable/data v .rtbz:
    ; su za map sekciou, nie hned za setup_pairs streamom.
    mov rdi, r9
    movzx eax, byte [rbx]
    test eax, 2
    jz .maps_done
    test eax, 16
    jnz .maps_u16

    mov ecx, 4
.maps_u8_loop:
    cmp rdi, r14
    jae .nf
    movzx eax, byte [rdi]
    lea rdi, [rdi + rax + 1]
    dec ecx
    jnz .maps_u8_loop
    jmp .maps_done

.maps_u16:
    mov ecx, 4
.maps_u16_loop:
    lea rax, [rdi + 2]
    cmp rax, r14
    ja .nf
    movzx eax, word [rdi]
    lea rdi, [rdi + 2 + rax*2]
    dec ecx
    jnz .maps_u16_loop

.maps_done:
    mov rax, rdi
    sub rax, r15
    test al, 1
    jz .tables_ready
    inc rdi

.tables_ready:
    ; size0 = 6 * num_indices, size1 = 2 * num_blocks
    movzx ecx, byte [rbx + 2]      ; idxbits
    cmp ecx, 31
    ja .nf

    mov rax, [tb_tb_size]
    movzx edx, byte [tb_dec_bside_tmp]
    test edx, edx
    jz .tables_tbsize_ready
    mov rax, [tb_tb_size + 8]
.tables_tbsize_ready:

    mov rdx, 1
    shl rdx, cl
    dec rdx
    add rax, rdx
    shr rax, cl                     ; num_indices
    test rax, rax
    jz .nf
    mov r10, rax
    imul r10, r10, 6                ; size0

    mov eax, dword [rbx + 4]        ; real blocks
    movzx edx, byte [rbx + 3]       ; extra blocks
    add eax, edx
    mov r11d, eax
    mov rax, r11
    shl rax, 1                       ; size1
    mov r8, rax

    mov [tb_dec_override_indextable], rdi
    lea rax, [rdi + r10]
    mov [tb_dec_override_sizetable], rax
    add rax, r8
    add rax, 63
    and rax, -64
    mov [tb_dec_override_data], rax
    mov byte [tb_dec_override_ptrs], 1

    cmp dword [tb_num], 4
    je .idx_full4

    ; najdi WK/BK/extra square
    lea rdx, [board]
    mov r9d, -1                   ; wk
    mov r10d, -1                  ; bk
    mov ecx, [tb_dtz_debug_target_code]
    mov r11d, -1                  ; extra
    xor eax, eax
.scan_board:
    cmp eax, 64
    jae .scan_done
    movzx edi, byte [rdx + rax]
    cmp edi, KING
    jne .chk_bk
    mov r9d, eax
    jmp .scan_next
.chk_bk:
    cmp edi, KING | BLACK
    jne .chk_extra
    mov r10d, eax
    jmp .scan_next
.chk_extra:
    cmp edi, ecx
    jne .scan_next
    mov r11d, eax
.scan_next:
    inc eax
    jmp .scan_board

.scan_done:
    mov [tb_dtz_debug_wk], r9d
    mov [tb_dtz_debug_bk], r10d
    mov [tb_dtz_debug_extra], r11d

    cmp r9d, 0
    jl .nf_105
    cmp r10d, 0
    jl .nf_106
    cmp r11d, 0
    jl .nf_107

    ; idx pre setup_pairs decode
    mov edi, r9d
    mov esi, r10d
    mov edx, r11d
    call tb_encode_111_num3_idx
    test eax, eax
    jz .nf_108
    mov [tb_dtz_debug_idx], rdx

    ; raw symbol decode
    mov rcx, rdx
    mov rdi, rbx
    mov rsi, r14
    mov rdx, 31332
    jmp .decode_raw_symbol

.idx_full4:
    ; mapovanie board -> pos[] v poradi pieces[bside] (+cmirror)
    lea r11, [tb_pieces]
    movzx ecx, byte [tb_dec_bside_tmp]
    test ecx, ecx
    jz .idx_f4_pc_ready
    add r11, 8
.idx_f4_pc_ready:

    lea rdx, [board]
    xor ecx, ecx                  ; count
    xor eax, eax                  ; sq
.idx_f4_collect:
    cmp eax, 64
    jae .idx_f4_collect_done
    movzx edi, byte [rdx + rax]
    test edi, edi
    jz .idx_f4_collect_next
    mov [tb_tmp_pieces + rcx*4], edi
    mov [tb_tmp_gpos + rcx*4], eax
    inc ecx
.idx_f4_collect_next:
    inc eax
    jmp .idx_f4_collect
.idx_f4_collect_done:

    xor eax, eax                  ; i
    xor edx, edx                  ; j
.idx_f4_map_i:
    cmp eax, [tb_num]
    jae .idx_f4_map_done
    movzx esi, byte [r11 + rax]
    movzx edi, byte [tb_dec_cmirror_tmp]
    xor esi, edi
.idx_f4_find_j:
    cmp edx, ecx
    jae .nf
    mov edi, [tb_tmp_pieces + rdx*4]
    cmp edi, esi
    je .idx_f4_found_j
    inc edx
    jmp .idx_f4_find_j
.idx_f4_found_j:
    mov esi, [tb_tmp_gpos + rdx*4]
    mov [tb_tmp_pos + rax*4], esi
    inc edx
    mov esi, [tb_num]
    dec esi
    cmp eax, esi
    jae .idx_f4_map_next
    movzx esi, byte [r11 + rax]
    movzx edi, byte [r11 + rax + 1]
    cmp esi, edi
    je .idx_f4_map_next
    xor edx, edx
.idx_f4_map_next:
    inc eax
    jmp .idx_f4_map_i
.idx_f4_map_done:

    lea rdi, [tb_norm]
    lea rdx, [tb_factor]
    movzx ecx, byte [tb_dec_bside_tmp]
    test ecx, ecx
    jz .idx_f4_norm_ready
    add rdi, 32
    add rdx, 64
.idx_f4_norm_ready:
    lea rsi, [tb_tmp_pos]
    movzx ecx, byte [tb_dec_bside_tmp]
    call tb_encode_piece_idx
    test eax, eax
    jz .nf_108
    mov [tb_dtz_debug_idx], rdx

    ; raw symbol decode pre selected bside
    mov rcx, rdx
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [tb_tb_size]
    movzx ecx, byte [tb_dec_bside_tmp]
    test ecx, ecx
    jz .decode_raw_symbol
    mov rdx, [tb_tb_size + 8]

.decode_raw_symbol:
    mov eax, edx
    mov [tb_dtz_debug_tb_size], eax
    call tb_pairs_decode_symbol_idx
    test eax, eax
    jz .nf_g3
    mov r8d, edx                   ; raw DTZ symbol
    mov ebp, r8d                   ; pracovna kopia symbolu (call moze clobber r8)
    mov [tb_dtz_debug_raw_symbol], r8d
    mov eax, [tb_dec_min_len]
    mov [tb_dtz_debug_min_len], eax

    ; mapovanie symbol->DTZ podla flags setup_pairs
    movzx eax, byte [rbx]
    mov r10d, eax
    mov [tb_dtz_debug_flags], r10d

    ; Krok 2: canonical gate pre nesymetricke DTZ tabulky.
    ; Ak tabulka drzi opacny bside, vrat NOT_FOUND.
    mov eax, r10d
    and eax, 1
    mov [tb_dtz_debug_flags1], eax
    movzx edx, byte [tb_dec_bside_tmp]
    cmp eax, edx
    jne .flags_mismatch
    jmp .flags_ok

.flags_mismatch:
    cmp dword [tb_num], 4
    jne .nf_g1

.flags_ok:

    test r10d, 2
    jz .mapped_ready

    ; WDL_TO_MAP redukcia pre nase triedy: loss->slot1, draw/win->slot0
    xor ecx, ecx
    cmp r12d, TB_LOSS
    jne .slot_ready
    mov ecx, 1
.slot_ready:

    test r10d, 16
    jnz .map_u16

    test r9, r9
    jz .nf
    cmp r9, r14
    jae .nf
    cmp r9, r15
    jb .nf
    mov rdi, r9
    xor edx, edx
.map8_iter:
    cmp edx, ecx
    je .map8_target
    cmp rdi, r14
    jae .nf
    movzx eax, byte [rdi]
    lea rdi, [rdi + rax + 1]
    inc edx
    jmp .map8_iter
.map8_target:
    cmp rdi, r14
    jae .nf
    movzx eax, byte [rdi]
    lea rdi, [rdi + 1]
    cmp ebp, eax
    jae .nf
    movzx ebp, byte [rdi + rbp]
    jmp .mapped_ready

.map_u16:
    test r9, r9
    jz .nf
    cmp r9, r14
    jae .nf
    cmp r9, r15
    jb .nf
    mov rdi, r9
    xor edx, edx
.map16_iter:
    cmp edx, ecx
    je .map16_target
    lea rax, [rdi + 2]
    cmp rax, r14
    ja .nf
    movzx eax, word [rdi]
    lea rdi, [rdi + 2 + rax*2]
    inc edx
    jmp .map16_iter
.map16_target:
    lea rax, [rdi + 2]
    cmp rax, r14
    ja .nf
    movzx eax, word [rdi]
    cmp ebp, eax
    jae .nf
    lea rdi, [rdi + 2 + rbp*2]
    lea rax, [rdi + 2]
    cmp rax, r14
    ja .nf
    movzx ebp, word [rdi]

.mapped_ready:
    ; Krok 2: PA_FLAGS + (s & 1) podmienka.
    ; s reprezentujeme konzervativne z WDL class: {-2, 0, +2}.
    xor edx, edx                   ; s = 0 (draw)
    cmp r12d, TB_WIN
    jne .s_not_win
    mov edx, 2
    jmp .s_ready
.s_not_win:
    cmp r12d, TB_LOSS
    jne .s_ready
    mov edx, -2
.s_ready:

    ; PA_FLAGS redukcia (pre nase triedy: win=4, loss=8, draw=0)
    xor ecx, ecx
    cmp r12d, TB_WIN
    jne .pa_not_win
    mov ecx, 4
    jmp .pa_mask_ready
.pa_not_win:
    cmp r12d, TB_LOSS
    jne .pa_mask_ready
    mov ecx, 8
.pa_mask_ready:
    mov eax, edx
    and eax, 1
    jnz .pa_scale
    test r10d, ecx
    jnz .pa_done
.pa_scale:
    shl ebp, 1
.pa_done:

    ; signed DTZ: win = +(1+res), loss = -(1+res), draw = 0
    cmp r12d, TB_DRAW
    je .signed_draw
    mov eax, ebp
    add eax, 1
    cmp r12d, TB_LOSS
    jne .signed_ready
    neg eax
    jmp .signed_ready

.signed_draw:
    xor eax, eax
    jmp .signed_ready

.signed_ready:
    cmp dword [tb_num], 4
    jne .done

    ; 4-piece kontrakt v engine testoch pouziva triedu 0/1/2.
    ; Realny raw DTZ decode je uz vykonany vyssie.
    test eax, eax
    jz .done
    jg .ret_win_class
    mov eax, 2
    jmp .done

.ret_win_class:
    mov eax, 1
    jmp .done

.nf:
    mov eax, TB_NOT_FOUND

.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

.nf_g1:
    mov dword [tb_dtz_debug_nf_code], 101
    mov eax, DTZ_UNSUPPORTED
    jmp .done

.nf_102:
    mov dword [tb_dtz_debug_nf_code], 102
    jmp .nf

.nf_103:
    mov dword [tb_dtz_debug_nf_code], 103
    jmp .nf

.nf_104:
    mov dword [tb_dtz_debug_nf_code], 104
    jmp .nf

.nf_105:
    mov dword [tb_dtz_debug_nf_code], 105
    jmp .nf

.nf_106:
    mov dword [tb_dtz_debug_nf_code], 106
    jmp .nf

.nf_107:
    mov dword [tb_dtz_debug_nf_code], 107
    jmp .nf

.nf_108:
    mov dword [tb_dtz_debug_nf_code], 108
    jmp .nf

.nf_109:
    mov dword [tb_dtz_debug_nf_code], 109
    jmp .nf

.nf_g3:
    mov dword [tb_dtz_debug_nf_code], 301
    jmp .nf

; ============================================================
; tb_dtz_to_wdl_class - signed DTZ + halfmove -> WDL trieda
; Vstup: eax = signed DTZ (STM perspektiva)
; Vystup: eax = TB_WIN/TB_DRAW/TB_LOSS
; ============================================================
tb_dtz_to_wdl_class:
    test eax, eax
    jz .draw

    movzx ecx, byte [halfmove]
    test eax, eax
    jns .pos

    neg eax
    add ecx, eax
    cmp ecx, 100
    jg .draw
    mov eax, TB_LOSS
    ret

.pos:
    add ecx, eax
    cmp ecx, 100
    jg .draw
    mov eax, TB_WIN
    ret

.draw:
    mov eax, TB_DRAW
    ret

; ============================================================
; tb_piece_count - spocita neprazdne policka na sachovnici
; Vystup: eax = pocet figurok na sachovnici (0..64)
; ============================================================
