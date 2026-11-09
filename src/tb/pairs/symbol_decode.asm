tb_pairs_decode_symbol_idx:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                   ; setup ptr
    mov r13, rsi                   ; map_end
    mov r14, rdx                   ; tb_size
    mov r15, rcx                   ; idx
    mov byte [tb_dec_stage_tmp], 1

    xor eax, eax
    xor edx, edx

    test r12, r12
    jz .fail
    cmp r12, r13
    jae .fail
    cmp r12, [tb_map]
    jb .fail

    lea rax, [r12 + 2]
    cmp rax, r13
    ja .fail
    movzx eax, byte [r12]
    test eax, 0x80
    jz .non_const
    movzx edx, byte [r12 + 1]
    mov eax, 1
    jmp .done

.non_const:
    mov byte [tb_dec_stage_tmp], 2
    lea rax, [r12 + 12]
    cmp rax, r13
    ja .fail

    movzx eax, byte [r12 + 1]
    mov [tb_dec_blocksize], eax
    movzx eax, byte [r12 + 2]
    mov [tb_dec_idxbits], eax
    movzx eax, byte [r12 + 3]
    mov ebx, eax
    mov eax, dword [r12 + 4]
    mov [tb_dec_real_blocks], eax
    add eax, ebx
    mov [tb_dec_num_blocks], eax

    movzx eax, byte [r12 + 8]
    mov [tb_dec_max_len], eax
    movzx eax, byte [r12 + 9]
    mov [tb_dec_min_len], eax

    mov eax, [tb_dec_max_len]
    cmp eax, [tb_dec_min_len]
    jb .fail

    mov ebx, eax
    sub ebx, [tb_dec_min_len]
    inc ebx                        ; h
    cmp ebx, 64
    ja .fail

    lea rax, [r12 + 10]
    lea rax, [rax + rbx*2]
    lea rcx, [rax + 2]
    cmp rcx, r13
    ja .fail
    movzx eax, word [rax]
    test eax, eax
    jz .fail
    cmp eax, 4096
    ja .fail
    mov [tb_dec_num_syms], eax

    lea rdx, [r12 + 12]
    lea rdx, [rdx + rbx*2]
    mov [tb_dec_sympat], rdx

    lea rax, [r12 + 12]
    lea rax, [rax + rbx*2]
    mov ecx, [tb_dec_num_syms]
    lea rdx, [rcx + rcx*2]
    add rax, rdx
    mov edx, ecx
    and edx, 1
    add rax, rdx
    cmp rax, r13
    ja .fail
    cmp rax, [tb_map]
    jb .fail
    mov [tb_dec_indextable], rax

    mov ecx, [tb_dec_idxbits]
    test ecx, ecx
    jz .idx_zero
    cmp ecx, 31
    ja .fail
    mov eax, [tb_dec_blocksize]
    cmp eax, 31
    ja .fail

    mov rdx, 1
    shl rdx, cl
    mov rbx, rdx
    dec rbx
    mov rax, r14
    add rax, rbx
    shr rax, cl
    test rax, rax
    jz .fail
    mov [tb_dec_num_indices], rax

    cmp byte [tb_dec_override_ptrs], 1
    jne .derive_ptrs
    mov byte [tb_dec_override_ptrs], 0
    mov rdx, [tb_dec_override_indextable]
    cmp rdx, [tb_map]
    jb .fail
    cmp rdx, r13
    ja .fail
    mov [tb_dec_indextable], rdx
    mov rdx, [tb_dec_override_sizetable]
    cmp rdx, [tb_map]
    jb .fail
    cmp rdx, r13
    ja .fail
    mov [tb_dec_sizetable], rdx
    mov rdx, [tb_dec_override_data]
    cmp rdx, [tb_map]
    jb .fail
    cmp rdx, r13
    ja .fail
    mov [tb_dec_data], rdx
    jmp .build_codes

.derive_ptrs:

    lea rbx, [rax + rax*2]
    shl rbx, 1                     ; size0
    mov rdx, [tb_dec_indextable]
    lea rdx, [rdx + rbx]
    cmp rdx, r13
    ja .fail
    cmp rdx, [tb_map]
    jb .fail
    mov [tb_dec_sizetable], rdx

    mov eax, [tb_dec_num_blocks]
    mov ecx, eax
    shl rcx, 1                     ; size1
    lea rdx, [rdx + rcx]
    cmp rdx, r13
    ja .fail
    add rdx, 63
    and rdx, -64
    cmp rdx, [tb_map]
    jb .fail
    mov [tb_dec_data], rdx

    mov eax, [tb_dec_blocksize]
    mov ecx, eax
    mov rax, 1
    shl rax, cl
    mov ecx, [tb_dec_real_blocks]
    imul rax, rcx
    add rax, rdx
    cmp rax, r13
    ja .fail

    jmp .build_codes

.idx_zero:
    movzx edx, byte [r12 + 9]
    mov eax, 1
    jmp .done

.build_codes:
    mov byte [tb_dec_stage_tmp], 3
    ; reset symlen cache state pre aktualny sympat rozsah
    lea r8, [tb_sym_cache_state]
    mov ecx, [tb_dec_num_syms]
    xor eax, eax
.symclr_loop:
    test ecx, ecx
    jz .symclr_done
    mov [r8], al
    inc r8
    dec ecx
    jmp .symclr_loop
.symclr_done:

    ; offset[l]
    lea rbx, [tb_dec_offabs]
    xor ecx, ecx
.off_clr:
    cmp ecx, 64
    jae .off_fill
    mov word [rbx + rcx*2], 0
    inc ecx
    jmp .off_clr

.off_fill:
    mov eax, [tb_dec_min_len]
    mov edx, [tb_dec_max_len]
    lea r8, [r12 + 10]
.off_loop:
    cmp eax, edx
    ja .base_init
    mov ecx, eax
    sub ecx, [tb_dec_min_len]
    movzx ebp, word [r8 + rcx*2]
    mov [rbx + rax*2], bp
    inc eax
    jmp .off_loop

.base_init:
    lea rbx, [tb_dec_baseabs]
    xor ecx, ecx
.base_clr:
    cmp ecx, 64
    jae .base_build
    mov qword [rbx + rcx*8], 0
    inc ecx
    jmp .base_clr

.base_build:
    mov eax, [tb_dec_max_len]
    mov qword [rbx + rax*8], 0
    mov r9, 0
    dec eax
.base_loop:
    cmp eax, [tb_dec_min_len]
    jl .base_shift
    lea r8, [tb_dec_offabs]
    movzx ecx, word [r8 + rax*2]
    mov edx, eax
    inc edx
    movzx ebp, word [r8 + rdx*2]
    sub ecx, ebp
    mov rdx, r9
    add rdx, rcx
    shr rdx, 1
    mov r9, rdx
    mov [rbx + rax*8], rdx
    dec eax
    jmp .base_loop

.base_shift:
    mov eax, [tb_dec_min_len]
.base_shift_loop:
    cmp eax, [tb_dec_max_len]
    ja .decode_main
    mov rdx, [rbx + rax*8]
    mov ecx, 64
    sub ecx, eax
    cmp ecx, 63
    ja .base_zero
    shl rdx, cl
    jmp .base_store
.base_zero:
    xor rdx, rdx
.base_store:
    mov [rbx + rax*8], rdx
    inc eax
    jmp .base_shift_loop

.decode_main:
    mov byte [tb_dec_stage_tmp], 4
    mov dword [tb_dec_trace_nsteps], 0
    cmp r15, r14
    mov byte [tb_dec_stage_tmp], 41
    jae .fail

    mov eax, [tb_dec_idxbits]
    mov ecx, eax
    mov rax, r15
    shr rax, cl
    cmp rax, [tb_dec_num_indices]
    mov byte [tb_dec_stage_tmp], 42
    jae .fail
    mov r8, rax                    ; mainidx

    mov eax, 1
    mov ecx, [tb_dec_idxbits]
    shl eax, cl
    dec eax
    mov ebx, eax
    mov eax, r15d
    and eax, ebx
    mov edx, 1
    dec ecx
    shl edx, cl
    sub eax, edx
    mov r9d, eax                   ; litidx

    mov rax, r8
    mov [tb_dec_trace_mainidx], rax
    lea rdx, [rax + rax*2]
    shl rdx, 1
    add rdx, [tb_dec_indextable]
    mov rax, [tb_dec_sizetable]
    cmp rdx, rax
    mov byte [tb_dec_stage_tmp], 43
    jae .fail

    mov r11d, dword [rdx]          ; block
    mov [tb_dec_trace_block], r11d
    cmp r11d, [tb_dec_num_blocks]
    mov byte [tb_dec_stage_tmp], 46
    jae .fail
    movzx eax, word [rdx + 4]
    add r9d, eax

    test r9d, r9d
    jns .lit_nonneg
.lit_neg:
    test r11d, r11d
    mov byte [tb_dec_stage_tmp], 44
    jz .fail
    dec r11d
    mov rax, [tb_dec_sizetable]
    movzx eax, word [rax + r11*2]
    add r9d, eax
    inc r9d
    js .lit_neg
    jmp .lit_done

.lit_nonneg:
.lit_pos:
    mov rax, [tb_dec_sizetable]
    movzx eax, word [rax + r11*2]
    cmp r9d, eax
    jle .lit_done
    sub r9d, eax
    dec r9d
    inc r11d
    cmp r11d, [tb_dec_num_blocks]
    mov byte [tb_dec_stage_tmp], 45
    jae .fail
    jmp .lit_pos

.lit_done:
    mov [tb_dec_trace_litidx], r9d
    mov [tb_dec_trace_block], r11d
    mov byte [tb_dec_stage_tmp], 5
    mov eax, r11d
    mov ecx, [tb_dec_blocksize]
    shl rax, cl
    add rax, [tb_dec_data]
    cmp rax, [tb_map]
    jb .fail
    mov r10, rax                   ; block ptr
    mov eax, 1
    mov ecx, [tb_dec_blocksize]
    shl rax, cl
    lea r14, [r10 + rax]           ; block end
    lea rax, [r10 + 8]
    cmp rax, r13
    ja .fail

    mov rbx, [r10]
    bswap rbx
    lea r12, [r10 + 8]             ; ptr32
    xor ebp, ebp                   ; bitcnt

.sym_loop:
    mov eax, [tb_dec_min_len]
.find_l:
    cmp eax, [tb_dec_max_len]
    ja .fail
    lea rdx, [tb_dec_baseabs]
    mov r10, [rdx + rax*8]
    cmp rbx, r10
    jae .have_l
    inc eax
    jmp .find_l

.have_l:
    mov ecx, 64
    sub ecx, eax
    mov rdx, rbx
    sub rdx, r10
    mov r11d, eax                  ; l
    cmp ecx, 63
    ja .sym_fail
    shr rdx, cl
    lea r10, [tb_dec_offabs]
    movzx r10d, word [r10 + rax*2]
    add edx, r10d                  ; sym
    cmp edx, [tb_dec_num_syms]
    jae .fail
    mov r8d, edx                   ; sym uchovany (symlen_get cachuje r8)

    mov rdi, [tb_dec_sympat]
    mov esi, [tb_dec_num_syms]
    call tb_dec_symlen_get
    test eax, eax
    jz .fail
    mov eax, ecx
    inc eax
    cmp r9d, eax
    jl .sym_selected

    sub r9d, eax
    mov ecx, r11d
    shl rbx, cl
    add ebp, r11d
    cmp ebp, 32
    jb .sym_loop

    sub ebp, 32
    cmp r12, r14
    jae .refill_advance
    mov eax, dword [r12]
    bswap eax
    mov ecx, ebp
    shl rax, cl
    or rbx, rax
.refill_advance:
    add r12, 4
    jmp .sym_loop

.sym_fail:
    jmp .fail

.sym_selected:
    mov r10d, r8d                  ; root sym (nie clobbered edx)
    mov [tb_dec_trace_code_hex], rbx
    mov [tb_dec_trace_bitcnt], ebp
    mov [tb_dec_trace_root_sym], r10d

.leaf_loop:
    ; trace: aktualny uzol (sym) + litidx pred krokom
    mov eax, [tb_dec_trace_nsteps]
    cmp eax, 8
    jae .leaf_tr0_done
    mov ecx, eax
    shl ecx, 5
    lea rdx, [tb_dec_trace_steps]
    mov [rdx + rcx], r10d        ; sym
    mov [rdx + rcx + 12], r9d    ; litidx
.leaf_tr0_done:
    mov edx, r10d
    mov rdi, [tb_dec_sympat]
    mov esi, [tb_dec_num_syms]
    call tb_dec_symlen_get
    test eax, eax
    jz .fail
    test ecx, ecx
    jz .leaf_ok

    lea rax, [r10 + r10*2]
    add rax, [tb_dec_sympat]
    movzx edx, byte [rax + 1]
    and edx, 0x0f
    shl edx, 8
    movzx ebx, byte [rax]
    or edx, ebx                    ; s1
    mov ebx, edx                   ; s1 uchovany (symlen_get cachuje rbx)
    mov eax, [tb_dec_trace_nsteps]
    cmp eax, 8
    jae .leaf_tr1_done
    mov ecx, eax
    shl ecx, 5
    lea rax, [tb_dec_trace_steps]
    mov [rax + rcx + 4], edx     ; s1
.leaf_tr1_done:
    mov rdi, [tb_dec_sympat]
    mov esi, [tb_dec_num_syms]
    call tb_dec_symlen_get
    test eax, eax
    jz .fail
    mov eax, ecx
    inc eax
    cmp r9d, eax
    jl .take_s1

    sub r9d, eax
    lea rax, [r10 + r10*2]
    add rax, [tb_dec_sympat]
    movzx edx, byte [rax + 1]
    movzx ecx, byte [rax + 2]
    shl ecx, 4
    mov ebx, edx
    shr ebx, 4
    or ecx, ebx                    ; s2
    mov eax, [tb_dec_trace_nsteps]
    cmp eax, 8
    jae .leaf_tr2_done
    mov edx, eax
    shl edx, 5
    lea rbx, [tb_dec_trace_steps]
    mov [rbx + rdx + 8], ecx     ; s2
    mov dword [rbx + rdx + 16], 2 ; pick = s2
.leaf_tr2_done:
    mov r10d, ecx
    inc dword [tb_dec_trace_nsteps]
    jmp .leaf_loop

.take_s1:
    mov eax, [tb_dec_trace_nsteps]
    cmp eax, 8
    jae .leaf_tr3_done
    mov ecx, eax
    shl ecx, 5
    lea rdx, [tb_dec_trace_steps]
    mov dword [rdx + rcx + 16], 1 ; pick = s1
.leaf_tr3_done:
    mov r10d, ebx                  ; s1 (nie clobbered edx)
    inc dword [tb_dec_trace_nsteps]
    jmp .leaf_loop

.leaf_ok:
    mov byte [tb_dec_stage_tmp], 0
    mov [tb_dec_trace_leaf_sym], r10d
    lea rax, [r10 + r10*2]
    add rax, [tb_dec_sympat]
    movzx edx, byte [rax]
    mov eax, 1
    jmp .done

.fail:
    movzx edx, byte [tb_dec_stage_tmp]
    xor eax, eax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ============================================================
; tb_try_constant_wdl - skusi priamy WDL decode z setup_pairs streamu
; Vstup: r13d = white non-king type (0/typ), r14d = black non-king type (0/typ)
; Vystup: eax = TB_WIN/TB_DRAW/TB_LOSS alebo TB_NOT_FOUND
; Pozn.:
; - Constant setup_pairs dekoduje cez min_len (raw symbol).
; - Non-constant setup_pairs dekoduje len bezpecny slice idxbits==0
;   (v probe.c decompressor vracia priamo min_len). Pri idxbits>0
;   ostava fallback na heuristiky v tb_probe_wdl.
; ============================================================
