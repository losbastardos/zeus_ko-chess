tb_try_constant_wdl:
    push rbx
    push rcx
    push r14
    push r12
    push r15

    mov r12, [tb_map]
    test r12, r12
    jz .not_found
    mov r15, [tb_map_size]
    cmp r15, 16
    jb .not_found

    lea rsi, [r12 + r15]          ; map_end

    ; WDL hlavicka: byte[4] nesie split/files flags.
    movzx ebx, byte [r12 + 4]

    lea rdi, [r12 + 5]            ; data start po magickej hlavicke + flags

    ; Pawnless vetva (bez pesiakov): povodny decode tok, rozsireny
    ; o bezpecny non-constant idxbits==0 slice.
    ; detekcia pesiaka v lubovolnom z ne-kralovskych figurok
    xor eax, eax
.pawn_detect_loop:
    cmp eax, 16
    jae .pawn_detect_done
    movzx ecx, byte [tb_board_pieces + rax]
    cmp ecx, PAWN
    je .pawn_table
    inc eax
    jmp .pawn_detect_loop
.pawn_detect_done:

    ; Pawnless 3/4-piece tabulky (KXvK aj opacne) dekodujeme jednotne
    ; cez full4 tok: setup pieces/norm/factor + KK_IDX/111 encode.
    ; KvK (num=2) ostava na legacy constant/uniform-root slice.
    cmp dword [tb_num], 3
    jae .full4_decode

    jmp .pawnless_legacy

    ; full decode pre KQ/KR/KB/KN vs K (aj opacne)
    and ebx, 1                    ; split flag

    ; metadata byte s order nibblami pre bside 0/1
    movzx r10d, byte [rdi]
    mov [tb_wdl_debug_order_byte], r10b

    ; piece-entry metadata: num + 1 bajt, potom align na parny offset
    mov ecx, 2
    test r13d, r13d
    jz .fd_no_white
    inc ecx
.fd_no_white:
    test r14d, r14d
    jz .fd_no_black
    inc ecx
.fd_no_black:
    lea rax, [rcx + 1]
    add rdi, rax
    mov rax, rdi
    sub rax, r12
    test al, 1
    jz .fd_aligned
    inc rdi
.fd_aligned:
    cmp rdi, rsi
    jae .not_found

    ; bside vyber podla key-match vetvy (ako probe.c):
    ;   board_key == pieces[0]_key -> bside = side   (!wtm vetva)
    ;   inak                        -> bside = !side  (wtm vetva, cmirror=8;
    ;                                   idx je geometricky, cmirror netreba)
    lea r8, [tb_piece_key]
    lea rdx, [board]
    xor r9d, r9d                  ; board key
    xor eax, eax
.fd_board_key_loop:
    cmp eax, 64
    jae .fd_board_key_done
    movzx ecx, byte [rdx + rax]
    test ecx, ecx
    jz .fd_board_key_next
    add r9, [r8 + rcx*8]
.fd_board_key_next:
    inc eax
    jmp .fd_board_key_loop
.fd_board_key_done:
    xor r11d, r11d                ; pieces[0] key
    xor eax, eax
.fd_ptr_key_loop:
    cmp eax, [tb_num]
    jae .fd_ptr_key_done
    movzx ecx, byte [tb_pieces + rax]
    add r11, [r8 + rcx*8]
    inc eax
    jmp .fd_ptr_key_loop
.fd_ptr_key_done:
    movzx eax, byte [side]
    cmp r9, r11
    je .fd_have_bside             ; key match: bside = side
    xor eax, 1                    ; key mismatch: bside = !side
.fd_have_bside:
    mov r11d, eax

    ; order nibble pre zvoleny bside (iba 0/1 pre enc_type=2,num=3)
    mov eax, r10d
    test r11d, r11d
    jz .fd_low_order
    shr eax, 4
.fd_low_order:
    and eax, 0x0f
    cmp eax, 1
    ja .not_found
    mov r10d, eax
    mov [tb_wdl_debug_order], r10d

    ; setup_pairs pointer podla bside (pre split=1)
    mov rbx, rdi
    test r11d, r11d
    jz .fd_have_setup
    mov rdi, rbx
    call tb_parse_pairs_minlen
    test eax, eax
    jz .not_found
    mov rbx, r8
.fd_have_setup:

    ; najdi WK/BK/extra square
    lea rdx, [board]
    mov r8d, -1                   ; wk
    mov r9d, -1                   ; bk
    mov eax, r13d
    test eax, eax
    jz .fd_extra_black
    mov ecx, r13d
    jmp .fd_extra_code_ready
.fd_extra_black:
    mov ecx, r14d
    or ecx, BLACK
.fd_extra_code_ready:
    mov r11d, -1                  ; extra
    xor eax, eax
.fd_scan:
    cmp eax, 64
    jae .fd_scan_done
    movzx edi, byte [rdx + rax]
    cmp edi, KING
    jne .fd_not_wk
    mov r8d, eax
    jmp .fd_next
.fd_not_wk:
    cmp edi, KING | BLACK
    jne .fd_not_bk
    mov r9d, eax
    jmp .fd_next
.fd_not_bk:
    cmp edi, ecx
    jne .fd_next
    mov r11d, eax
.fd_next:
    inc eax
    jmp .fd_scan

.fd_scan_done:
    mov [tb_wdl_debug_wk], r8d
    mov [tb_wdl_debug_bk], r9d
    mov [tb_wdl_debug_extra], r11d

    cmp r8d, 0
    jl .not_found
    cmp r9d, 0
    jl .not_found
    cmp r11d, 0
    jl .not_found

    mov edi, r8d
    mov esi, r9d
    mov edx, r11d
    mov ecx, r10d
    call tb_encode_k2_num3_idx
    test eax, eax
    jz .not_found
    mov [tb_wdl_debug_idx], rdx

    ; tb_size pre enc_type=2,num=3: 462 * 62 = 28644
    mov rcx, rdx                  ; idx
    mov rdi, rbx                  ; setup_pairs ptr
    lea rsi, [r12 + r15]          ; map_end (rsi mohol byt clobbered encode helperom)
    mov rdx, 28644
    call tb_pairs_decode_symbol_idx
    test eax, eax
    jz .not_found
    mov r10d, edx
    jmp .raw_to_class

%include "tb/pairs/wdl_full4_decode.asm"

.pawnless_legacy:

    and ebx, 1                    ; split flag

    ; piece-entry metadata pre pawnless vetvu: num + 1 bajt, potom align na parny offset
    mov ecx, 2                    ; obe kralovske figurky
    test r13d, r13d
    jz .no_white_extra
    inc ecx
.no_white_extra:
    test r14d, r14d
    jz .no_black_extra
    inc ecx
.no_black_extra:
    lea rax, [rcx + 1]
    add rdi, rax
    mov rax, rdi
    sub rax, r12
    test al, 1
    jz .aligned
    inc rdi
.aligned:
    cmp rdi, rsi
    jae .not_found

    ; precomp[0]
    mov rbx, rdi
    call tb_parse_pairs_minlen
    test eax, eax
    jz .not_found
    cmp eax, 1
    je .pc0_const
    movzx eax, byte [rbx + 2]      ; idxbits
    test eax, eax
    jz .pc0_minlen
    mov rdi, r10
    mov esi, r9d
    call tb_pairs_uniform_root
    test eax, eax
    jz .not_found
    movzx r10d, dl
    jmp .pc0_ok
.pc0_const:
.pc0_minlen:
    mov r10d, edx                 ; raw0
.pc0_ok:

    test ebx, ebx
    jz .choose_done_single

    ; split: precomp[1]
    mov rdi, r8
    mov rbx, rdi
    call tb_parse_pairs_minlen
    test eax, eax
    jz .not_found
    cmp eax, 1
    je .pc1_const
    movzx eax, byte [rbx + 2]      ; idxbits
    test eax, eax
    jz .pc1_minlen
    mov rdi, r10
    mov esi, r9d
    call tb_pairs_uniform_root
    test eax, eax
    jz .not_found
    movzx r11d, dl
    jmp .pc1_ok
.pc1_const:
.pc1_minlen:
    mov r11d, edx                 ; raw1
.pc1_ok:

    cmp r10d, r11d
    je .choose_min0

    ; Konzervativny guard: ak sa split precomp vetvy rozidu a jedna vetva
    ; vracia draw (raw=2), preferuj draw. Toto znizuje falesne LOSS triedy
    ; v hraničných asymetrických 3-piece poziciach.
    cmp r10d, 2
    je .choose_min0
    cmp r11d, 2
    jne .choose_bside
    mov r10d, r11d
    jmp .choose_min0

.choose_bside:

    ; Aproximacia bside vyberu pre asymetricke materialy:
    ; pri key match vetve v syzygy probe je bside = !wtm.
    movzx eax, byte [side]
    test eax, eax
    jz .choose_min1               ; white na tahu -> bside=1 -> precomp[1]
    jmp .choose_min0              ; black na tahu -> bside=0 -> precomp[0]

.choose_min1:
    mov r10d, r11d

.choose_min0:

.choose_done_single:
    jmp .raw_to_class

.pawn_table:
    ; Pawnful tabulky (3-piece KPvK/KvPK aj 4-piece) dekodujeme jednotne
    ; cez pawn4 tok: file bucket + tb_setup_pieces_pawn + tb_encode_pawn_idx.
    cmp dword [tb_num], 3
    jb .not_found
    cmp dword [tb_num], 4
    ja .not_found
    jmp .pawn4_table

.pawn3_table:
    mov byte [tb_wdl_pairs_is_const], 4
    ; 3-piece pawn scope: KPvK/KvPK. Vyberieme setup_pairs slot
    ; rovnako ako probe.c (file bucket + bside), ale realny variable-bit
    ; decode (idxbits>0) zatial neriesime v tomto kroku.
    movzx eax, byte [r12 + 4]
    mov r11d, eax                 ; flags
    and eax, 0x02
    jz .not_found                 ; bez files flagu nie je nas current scope

    ; files=4, split=bit0
    mov eax, r11d
    and eax, 1
    mov r8d, eax                  ; split flag

    ; metadata pre pawn tabulky: files * (num + s)
    ; current scope: num=3, s=1 (jedna strana ma presne jedneho pesiaka)
    add rdi, 16
    mov rax, rdi
    sub rax, r12
    test al, 1
    jz .pawn_aligned
    inc rdi
.pawn_aligned:
    cmp rdi, rsi
    jae .not_found
    mov [tb_dec_headers_start_tmp], rdi

    ; urci cmirror/mirror/bside podla key-match vetvy (probe.c)
    lea rbx, [board]
    xor r10, r10                   ; board key
    xor eax, eax
.pawn_key_board_scan:
    cmp eax, 64
    jae .pawn_key_board_done
    movzx edx, byte [rbx + rax]
    test edx, edx
    jz .pawn_key_board_next
    lea rsi, [tb_piece_key]
    add r10, [rsi + rdx*8]
.pawn_key_board_next:
    inc eax
    jmp .pawn_key_board_scan

.pawn_key_board_done:
    lea rsi, [tb_piece_key]
    xor r11, r11                   ; ptr key (file[0].pieces[0])
    movzx eax, byte [r12 + 6]
    and eax, 0x0f
    add r11, [rsi + rax*8]
    movzx eax, byte [r12 + 7]
    and eax, 0x0f
    add r11, [rsi + rax*8]
    movzx eax, byte [r12 + 8]
    and eax, 0x0f
    add r11, [rsi + rax*8]

    mov byte [tb_dec_cmirror_tmp], 0
    mov byte [tb_dec_mirror_tmp], 0
    movzx edx, byte [side]         ; key-match vetva: bside=!wtm (wtm = !side)
    cmp r10, r11
    je .pawn_side_ready
    mov byte [tb_dec_cmirror_tmp], 8
    mov byte [tb_dec_mirror_tmp], 56
    movzx edx, byte [side]         ; key-mismatch vetva: bside=wtm = !side
    xor edx, 1
.pawn_side_ready:
    mov [tb_dec_bside_tmp], dl
    mov r11d, edx                  ; bside 0/1

    ; najdi square pesiaka podla pieces[0] a cmirror, potom aplikuj mirror
    movzx eax, byte [r12 + 6]      ; file[0].pieces[0][0], low nibble
    and eax, 0x0f
    movzx edx, byte [tb_dec_cmirror_tmp]
    xor eax, edx
    mov r9d, -1
    xor edx, edx
.pawn_sq_scan:
    cmp edx, 64
    jae .pawn_sq_done
    movzx ecx, byte [rbx + rdx]
    cmp ecx, eax
    jne .pawn_sq_next
    mov ecx, edx
    movzx esi, byte [tb_dec_mirror_tmp]
    xor ecx, esi
    mov r9d, ecx
    jmp .pawn_sq_done
.pawn_sq_next:
    inc edx
    jmp .pawn_sq_scan

.pawn_sq_done:
    cmp r9d, 0
    jl .not_found
    mov eax, r9d
    and eax, 7
    cmp eax, 3
    jle .file_ok
    mov edx, 7
    sub edx, eax
    mov eax, edx
.file_ok:
    mov r10d, eax                 ; file bucket 0..3
    mov r14d, eax                 ; uloz file bucket
    mov [tb_dec_file_tmp], al     ; file bucket pre neskorsie pieces[] mapovanie

    ; target precomp index v poradi setup_pairs streamu
    ; order: file0[pre0,pre1], file1[pre0,pre1], ... (ak split)
    mov eax, r10d
    shl eax, 1
    test r8d, r8d
    jnz .idx_add_bside
    shr eax, 1
    xor r11d, r11d                ; pri non-split sa pouzije precomp[0]
.idx_add_bside:
    add eax, r11d
    mov [tb_dec_target_tmp], eax  ; target index

    ; order nibble pre dany file bucket + bside (0..2)
    lea rax, [r12 + 5]
    lea rax, [rax + r14*4]
    movzx edx, byte [rax]
    test r11d, r11d
    jz .pawn_order_low
    shr edx, 4
.pawn_order_low:
    and edx, 0x0f
    cmp edx, 2
    ja .not_found
    mov r14d, edx                 ; order 0..2

    ; pocet precomp slotov
    mov eax, 4
    test r8d, r8d
    jz .have_slots
    shl eax, 1
.have_slots:
    mov r11d, eax                 ; slot_count
    mov [tb_dec_slot_count_tmp], r11d

    xor ecx, ecx                  ; current index
.pawn_parse_loop:
    cmp ecx, r11d
    jae .not_found

    lea rsi, [r12 + r15]          ; map_end pre tb_parse_pairs_minlen
    mov rbx, rdi
    push rcx
    call tb_parse_pairs_minlen
    mov edx, eax
    pop rcx
    test edx, edx
    jnz .pawn_parse_ok
    mov byte [tb_wdl_pairs_is_const], 7
    jmp .not_found
.pawn_parse_ok:

    cmp ecx, [tb_dec_target_tmp]
    jne .pawn_next

    ; priprav realne indextable/sizetable/data pointery pre target slot
    mov rdi, [tb_dec_headers_start_tmp]
    lea rsi, [r12 + r15]
    mov edx, [tb_dec_slot_count_tmp]
    mov ecx, [tb_dec_target_tmp]
    mov r8, 23436
    call tb_pairs_prepare_pawn_override
    test eax, eax
    jz .not_found

    mov byte [tb_wdl_pairs_is_const], 5

    ; Poradie kralov musi ist podla pieces[] nibblov pre dany file+bside.
    ; data chunk na file ma 4 bajty: [order][p0][p1][p2].
    movzx edx, byte [tb_dec_file_tmp]
    lea rax, [r12 + 5]
    lea rax, [rax + rdx*4]
    lea rax, [rax + 2]            ; p1
    movzx edx, byte [rax]
    movzx ecx, byte [rax + 1]     ; p2
    movzx eax, byte [tb_dec_bside_tmp]
    test eax, eax
    jz .pawn_piece_nibbles_ready
    shr edx, 4
    shr ecx, 4
.pawn_piece_nibbles_ready:
    and edx, 0x0f
    and ecx, 0x0f

    ; p1/p2 -> realne board codes cez cmirror; sq -> pos cez mirror
    movzx eax, byte [tb_dec_cmirror_tmp]
    xor edx, eax
    xor ecx, eax
    mov r11d, edx                 ; expected code pieces[1]
    mov esi, ecx                  ; expected code pieces[2]

    lea rax, [board]
    mov r8d, -1                   ; pos1
    mov r10d, -1                  ; pos2
    xor edx, edx
.pawn_find_kings:
    cmp edx, 64
    jae .pawn_kings_done
    movzx ecx, byte [rax + rdx]
    cmp ecx, r11d
    jne .pawn_chk_k2
    mov ecx, edx
    movzx edi, byte [tb_dec_mirror_tmp]
    xor ecx, edi
    mov r8d, ecx
    jmp .pawn_kings_next
.pawn_chk_k2:
    cmp ecx, esi
    jne .pawn_kings_next
    mov ecx, edx
    movzx edi, byte [tb_dec_mirror_tmp]
    xor ecx, edi
    mov r10d, ecx
.pawn_kings_next:
    inc edx
    jmp .pawn_find_kings

.pawn_kings_done:
    cmp r8d, 0
    jl .not_found
    cmp r10d, 0
    jl .not_found
    mov esi, r8d
    mov edx, r10d

    mov edi, r9d                  ; pawn sq
    mov ecx, r14d                 ; order nibble 0..2
    call tb_encode_pawn1_num3_idx
    test eax, eax
    jz .not_found

    mov [tb_wdl_pairs_num_syms], edx
    mov eax, [tb_dec_target_tmp]
    mov [tb_wdl_pairs_num_blocks], eax

    mov rcx, rdx
    mov rdi, rbx
    lea rsi, [r12 + r15]          ; map_end (rsi mohol byt clobbered encode helperom)
    mov rdx, 23436
    call tb_pairs_decode_symbol_idx
    test eax, eax
    jnz .pawn_decode_ok
    mov [tb_wdl_pairs_blocksize], dl
    mov byte [tb_wdl_pairs_is_const], 9
    jmp .not_found
.pawn_decode_ok:
    mov byte [tb_wdl_pairs_is_const], 6
    mov r10d, edx
    jmp .raw_to_class

.pawn_next:
    mov rdi, r8
    inc ecx
    jmp .pawn_parse_loop

.pawn4_table:
    ; 4-piece pawnful: podpora 1 pesiak + 1 figura + 2 krali
    ; (KBPvK, KNPvK, KQPvK, KRPvK, KBvKP, KNvKP, KQvKP, KRvKP)
    ; Pre KPPvK/KPvKP zatial fallback.

    ; spocitaj bielych a ciernych pesiakov
    lea rax, [board]
    xor r8d, r8d                  ; white pawns
    xor r9d, r9d                  ; black pawns
    xor ecx, ecx
.count_pawns:
    cmp ecx, 64
    jae .count_done
    movzx edx, byte [rax + rcx]
    test edx, edx
    jz .count_next
    mov ebx, edx
    and ebx, PIECE_MASK
    cmp ebx, PAWN
    jne .count_next
    test edx, COLOR_MASK
    jnz .count_black
    inc r8d
    jmp .count_next
.count_black:
    inc r9d
.count_next:
    inc ecx
    jmp .count_pawns
.count_done:
    mov r10d, r8d                 ; bielych pesiacov
    mov r11d, r9d                 ; ciernych pesiacov
    lea r8, [board]               ; board pointer pre dalsi scan
    lea r9, [r12 + 6]             ; pieces data file0 (ptr_key)

    ; Syzygy pawns[0]/pawns[1] swap pravidlo
    test r11d, r11d
    jz .pawns_ready
    test r10d, r10d
    jz .do_swap
    cmp r11d, r10d
    jae .pawns_ready
.do_swap:
    mov eax, r10d
    mov r10d, r11d
    mov r11d, eax
.pawns_ready:
    cmp r11d, 1
    ja .not_found
    cmp r10d, 1
    je .p4_pawn_count_ok
    cmp r10d, 2
    jne .not_found
    test r11d, r11d
    jnz .not_found
.p4_pawn_count_ok:
    mov [tb_pawns0], r10d         ; uloz pawns0/pawns1 pre setup
    mov [tb_pawns1], r11d

    ; nacitaj pieces[0] z file=0, bside=0 pre key match a lead pawn
    mov r12, [tb_map]
    lea rsi, [r12 + 5]            ; data start
    ; s = 1 + (pawns1 > 0); record size = num + s
    mov ebx, 1
    cmp dword [tb_pawns1], 0
    je .p4_have_s_key
    inc ebx
.p4_have_s_key:
    mov eax, [tb_num]
    add eax, ebx
    ; pieces bajty zacinaju za order bajtmi
    lea r9, [rsi + rbx]           ; pieces data file0

    ; ptr_key = sum tb_piece_key[pieces0[i]]
    xor r11, r11                  ; ptr_key
    xor ecx, ecx
.ptr_key_loop:
    cmp ecx, [tb_num]
    jae .ptr_key_done
    movzx eax, byte [r9 + rcx]
    and eax, 0x0f                 ; bside 0 low nibble
    lea rdx, [tb_piece_key]
    add r11, [rdx + rax*8]
    inc ecx
    jmp .ptr_key_loop
.ptr_key_done:

    ; board_key = sum tb_piece_key[board[i]]
    xor r10, r10                  ; board_key
    xor ecx, ecx
.board_key_loop:
    cmp ecx, 64
    jae .board_key_done
    movzx edi, byte [r8 + rcx]
    test edi, edi
    jz .board_key_next
    lea rdx, [tb_piece_key]
    add r10, [rdx + rdi*8]
.board_key_next:
    inc ecx
    jmp .board_key_loop
.board_key_done:
    mov [tb_wdl_debug_wk], r10d
    mov [tb_wdl_debug_bk], r11d

    ; cmirror/mirror/bside: symmetric (rovnaky material) tabulky maju bside=0
    ; a cmirror/mirror podla side; asymetricke idu key-match vetvou (probe.c)
    mov byte [tb_dec_cmirror_tmp], 0
    mov byte [tb_dec_mirror_tmp], 0
    call tb_material_symmetric
    test eax, eax
    jz .p4_asym
    xor edx, edx                  ; bside = 0
    movzx eax, byte [side]
    test eax, eax
    jz .p4_side_ready
    mov byte [tb_dec_cmirror_tmp], 8
    mov byte [tb_dec_mirror_tmp], 56
    jmp .p4_side_ready
.p4_asym:
    movzx edx, byte [side]
    cmp r10, r11
    je .p4_side_ready
    mov byte [tb_dec_cmirror_tmp], 8
    mov byte [tb_dec_mirror_tmp], 56
    xor edx, 1
.p4_side_ready:
    mov [tb_dec_bside_tmp], dl
    mov [tb_wdl_pairs_blocksize], dl

    ; najdi lead pawn square (pieces0[0] ^ cmirror)
    movzx eax, byte [r9]
    and eax, 0x0f
    movzx ebx, byte [tb_dec_cmirror_tmp]
    xor eax, ebx
    mov r13d, eax                 ; expected lead pawn code
    mov r14d, -1                  ; best lead pawn sq
    mov r10d, 255                 ; best flap
    xor ecx, ecx
.p4_find_pawn:
    cmp ecx, 64
    jae .p4_pawn_done
    movzx edx, byte [r8 + rcx]
    cmp edx, r13d
    jne .p4_find_pawn_next
    mov eax, ecx
    movzx ebx, byte [tb_dec_mirror_tmp]
    xor eax, ebx
    lea rdx, [tb_flap]
    movzx eax, byte [rdx + rax]
    cmp eax, r10d
    jae .p4_find_pawn_next
    mov r10d, eax                 ; najlepsi flap
    mov r14d, ecx                 ; najlepsi sq
.p4_find_pawn_next:
    inc ecx
    jmp .p4_find_pawn
.p4_pawn_done:
    cmp r14d, 0
    jl .not_found
    movzx eax, byte [tb_dec_mirror_tmp]
    xor r14d, eax                 ; lead pawn sq po mirror

    ; file bucket z lead pawn
    mov eax, r14d
    and eax, 7
    lea rdx, [tb_file_to_file]
    movzx eax, byte [rdx + rax]
    mov r15d, eax                 ; file bucket

    ; setup pieces/norm/factor pre dany file a bside
    push r8                       ; uloz board pointer (tb_setup_pieces_pawn moze pouzit r8)
    movzx r11d, byte [tb_dec_bside_tmp]
    mov edi, r15d
    mov esi, r11d
    mov edx, [tb_pawns0]
    mov ecx, [tb_pawns1]
    call tb_setup_pieces_pawn
    pop r8
    test eax, eax
    jz .not_found
    mov rax, [tb_tb_size]
    mov [tb_wdl_debug_tb_size], rax

    ; zostav tb_tmp_pos[0..num-1]
    lea rdi, [tb_tmp_pos]
    mov [rdi], r14d               ; pos[0] = lead pawn
    mov r13d, [tb_num]
    mov ecx, 1
.p4_build_pos:
    cmp ecx, r13d
    jae .p4_pos_done
    movzx eax, byte [tb_pieces + rcx]
    movzx ebx, byte [tb_dec_cmirror_tmp]
    xor eax, ebx                  ; expected board code
    xor edx, edx
.p4_find_piece:
    cmp edx, 64
    jae .not_found
    movzx edi, byte [r8 + rdx]
    cmp edi, eax
    jne .p4_find_next
    ; preskoc uz pouzite policko (duplicitne figury)
    mov r10d, edx
    movzx esi, byte [tb_dec_mirror_tmp]
    xor r10d, esi                 ; normalizovane policko kandidat
    xor r9d, r9d
.p4_used_check:
    cmp r9d, ecx
    jae .p4_piece_found
    cmp r10d, [tb_tmp_pos + r9*4]
    je .p4_find_next
    inc r9d
    jmp .p4_used_check
.p4_piece_found:
    movzx ebx, byte [tb_dec_mirror_tmp]
    xor edx, ebx
    mov [tb_tmp_pos + rcx*4], edx
    inc ecx
    jmp .p4_build_pos
.p4_find_next:
    inc edx
    jmp .p4_find_piece
.p4_pos_done:

    call tb_encode_pawn_idx
    test eax, eax
    jz .not_found
    mov [tb_wdl_debug_idx], rdx
    mov r14, rdx                  ; idx
    mov r13d, r15d                ; file bucket
    movzx r11d, byte [tb_dec_bside_tmp] ; bside

    ; priprav setup_pairs slot pre file+bside
    mov r12, [tb_map]
    mov r15, [tb_map_size]
    lea rsi, [r12 + r15]          ; map_end
    lea rdi, [r12 + 5]            ; headers_start
    ; record size = num + s, s = 1 + (pawns1 > 0), files = 4
    mov ebx, 1
    cmp dword [tb_pawns1], 0
    je .p4_have_s
    inc ebx
.p4_have_s:
    mov eax, [tb_num]
    add eax, ebx
    shl eax, 2                    ; skip all 4 file records
    add rdi, rax                  ; setup_pairs start
    ; (alignment pre pawnful 4-piece je parita, pre istotu zarovnaj)
    mov rax, rdi
    sub rax, r12
    test al, 1
    jz .p4_aligned
    inc rdi
.p4_aligned:

    mov [tb_dec_headers_start_tmp], rdi
    mov rax, rdi
    sub rax, r12
    mov [tb_wdl_debug_order_byte], al

    ; slot_count = 4 files * (1 + split)
    movzx eax, byte [r12 + 4]
    and eax, 1
    mov ebx, 4
    test eax, eax
    jz .p4_slots_no_split
    shl ebx, 1
.p4_slots_no_split:
    mov [tb_dec_slot_count_tmp], ebx

    ; target index: file (non-split) alebo file*2 + bside (split)
    cmp ebx, 4
    je .p4_target_nosplit
    mov eax, r13d
    shl eax, 1
    test r11d, r11d
    jz .p4_target_ready
    inc eax
    jmp .p4_target_ready
.p4_target_nosplit:
    mov eax, r13d
.p4_target_ready:
    mov [tb_dec_target_tmp], eax
    mov [tb_wdl_pairs_num_blocks], eax

    ; parse slots az po target
    xor ecx, ecx
.p4_parse_loop:
    cmp ecx, ebx
    jae .not_found
    mov r14, rdi                  ; save header ptr (tb_parse_pairs_minlen meni r9)
    push rcx
    call tb_parse_pairs_minlen
    pop rcx
    test eax, eax
    jz .not_found
    cmp ecx, [tb_dec_target_tmp]
    je .p4_target_slot
    mov rdi, r8                   ; next ptr
    inc ecx
    jmp .p4_parse_loop
.p4_target_slot:
    mov rbx, r14                  ; target setup_pairs ptr
    mov [tb_wdl_pairs_num_syms], ecx
    mov rax, rbx
    sub rax, r12
    mov [tb_wdl_pairs_header_off], rax

    mov rdi, [tb_dec_headers_start_tmp]
    lea rsi, [r12 + r15]
    mov edx, [tb_dec_slot_count_tmp]
    mov ecx, [tb_dec_target_tmp]
    mov r8, [tb_tb_size]
    call tb_pairs_prepare_pawn_override
    test eax, eax
    jz .not_found

    mov rcx, [tb_wdl_debug_idx]
    mov rdi, rbx
    lea rsi, [r12 + r15]
    mov rdx, [tb_tb_size]
    call tb_pairs_decode_symbol_idx
    test eax, eax
    jnz .p4_decode_ok
    movzx eax, byte [tb_dec_stage_tmp]
    mov [tb_wdl_debug_nf_code], al
    jmp .not_found
.p4_decode_ok:
    mov r10d, edx
    jmp .raw_to_class

.raw_to_class:
    ; raw syzygy symbol -> WDL trieda: raw-2  {-2..2}
    cmp r10d, 4
    ja .not_found
    mov eax, r10d
    sub eax, 2
    cmp eax, 0
    jg .win
    jl .loss
    mov eax, TB_DRAW
    jmp .done

.win:
    mov eax, TB_WIN
    jmp .done

.loss:
    mov eax, TB_LOSS
    jmp .done

.not_found:
.nf_regular:
    cmp byte [tb_wdl_pairs_is_const], 4
    jne .nf_keep
    mov byte [tb_wdl_pairs_is_const], 8
.nf_keep:
    mov eax, TB_NOT_FOUND

.done:
    pop r15
    pop r12
    pop r14
    pop rcx
    pop rbx
    ret
