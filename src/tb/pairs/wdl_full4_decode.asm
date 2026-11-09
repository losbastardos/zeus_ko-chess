.full4_decode:
    ; full decode pre 4-piece pawnless (enc_type=3 v aktualnych 4-piece TB)
    and ebx, 1                    ; split flag
    mov r13d, ebx                 ; split flag kopia

    ; metadata byte s order nibblami pre bside 0/1
    movzx r10d, byte [rdi]
    mov [tb_wdl_debug_order_byte], r10b

    ; setup_pairs start berieme z parser metadata (tb_find_pairs_probe)
    mov rdi, [tb_wdl_pairs_header_off]
    test rdi, rdi
    jz .not_found
    add rdi, r12
.f4_aligned:
    cmp rdi, rsi
    jae .not_found

    ; board key (vsetky figury)
    lea r8, [tb_piece_key]
    lea rdx, [board]
    xor r14, r14
    xor eax, eax
.f4_board_key_loop:
    cmp eax, 64
    jae .f4_board_key_done
    movzx ecx, byte [rdx + rax]
    test ecx, ecx
    jz .f4_board_key_next
    add r14, [r8 + rcx*8]
.f4_board_key_next:
    inc eax
    jmp .f4_board_key_loop
.f4_board_key_done:

    ; ptr key (pieces[0])
    xor rbx, rbx
    xor eax, eax
.f4_ptr_key_loop:
    cmp eax, [tb_num]
    jae .f4_ptr_key_done
    movzx ecx, byte [tb_pieces + rax]
    add rbx, [r8 + rcx*8]
    inc eax
    jmp .f4_ptr_key_loop
.f4_ptr_key_done:

    ; symmetric test: rovnaky ne-kralovsky material na oboch stranach
    ; (KXvKX symetria, pozri python-chess Table.symmetric)
    call tb_material_symmetric
    mov r11d, eax

    ; bside/cmirror podla key-match vetvy
    movzx eax, byte [side]        ; side: 0=white,1=black, => wtm = !side
    mov edx, eax                  ; edx = side
    xor r8d, r8d                  ; cmirror
    xor r9d, r9d                  ; bside

    test r11d, r11d
    jz .f4_not_symmetric

    ; symmetric: cmirror = (side ? 8 : 0), bside = 0
    test edx, edx
    jz .f4_orient_ready
    mov r8d, 8
    jmp .f4_orient_ready

.f4_not_symmetric:
    cmp r14, rbx
    je .f4_key_match
    mov r8d, 8                    ; cmirror
    mov r9d, edx
    xor r9d, 1                    ; bside = wtm = !side
    jmp .f4_orient_ready

.f4_key_match:
    mov r9d, edx                  ; bside = !wtm = side

.f4_orient_ready:
    mov [tb_wdl_pairs_num_blocks], r9d
    ; order nibble pre zvoleny bside
    mov eax, r10d
    test r9d, r9d
    jz .f4_order_low
    shr eax, 4
.f4_order_low:
    and eax, 0x0f
    mov [tb_wdl_debug_order], eax

    ; setup_pairs pointer + split layout override pre piece tabulky
    mov byte [tb_dec_override_ptrs], 0
    mov rbx, rdi                  ; default header0

    test r13d, r13d
    jz .f4_have_setup

    mov r13d, r9d                 ; save bside cez parser cally
    mov [tb_dec_cmirror_tmp], r8b ; save cmirror

    ; split=1: vypocitaj realne pointery pre slot0/slot1 podla C layoutu
    ; (indextable/sizetable/data su globalne za oboma setup hlavami).
    mov r14, rdi                  ; header0
    mov rdi, r14
    lea rsi, [r12 + r15]
    call tb_parse_pairs_minlen
    test eax, eax
    jz .not_found
    mov r11, r8                   ; header1

    mov rdi, r11
    lea rsi, [r12 + r15]
    call tb_parse_pairs_minlen
    test eax, eax
    jz .not_found
    mov r10, r8                   ; headers_end

    ; size0/size1/size2 pre slot0 (header0, tb_size[0])
    mov qword [tb_dec_slot_size0], 0
    mov qword [tb_dec_slot_size1], 0
    mov qword [tb_dec_slot_size2], 0
    movzx eax, byte [r14]
    test eax, 0x80
    jnz .f4_slot0_done
    movzx ecx, byte [r14 + 2]     ; idxbits
    mov rax, 1
    shl rax, cl
    dec rax
    add rax, [tb_tb_size]
    shr rax, cl
    imul rax, rax, 6
    mov [tb_dec_slot_size0], rax

    mov eax, dword [r14 + 4]      ; real_num_blocks
    mov r8d, eax                   ; real blocks copy
    movzx ecx, byte [r14 + 3]      ; extra blocks
    add eax, ecx                   ; num_blocks
    mov ecx, eax
    mov rax, rcx
    shl rax, 1
    mov [tb_dec_slot_size1], rax

    movzx ecx, byte [r14 + 1]      ; blocksize
    mov rax, 1
    shl rax, cl
    mov ecx, r8d
    imul rax, rcx
    mov [tb_dec_slot_size2], rax
.f4_slot0_done:

    ; size0/size1/size2 pre slot1 (header1, tb_size[1])
    mov qword [tb_dec_slot_size0 + 8], 0
    mov qword [tb_dec_slot_size1 + 8], 0
    mov qword [tb_dec_slot_size2 + 8], 0
    movzx eax, byte [r11]
    test eax, 0x80
    jnz .f4_slot1_done
    movzx ecx, byte [r11 + 2]     ; idxbits
    mov rax, 1
    shl rax, cl
    dec rax
    add rax, [tb_tb_size + 8]
    shr rax, cl
    imul rax, rax, 6
    mov [tb_dec_slot_size0 + 8], rax

    mov eax, dword [r11 + 4]      ; real_num_blocks
    mov r8d, eax                   ; real blocks copy
    movzx ecx, byte [r11 + 3]      ; extra blocks
    add eax, ecx                   ; num_blocks
    mov ecx, eax
    mov rax, rcx
    shl rax, 1
    mov [tb_dec_slot_size1 + 8], rax

    movzx ecx, byte [r11 + 1]      ; blocksize
    mov rax, 1
    shl rax, cl
    mov ecx, r8d
    imul rax, rcx
    mov [tb_dec_slot_size2 + 8], rax
.f4_slot1_done:

    ; layout:
    ; ind0 = headers_end
    ; ind1 = ind0 + size0_0
    ; siz0 = ind1 + size0_1
    ; siz1 = siz0 + size1_0
    ; data0 = align64(siz1 + size1_1)
    ; data1 = align64(data0 + size2_0)
    mov rax, r10
    mov [tb_dec_override_indextable], rax            ; default slot0 ind

    mov rdx, r10
    add rdx, [tb_dec_slot_size0]
    mov [tb_dec_override_sizetable], rdx             ; temp: ind1

    mov rcx, rdx
    add rcx, [tb_dec_slot_size0 + 8]
    mov [tb_dec_override_data], rcx                  ; temp: siz0

    mov r8, rcx
    add r8, [tb_dec_slot_size1]

    mov rax, r8
    add rax, [tb_dec_slot_size1 + 8]
    add rax, 63
    and rax, -64                                      ; data0
    mov rdx, rax
    add rdx, [tb_dec_slot_size2]
    add rdx, 63
    and rdx, -64                                      ; data1

    ; vyber slotu podla bside
    test r13d, r13d
    jz .f4_pick_slot0

    ; slot1: header1 + ind1/siz1/data1
    mov rbx, r11
    mov rax, [tb_dec_override_sizetable]             ; ind1
    mov [tb_dec_override_indextable], rax
    mov rax, r8                                      ; siz1
    mov [tb_dec_override_sizetable], rax
    mov [tb_dec_override_data], rdx                  ; data1
    mov byte [tb_dec_override_ptrs], 1
    mov r9d, r13d
    movzx r8d, byte [tb_dec_cmirror_tmp]
    jmp .f4_have_setup

.f4_pick_slot0:
    ; slot0: header0 + ind0/siz0/data0
    mov rbx, r14
    mov rdx, [tb_dec_override_data]                  ; siz0 (temporary)
    mov [tb_dec_override_sizetable], rdx
    mov [tb_dec_override_data], rax                  ; data0
    mov byte [tb_dec_override_ptrs], 1
    mov r9d, r13d
    movzx r8d, byte [tb_dec_cmirror_tmp]
.f4_have_setup:

    ; priprav board arrays pieces[]/gpos[]
    xor ecx, ecx                  ; count
    xor eax, eax                  ; sq
    lea rdx, [board]
.f4_collect_loop:
    cmp eax, 64
    jae .f4_collect_done
    movzx r11d, byte [rdx + rax]
    test r11d, r11d
    jz .f4_collect_next
    mov [tb_tmp_pieces + rcx*4], r11d
    mov [tb_tmp_gpos + rcx*4], eax
    inc ecx
.f4_collect_next:
    inc eax
    jmp .f4_collect_loop
.f4_collect_done:
    mov [tb_wdl_debug_wk], ecx
    mov eax, [tb_tmp_pieces]
    mov [tb_wdl_debug_bk], eax

    ; mapovanie podla pieces[bside] a cmirror
    lea r11, [tb_pieces]
    test r9d, r9d
    jz .f4_pc_ready
    add r11, 8
.f4_pc_ready:

    xor eax, eax                  ; i
    xor edx, edx                  ; j
.f4_map_i_loop:
    cmp eax, [tb_num]
    jae .f4_map_done
    movzx esi, byte [r11 + rax]

    xor esi, r8d                  ; target piece code

.f4_find_j:
    cmp edx, ecx
    jae .f4_map_notfound
    mov edi, [tb_tmp_pieces + rdx*4]
    cmp edi, esi
    je .f4_found_j
    inc edx
    jmp .f4_find_j
.f4_map_notfound:
    add eax, 100
    mov [tb_wdl_debug_extra], eax
    jmp .not_found

.f4_found_j:
    mov esi, [tb_tmp_gpos + rdx*4]
    mov [tb_tmp_pos + rax*4], esi
    inc edx

    mov esi, [tb_num]
    dec esi
    cmp eax, esi
    jae .f4_map_i_next
    movzx esi, byte [r11 + rax]
    movzx edi, byte [r11 + rax + 1]
    cmp esi, edi
    je .f4_map_i_next
    xor edx, edx

.f4_map_i_next:
    inc eax
    jmp .f4_map_i_loop

.f4_map_done:
    mov eax, [tb_tmp_pos]
    mov [tb_wdl_debug_wk], eax
    mov eax, [tb_tmp_pos + 4]
    mov [tb_wdl_debug_bk], eax
    mov eax, [tb_tmp_pos + 8]
    mov [tb_wdl_debug_extra], eax
    ; encode idx cez general helper
    lea rdi, [tb_norm]
    lea rdx, [tb_factor]
    test r9d, r9d
    jz .f4_norm_ready
    add rdi, 32                   ; 8 * dword
    add rdx, 64                   ; 8 * qword
.f4_norm_ready:
    lea rsi, [tb_tmp_pos]
    mov ecx, r9d
    call tb_encode_piece_idx
    test eax, eax
    jz .not_found
    mov [tb_wdl_debug_idx], rdx

    ; raw symbol decode
    mov rcx, rdx
    mov rdi, rbx
    mov rsi, [tb_map_size]
    add rsi, r12
    mov rdx, [tb_tb_size]
    test r9d, r9d
    jz .f4_tbsize_ok
    mov rdx, [tb_tb_size + 8]
.f4_tbsize_ok:
    call tb_pairs_decode_symbol_idx
    test eax, eax
    jz .not_found
    mov r10d, edx
    jmp .raw_to_class
