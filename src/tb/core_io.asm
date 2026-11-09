; ============================================================
; tb_unmap_current - uvolni aktualne mmap mapovanie, ak existuje
; ============================================================
tb_unmap_current:
    push r12
    mov r12, [tb_map]
    test r12, r12
    jz .clear
    mov rax, SYS_MUNMAP
    mov rdi, r12
    mov rsi, [tb_map_size]
    syscall
.clear:
    mov qword [tb_map], 0
    mov qword [tb_map_size], 0
    mov qword [tb_fd], -1
    mov byte [tb_loaded_path], 0
    pop r12
    ret

; ============================================================
; tb_str_eq - porovna dva NUL-terminated retazce
; Vstup: rdi = s1, rsi = s2
; Vystup: eax = 1 (equal) / 0 (not equal)
; ============================================================
tb_str_eq:
    push rcx
    xor ecx, ecx
.loop:
    cmp rcx, TB_PATH_MAX
    jae .equal
    movzx eax, byte [rdi + rcx]
    movzx edx, byte [rsi + rcx]
    cmp eax, edx
    jne .not_equal
    test al, al
    jz .equal
    inc rcx
    jmp .loop

.equal:
    mov eax, 1
    pop rcx
    ret

.not_equal:
    xor eax, eax
    pop rcx
    ret

; ============================================================
; tb_copy_path - skopiruje NUL-terminated cestu
; Vstup: rdi = dst, rsi = src
; ============================================================
tb_copy_path:
    push rcx
    xor ecx, ecx
.copy:
    cmp rcx, TB_PATH_MAX - 1
    jae .done
    movzx eax, byte [rsi + rcx]
    mov [rdi + rcx], al
    inc rcx
    test al, al
    jnz .copy
.done:
    mov byte [rdi + TB_PATH_MAX - 1], 0
    pop rcx
    ret

; ============================================================
; tb_ensure_loaded_path - mapuj subor len ked nie je uz mapnuty
; Vstup: rdi = cesta
; Vystup: eax = 0 success, 1 fail
; ============================================================
tb_ensure_loaded_path:
    push rbx
    push r12
    mov rbx, rdi

    mov r12, [tb_map]
    test r12, r12
    jz .reload
    cmp qword [tb_map_size], 0
    jle .reload

    lea rdi, [tb_loaded_path]
    mov rsi, rbx
    call tb_str_eq
    test eax, eax
    jz .reload
    xor eax, eax
    jmp .done

.reload:
    call tb_unmap_current
    mov rdi, rbx
    call tb_load_path
    test eax, eax
    jnz .fail
    mov byte [tb_dec_override_ptrs], 0
    lea rdi, [tb_sym_cache_state]
    mov ecx, 4096/8
    xor eax, eax
    rep stosq
    lea rdi, [tb_dec_symlen]
    mov ecx, 4096/8
    rep stosq
    lea rdi, [tb_loaded_path]
    mov rsi, rbx
    call tb_copy_path
    xor eax, eax
    jmp .done

.fail:
    mov eax, 1

.done:
    pop r12
    pop rbx
    ret

; ============================================================
; tb_find_pairs_probe - najde setup_pairs hlavu a vrati nasledny offset
; Vstup:  rdi = map_ptr, rsi = map_size
; Vystup: eax = 0 fail, 1 constant setup_pairs, 2 non-constant setup_pairs
;         r8  = header offset setup_pairs
;         r9  = probe offset (next pointer setup_pairs)
;         dl  = probe byte (0 ak n/a)
;         r10d = num_blocks (0 pri constant)
;         r11d = num_syms (0 pri constant)
;         bl = blocksize (0 pri constant)
;         cl = idxbits (0 pri constant)
;         al = is_const (1/0) pri uspechu
; Pozn.: probe offset je "next" pointer zo setup_pairs, nie fixny +32.
; ============================================================
tb_find_pairs_probe:
    push rbx
    push r12
    push r13

    xor eax, eax
    xor r8, r8
    xor r9, r9
    xor edx, edx
    xor r10d, r10d
    xor r11d, r11d
    xor ebx, ebx
    xor ecx, ecx

    test rdi, rdi
    jz .fail
    cmp rsi, 16
    jb .fail
    mov r12, rsi                ; map_size

    ; Syzygy data cast zacina za uvodnou preambulou, hladame po parnych offsetoch.
    mov r13, 10

.scan_loop:
    ; Potrebujeme aspon 12 bajtov na nekonstantny setup_pairs header.
    mov rax, r13
    add rax, 12
    cmp rax, r12
    ja .fail

    movzx eax, byte [rdi + r13]
    test al, 0x80
    jz .non_const
    ; Constant setup_pairs ma byt striktne 0x80, inak je to cast preambuly.
    cmp al, 0x80
    jne .next_candidate

    ; Constant-table varianta: 2 bajty (flag|min_len), next = off + 2.
    mov r8, r13
    lea r9, [r13 + 2]
    cmp r9, r12
    ja .next_candidate
    cmp r9, r12
    je .const_ok
    movzx edx, byte [rdi + r9]
.const_ok:
    mov eax, 1
    jmp .ret

.non_const:
    movzx ebx, byte [rdi + r13 + 1]   ; blocksize
    cmp ebx, 1
    jb .next_candidate
    cmp ebx, 31
    ja .next_candidate

    movzx ecx, byte [rdi + r13 + 2]   ; idxbits
    cmp ecx, 1
    jb .next_candidate
    cmp ecx, 31
    ja .next_candidate

    mov r10d, dword [rdi + r13 + 4]   ; real_num_blocks
    test r10d, r10d
    jz .next_candidate

    movzx r11d, byte [rdi + r13 + 3]  ; extra blocks
    add r10d, r11d

    movzx eax, byte [rdi + r13 + 8]   ; max_len
    movzx edx, byte [rdi + r13 + 9]   ; min_len
    cmp eax, edx
    jb .next_candidate
    cmp eax, 63
    ja .next_candidate

    ; h = max_len - min_len + 1
    sub eax, edx
    inc eax
    mov esi, eax

    ; num_syms je na [off + 10 + 2*h]
    lea rax, [r13 + 10]
    lea rax, [rax + rsi*2]
    lea rdx, [rax + 2]
    cmp rdx, r12
    ja .next_candidate

    movzx r11d, word [rdi + rax]      ; num_syms
    test r11d, r11d
    jz .next_candidate
    cmp r11d, 4096
    ja .next_candidate

    ; next = off + 12 + 2*h + 3*num_syms + (num_syms & 1)
    mov r8, r13
    lea r9, [r13 + 12]
    lea r9, [r9 + rsi*2]
    lea rax, [r11 + r11*2]
    add r9, rax
    mov eax, r11d
    and eax, 1
    add r9, rax
    cmp r9, r12
    ja .next_candidate

    xor edx, edx
    cmp r9, r12
    je .pairs_ok
    movzx edx, byte [rdi + r9]

.pairs_ok:
    mov eax, 2
    jmp .ret

.next_candidate:
    add r13, 2
    cmp r13, 256
    jb .scan_loop

.fail:
    xor eax, eax
    xor r8, r8
    xor r9, r9
    xor edx, edx
    xor r10d, r10d
    xor r11d, r11d
    xor ebx, ebx
    xor ecx, ecx

.ret:
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; tb_validate_map_and_probe - validuj magic a vrat debug payload byte
; Vstup:  rdi = map_ptr, rsi = map_size, edx = expected magic
; Vystup: eax = 1 valid / 0 invalid
;         r8  = payload probe offset (0 = n/a)
;         dl  = payload probe byte (0 ak n/a)
; Pozn.: payload probe offset je odvodeny zo setup_pairs parsera.
; ============================================================
tb_validate_map_and_probe:
    ; map + minimalna hlava
    test rdi, rdi
    jz .fail
    cmp rsi, 4
    jb .fail

    mov ecx, dword [rdi]
    cmp ecx, edx
    jne .fail

    ; debug payload probe z realneho setup_pairs parsera
    call tb_find_pairs_probe
    test eax, eax
    jz .clear_probe
    mov r8, r9
    mov eax, 1
    ret

.clear_probe:
    xor r8, r8
    xor edx, edx

.ok:
    mov eax, 1
    ret

.fail:
    xor eax, eax
    xor r8, r8
    xor edx, edx
    ret

; ============================================================
; tb_parse_pairs_minlen - parsuje setup_pairs na presnom offsete
; Vstup:  rdi = setup_pairs ptr, rsi = map_end ptr
; Vystup: eax = 0 fail, 1 constant, 2 non-constant
;         edx = min_len
;         r8  = next ptr za setup_pairs
;         r9d = num_syms (0 pre constant)
;         r10 = sympat ptr (0 pre constant)
; ============================================================
tb_parse_pairs_minlen:
    xor eax, eax
    xor edx, edx
    xor r8, r8
    xor r9d, r9d
    xor r10, r10

    test rdi, rdi
    jz .fail
    cmp rdi, rsi
    jae .fail

    lea rcx, [rdi + 2]
    cmp rcx, rsi
    ja .fail

    movzx ecx, byte [rdi]
    test ecx, 0x80
    jz .non_const

    movzx edx, byte [rdi + 1]
    lea r8, [rdi + 2]
    xor r9d, r9d
    xor r10, r10
    mov eax, 1
    ret

.non_const:
    lea rcx, [rdi + 12]
    cmp rcx, rsi
    ja .fail

    movzx ecx, byte [rdi + 8]      ; max_len
    movzx edx, byte [rdi + 9]      ; min_len
    cmp ecx, edx
    jb .fail

    ; h = max_len - min_len + 1
    sub ecx, edx
    inc ecx
    test ecx, ecx
    jle .fail
    cmp ecx, 64
    ja .fail

    ; num_syms je na [ptr + 10 + 2*h]
    lea r8, [rdi + 10]
    lea r8, [r8 + rcx*2]
    lea r9, [r8 + 2]
    cmp r9, rsi
    ja .fail

    movzx r9d, word [r8]
    test r9d, r9d
    jz .fail

    ; sympat zacina za hlavouri + offset[] tabulkou
    lea r10, [rdi + 12]
    lea r10, [r10 + rcx*2]

    ; next = ptr + 12 + 2*h + 3*num_syms + (num_syms & 1)
    lea r8, [rdi + 12]
    lea r8, [r8 + rcx*2]
    lea rcx, [r9 + r9*2]
    add r8, rcx
    mov ecx, r9d
    and ecx, 1
    add r8, rcx
    cmp r8, rsi
    ja .fail

    mov eax, 2
    ret

.fail:
    xor eax, eax
    xor edx, edx
    xor r8, r8
    xor r9d, r9d
    xor r10, r10
    ret

; ============================================================
; tb_pairs_prepare_pawn_override - vypocita realne pointery
; indextable/sizetable/data pre vybrany pawn setup_pairs slot.
; Vstup:
;   rdi = headers_start (prvy setup_pairs header)
;   rsi = map_end
;   edx = slot_count
;   ecx = target_slot
;   r8  = tb_size
; Vystup: eax = 1 success / 0 fail
; Pozn.: nastavuje tb_dec_override_* a tb_dec_override_ptrs=1
; ============================================================
tb_pairs_prepare_pawn_override:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    xor eax, eax
    mov byte [tb_dec_override_ptrs], 0

    test rdi, rdi
    jz .fail
    cmp edx, 1
    jb .fail
    cmp edx, 8
    ja .fail
    cmp ecx, edx
    jae .fail

    mov r12, rdi                  ; iter ptr cez setup headers
    mov r13, rsi                  ; map_end
    mov r14d, edx                 ; slot_count
    mov r15d, ecx                 ; target_slot
    mov rbp, r8                   ; tb_size

    xor ebx, ebx
.scan_slots:
    cmp ebx, r14d
    jae .slots_done

    mov rdi, r12
    mov rsi, r13
    call tb_parse_pairs_minlen
    test eax, eax
    jz .fail

    lea rdi, [tb_dec_slot_size0]
    lea rsi, [tb_dec_slot_size1]
    lea rdx, [tb_dec_slot_size2]

    cmp eax, 1
    jne .slot_nonconst
    mov qword [rdi + rbx*8], 0
    mov qword [rsi + rbx*8], 0
    mov qword [rdx + rbx*8], 0
    mov r12, r8
    inc ebx
    jmp .scan_slots

.slot_nonconst:
    movzx ecx, byte [r12 + 2]     ; idxbits
    mov rax, 1
    shl rax, cl
    dec rax
    add rax, rbp
    shr rax, cl                    ; num_indices
    imul rax, rax, 6               ; size0
    mov [rdi + rbx*8], rax

    mov eax, dword [r12 + 4]       ; real_num_blocks
    movzx ecx, byte [r12 + 3]
    add eax, ecx                   ; num_blocks
    mov ecx, eax
    mov rax, rcx
    shl rax, 1                     ; size1
    mov [rsi + rbx*8], rax

    movzx ecx, byte [r12 + 1]      ; blocksize
    mov rax, 1
    shl rax, cl
    mov ecx, dword [r12 + 4]       ; real_num_blocks
    imul rax, rcx                  ; size2
    mov [rdx + rbx*8], rax

    mov r12, r8                    ; next ptr
    inc ebx
    jmp .scan_slots

.slots_done:
    mov r10, r12                   ; headers_end

    ; indextable pointer pre target slot
    mov r11, r10
    xor ebx, ebx
.sum_size0_prev:
    cmp ebx, r15d
    jae .have_indextable
    lea rax, [tb_dec_slot_size0]
    add r11, [rax + rbx*8]
    inc ebx
    jmp .sum_size0_prev

.have_indextable:
    mov [tb_dec_override_indextable], r11

    ; sizetable base = headers_end + sum(size0 all)
    mov r12, r10
    xor ebx, ebx
.sum_size0_all:
    cmp ebx, r14d
    jae .have_size0_all
    lea rax, [tb_dec_slot_size0]
    add r12, [rax + rbx*8]
    inc ebx
    jmp .sum_size0_all

.have_size0_all:
    ; sizetable pointer pre target slot
    mov r11, r12
    xor ebx, ebx
.sum_size1_prev:
    cmp ebx, r15d
    jae .have_sizetable
    lea rax, [tb_dec_slot_size1]
    add r11, [rax + rbx*8]
    inc ebx
    jmp .sum_size1_prev

.have_sizetable:
    mov [tb_dec_override_sizetable], r11

    ; data base = sizetable base + sum(size1 all)
    mov rax, r12
    xor ebx, ebx
.sum_size1_all:
    cmp ebx, r14d
    jae .have_data_base
    lea rcx, [tb_dec_slot_size1]
    add rax, [rcx + rbx*8]
    inc ebx
    jmp .sum_size1_all

.have_data_base:
    ; data ptr pre target: align64 pred kazdym slotom, potom +size2
    xor ebx, ebx
.walk_data_slots:
    cmp ebx, r14d
    jae .fail
    add rax, 63
    and rax, -64
    cmp ebx, r15d
    jne .data_next
    mov [tb_dec_override_data], rax
    jmp .bounds_check
.data_next:
    lea rcx, [tb_dec_slot_size2]
    add rax, [rcx + rbx*8]
    inc ebx
    jmp .walk_data_slots

.bounds_check:
    cmp [tb_dec_override_indextable], r10
    jb .fail
    cmp [tb_dec_override_sizetable], r10
    jb .fail
    cmp [tb_dec_override_data], r10
    jb .fail
    cmp [tb_dec_override_indextable], r13
    jae .fail
    cmp [tb_dec_override_sizetable], r13
    jae .fail
    cmp [tb_dec_override_data], r13
    jae .fail

    mov byte [tb_dec_override_ptrs], 1
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

