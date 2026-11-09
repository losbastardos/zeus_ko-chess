tb_dec_symlen_get:
    push rbx
    push r8
    push r9
    push r10

    mov ebx, edx
    cmp ebx, esi
    jae .fail

    lea r8, [tb_sym_cache_state]
    movzx eax, byte [r8 + rbx]
    cmp eax, 2
    je .cached_ok
    cmp eax, 1
    je .fail
    cmp eax, 3
    je .fail

    mov byte [r8 + rbx], 1

    lea r9, [rbx + rbx*2]
    lea r9, [rdi + r9]

    movzx eax, byte [r9 + 1]
    movzx ecx, byte [r9 + 2]
    shl ecx, 4
    mov r10d, eax
    shr r10d, 4
    or ecx, r10d
    cmp ecx, 0x0fff
    jne .non_terminal

    lea r10, [tb_dec_symlen]
    mov byte [r10 + rbx], 0
    mov byte [r8 + rbx], 2
    xor ecx, ecx
    mov eax, 1
    jmp .done

.non_terminal:
    movzx eax, byte [r9 + 1]
    and eax, 0x0f
    shl eax, 8
    movzx edx, byte [r9]
    or eax, edx
    mov edx, eax
    call tb_dec_symlen_get
    test eax, eax
    jz .mark_fail
    mov r10d, ecx

    movzx eax, byte [r9 + 1]
    movzx ecx, byte [r9 + 2]
    shl ecx, 4
    mov edx, eax
    shr edx, 4
    or ecx, edx
    mov edx, ecx
    call tb_dec_symlen_get
    test eax, eax
    jz .mark_fail

    add ecx, r10d
    inc ecx
    lea r10, [tb_dec_symlen]
    mov [r10 + rbx], cl
    mov byte [r8 + rbx], 2
    mov eax, 1
    jmp .done

.cached_ok:
    lea r10, [tb_dec_symlen]
    movzx ecx, byte [r10 + rbx]
    mov eax, 1
    jmp .done

.mark_fail:
    mov byte [r8 + rbx], 3
.fail:
    xor eax, eax

.done:
    pop r10
    pop r9
    pop r8
    pop rbx
    ret

; ============================================================
; tb_encode_k2_num3_idx - idx pre enc_type=2,num=3,order 0/1
; Vstup: edi = wk sq, esi = bk sq, edx = extra sq, ecx = order
; Vystup: eax = 1 success / 0 fail, rdx = idx
; ============================================================
tb_encode_k2_num3_idx:
    push rbx
    push r8
    push r9

    mov r8d, edi
    mov r9d, esi
    mov ebx, edx

    test r8d, 4
    jz .f2
    xor r8d, 7
    xor r9d, 7
    xor ebx, 7
.f2:
    test r8d, 32
    jz .diag
    xor r8d, 56
    xor r9d, 56
    xor ebx, 56

.diag:
    lea rdx, [tb_offdiag]
    movsx eax, byte [rdx + r8]
    test eax, eax
    jnz .check0
    movsx eax, byte [rdx + r9]
    test eax, eax
    jz .diag_ok
.check0:
    cmp eax, 0
    jle .diag_ok
    lea rdx, [tb_flipdiag]
    movzx eax, byte [rdx + r8]
    mov r8d, eax
    movzx eax, byte [rdx + r9]
    mov r9d, eax
    movzx eax, byte [rdx + rbx]
    mov ebx, eax

.diag_ok:
    lea rdx, [tb_triangle]
    movzx eax, byte [rdx + r8]
    imul eax, eax, 64
    add eax, r9d
    lea rdx, [tb_KK_idx]
    movsx eax, word [rdx + rax*2]
    test eax, eax
    js .fail
    mov r10d, eax

    xor edx, edx
    cmp ebx, r8d
    setg dl
    xor esi, esi
    cmp ebx, r9d
    setg sil
    add edx, esi
    mov eax, ebx
    sub eax, edx
    cmp eax, 0
    jl .fail
    cmp eax, 61
    jg .fail

    cmp ecx, 0
    je .order0
    cmp ecx, 1
    jne .fail
    imul r10d, r10d, 62
    add eax, r10d
    mov edx, eax
    mov eax, 1
    jmp .done

.order0:
    imul eax, eax, 462
    add eax, r10d
    mov edx, eax
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax
    xor edx, edx

.done:
    pop r9
    pop r8
    pop rbx
    ret

; ============================================================
; tb_encode_pawn1_num3_idx - idx pre 1 pawn + 2 kings
; Vstup: edi = pawn sq, esi = kingA sq, edx = kingB sq, ecx = order (0..2)
; Vystup: eax = 1 success / 0 fail, rdx = idx
; Pozn.: kingA/kingB poradie musi zodpovedat pieces[] poradiu tabulky.
; ============================================================
tb_encode_pawn1_num3_idx:
    push rbx
    push r8
    push r9

    mov r8d, edi
    mov r9d, esi
    mov ebx, edx

    ; mirror na a-d file
    test r8d, 4
    jz .pawn_mirror_done
    xor r8d, 7
    xor r9d, 7
    xor ebx, 7
.pawn_mirror_done:

    lea rdx, [tb_flap]
    movzx eax, byte [rdx + r8]
    cmp eax, 23
    ja .fail

    ; idxPawn = flap % 6
    mov edx, eax
.mod6:
    cmp edx, 6
    jb .have_idxpawn
    sub edx, 6
    jmp .mod6
.have_idxpawn:
    mov r10d, edx                  ; idxPawn 0..5

    ; s1 = kingA - (kingA > pawn)
    xor edx, edx
    cmp r9d, r8d
    setg dl
    mov eax, r9d
    sub eax, edx
    cmp eax, 0
    jl .fail
    cmp eax, 62
    ja .fail
    mov r11d, eax                  ; s1

    ; s2 = kingB - (kingB > pawn) - (kingB > kingA)
    xor edx, edx
    cmp ebx, r8d
    setg dl
    xor esi, esi
    cmp ebx, r9d
    setg sil
    add edx, esi
    mov eax, ebx
    sub eax, edx
    cmp eax, 0
    jl .fail
    cmp eax, 61
    ja .fail
    mov r8d, eax                   ; s2

    cmp ecx, 0
    je .order0
    cmp ecx, 1
    je .order1
    cmp ecx, 2
    je .order2
    jmp .fail

.order0:
    ; idx = idxPawn + s1*6 + s2*378
    mov eax, r11d
    imul eax, eax, 6
    mov edx, r8d
    imul edx, edx, 378
    add eax, edx
    add eax, r10d
    mov edx, eax
    mov eax, 1
    jmp .done

.order1:
    ; idx = idxPawn*63 + s1 + s2*378
    mov eax, r10d
    imul eax, eax, 63
    add eax, r11d
    mov edx, r8d
    imul edx, edx, 378
    add eax, edx
    mov edx, eax
    mov eax, 1
    jmp .done

.order2:
    ; idx = idxPawn*3906 + s1 + s2*63
    mov eax, r10d
    imul eax, eax, 3906
    add eax, r11d
    mov edx, r8d
    imul edx, edx, 63
    add eax, edx
    mov edx, eax
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax
    xor edx, edx

.done:
    pop r9
    pop r8
    pop rbx
    ret

; ============================================================
; tb_encode_111_num3_idx - idx pre enc_type=0 (111), num=3
; Vstup: edi = sq0, esi = sq1, edx = sq2 (poradie podla pieces[])
; Vystup: eax = 1 success / 0 fail, rdx = idx
; ============================================================
tb_encode_111_num3_idx:
    push rbx
    push r8
    push r9
    push r10
    push r11

    mov r8d, edi                  ; p0
    mov r9d, esi                  ; p1
    mov r10d, edx                 ; p2

    ; mirror na a-d file podla p0
    test r8d, 4
    jz .m_rank
    xor r8d, 7
    xor r9d, 7
    xor r10d, 7

.m_rank:
    ; mirror na ranks 1-4 podla p0
    test r8d, 32
    jz .diag_norm
    xor r8d, 56
    xor r9d, 56
    xor r10d, 56

.diag_norm:
    ; najdi prvu nediagonalnu figuru z p0..p2 a pripadne flipni diagonalu
    lea r11, [tb_offdiag]
    movsx eax, byte [r11 + r8]
    test eax, eax
    jnz .diag_decide
    movsx eax, byte [r11 + r9]
    test eax, eax
    jnz .diag_decide
    movsx eax, byte [r11 + r10]

.diag_decide:
    cmp eax, 0
    jle .idx_branch
    lea r11, [tb_flipdiag]
    movzx eax, byte [r11 + r8]
    mov r8d, eax
    movzx eax, byte [r11 + r9]
    mov r9d, eax
    movzx eax, byte [r11 + r10]
    mov r10d, eax

.idx_branch:
    ; i = (p1 > p0), j = (p2 > p0) + (p2 > p1)
    xor ecx, ecx
    cmp r9d, r8d
    setg cl                       ; i
    xor ebx, ebx
    cmp r10d, r8d
    setg bl
    xor edx, edx
    cmp r10d, r9d
    setg dl
    add ebx, edx                  ; j

    ; if offdiag(p0)
    lea r11, [tb_offdiag]
    movsx eax, byte [r11 + r8]
    test eax, eax
    jz .chk_p1

    lea r11, [tb_triangle]
    movzx eax, byte [r11 + r8]
    imul eax, eax, 3906           ; 63*62
    mov edx, r9d
    sub edx, ecx
    imul edx, edx, 62
    add eax, edx
    mov edx, r10d
    sub edx, ebx
    add eax, edx
    mov edx, eax
    mov eax, 1
    jmp .done

.chk_p1:
    lea r11, [tb_offdiag]
    movsx eax, byte [r11 + r9]
    test eax, eax
    jz .chk_p2

    lea r11, [tb_diag]
    movzx eax, byte [r11 + r8]
    imul eax, eax, 1736           ; 28*62
    add eax, 23436                ; 6*63*62
    lea r11, [tb_lower]
    movzx edx, byte [r11 + r9]
    imul edx, edx, 62
    add eax, edx
    mov edx, r10d
    sub edx, ebx
    add eax, edx
    mov edx, eax
    mov eax, 1
    jmp .done

.chk_p2:
    lea r11, [tb_offdiag]
    movsx eax, byte [r11 + r10]
    test eax, eax
    jz .all_diag

    lea r11, [tb_diag]
    movzx eax, byte [r11 + r8]
    imul eax, eax, 196            ; 7*28
    add eax, 27888                ; 6*63*62 + 4*28*62
    movzx edx, byte [r11 + r9]
    sub edx, ecx
    imul edx, edx, 28
    add eax, edx
    lea r11, [tb_lower]
    movzx edx, byte [r11 + r10]
    add eax, edx
    mov edx, eax
    mov eax, 1
    jmp .done

.all_diag:
    lea r11, [tb_diag]
    movzx eax, byte [r11 + r8]
    imul eax, eax, 42             ; 7*6
    add eax, 28672                ; 6*63*62 + 4*28*62 + 4*7*28
    movzx edx, byte [r11 + r9]
    sub edx, ecx
    imul edx, edx, 6
    add eax, edx
    movzx edx, byte [r11 + r10]
    sub edx, ebx
    add eax, edx
    mov edx, eax
    mov eax, 1
    jmp .done

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbx
    ret

; ============================================================
; tb_encode_piece_idx - prvy krok general encode API
; Vstup: rdi = norm[8], rsi = pos[8], rdx = factor[8], ecx = bside
; Vystup: eax = 1 success / 0 fail, rdx = idx
; Pozn.: podporuje regular enc_type=0/2 aj CONNECTED_KINGS enc_type=3.
; ============================================================
tb_encode_piece_idx:
    push rbx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov r15, rdx                  ; factor ptr

    mov eax, [tb_enc_type]
    cmp eax, 0
    je .enc0
    cmp eax, 2
    je .enc2
    cmp eax, 3
    je .enc3

    ; ostatne enc_type mimo scope.
    jmp .fail

.enc0:
    mov r12d, [tb_num]
    cmp r12d, 3
    jb .fail
    mov r14d, 3                   ; first non-king-ish group limit pre diagonal test
    jmp .enc_regular_transform

.enc2:
    mov r12d, [tb_num]
    cmp r12d, 2
    jb .fail
    mov r14d, 2                   ; first non-king-ish group limit pre diagonal test

.enc_regular_transform:
    ; if (pos0 & 0x04) pos[i] ^= 0x07
    mov eax, [rsi]
    test eax, 4
    jz .reg_rank
    xor r10d, r10d
.reg_xor7:
    cmp r10d, r12d
    jae .reg_rank
    mov eax, [rsi + r10*4]
    xor eax, 7
    mov [rsi + r10*4], eax
    inc r10d
    jmp .reg_xor7

.reg_rank:
    ; if (pos0 & 0x20) pos[i] ^= 0x38
    mov eax, [rsi]
    test eax, 32
    jz .reg_diag_scan
    xor r10d, r10d
.reg_xor56:
    cmp r10d, r12d
    jae .reg_diag_scan
    mov eax, [rsi + r10*4]
    xor eax, 56
    mov [rsi + r10*4], eax
    inc r10d
    jmp .reg_xor56

.reg_diag_scan:
    ; najdi prvy offdiag(pos[i]) != 0
    lea r8, [tb_offdiag]
    xor r10d, r10d
.reg_find_first_offdiag:
    cmp r10d, r12d
    jae .reg_core
    mov eax, [rsi + r10*4]
    movsx ebx, byte [r8 + rax]
    test ebx, ebx
    jnz .reg_have_offdiag
    inc r10d
    jmp .reg_find_first_offdiag

.reg_have_offdiag:
    cmp r10d, r14d
    jae .reg_core
    cmp ebx, 0
    jle .reg_core

    ; flipdiag all
    lea r8, [tb_flipdiag]
    xor r10d, r10d
.reg_flipdiag_all:
    cmp r10d, r12d
    jae .reg_core
    mov eax, [rsi + r10*4]
    movzx eax, byte [r8 + rax]
    mov [rsi + r10*4], eax
    inc r10d
    jmp .reg_flipdiag_all

.reg_core:
    mov eax, [tb_enc_type]
    cmp eax, 0
    je .reg_core_enc0

    ; enc_type=2 core (11): idx = KK_IDX[TRIANGLE[p0]][p1]
    mov eax, [rsi]                ; p0
    mov ecx, [rsi + 4]            ; p1

    lea r9, [tb_triangle]
    movzx ebx, byte [r9 + rax]
    imul ebx, ebx, 64
    add ebx, ecx
    lea r9, [tb_KK_idx]
    movsx ebx, word [r9 + rbx*2]
    test ebx, ebx
    js .fail
    jmp .reg_core_done

.reg_core_enc0:
    cmp r12d, 3
    jb .fail

    mov eax, [rsi]                ; p0
    mov ecx, [rsi + 4]            ; p1
    mov edx, [rsi + 8]            ; p2

    xor r8d, r8d
    cmp ecx, eax
    setg r8b                      ; i = p1 > p0

    xor r9d, r9d
    cmp edx, eax
    setg r9b
    xor r10d, r10d
    cmp edx, ecx
    setg r10b
    add r9d, r10d                 ; j = (p2>p0) + (p2>p1)

    lea r11, [tb_offdiag]
    movsx ebx, byte [r11 + rax]
    test ebx, ebx
    jz .reg0_chk_p1

    lea r11, [tb_triangle]
    movzx ebx, byte [r11 + rax]
    imul ebx, ebx, 3906           ; 63*62
    mov r10d, ecx
    sub r10d, r8d
    imul r10d, r10d, 62
    add ebx, r10d
    mov r10d, edx
    sub r10d, r9d
    add ebx, r10d
    jmp .reg_core_done

.reg0_chk_p1:
    movsx ebx, byte [r11 + rcx]
    test ebx, ebx
    jz .reg0_chk_p2

    lea r11, [tb_diag]
    movzx ebx, byte [r11 + rax]
    imul ebx, ebx, 1736           ; 28*62
    add ebx, 23436                ; 6*63*62
    lea r11, [tb_lower]
    movzx r10d, byte [r11 + rcx]
    imul r10d, r10d, 62
    add ebx, r10d
    mov r10d, edx
    sub r10d, r9d
    add ebx, r10d
    jmp .reg_core_done

.reg0_chk_p2:
    movsx ebx, byte [r11 + rdx]
    test ebx, ebx
    jz .reg0_all_diag

    lea r11, [tb_diag]
    movzx ebx, byte [r11 + rax]
    imul ebx, ebx, 196            ; 7*28
    add ebx, 30380                ; 6*63*62 + 4*28*62
    movzx r10d, byte [r11 + rcx]
    sub r10d, r8d
    imul r10d, r10d, 28
    add ebx, r10d
    lea r11, [tb_lower]
    movzx r10d, byte [r11 + rdx]
    add ebx, r10d
    jmp .reg_core_done

.reg0_all_diag:
    lea r11, [tb_diag]
    movzx ebx, byte [r11 + rax]
    imul ebx, ebx, 42             ; 7*6
    add ebx, 31164                ; 6*63*62 + 4*28*62 + 4*7*28
    movzx r10d, byte [r11 + rcx]
    sub r10d, r8d
    imul r10d, r10d, 6
    add ebx, r10d
    movzx r10d, byte [r11 + rdx]
    sub r10d, r9d
    add ebx, r10d

.reg_core_done:
    mov r11, rbx
    mov eax, [tb_enc_type]
    cmp eax, 0
    je .reg_i3
    mov r13d, 2
    jmp .reg_scale
.reg_i3:
    mov r13d, 3

.reg_scale:
    imul r11, qword [r15]         ; idx *= factor[0]
    jmp .tail_outer

.enc3:
    ; scope: enc_type=3 (CONNECTED_KINGS vetva), num >= 2
    mov r12d, [tb_num]
    cmp r12d, 2
    jb .fail

    ; if triangle[pos0] > triangle[pos1] swap(pos0,pos1)
    lea r8, [tb_triangle]
    mov eax, [rsi]
    mov ecx, [rsi + 4]
    movzx ebx, byte [r8 + rax]
    movzx r9d, byte [r8 + rcx]
    cmp ebx, r9d
    jle .enc3_no_swap01
    mov [rsi], ecx
    mov [rsi + 4], eax
.enc3_no_swap01:

    ; if (pos0 & 0x04) pos[i] ^= 0x07
    mov eax, [rsi]
    test eax, 4
    jz .enc3_rank
    xor r10d, r10d
.enc3_xor7:
    cmp r10d, r12d
    jae .enc3_rank
    mov eax, [rsi + r10*4]
    xor eax, 7
    mov [rsi + r10*4], eax
    inc r10d
    jmp .enc3_xor7

.enc3_rank:
    ; if (pos0 & 0x20) pos[i] ^= 0x38
    mov eax, [rsi]
    test eax, 32
    jz .enc3_diag
    xor r10d, r10d
.enc3_xor56:
    cmp r10d, r12d
    jae .enc3_diag
    mov eax, [rsi + r10*4]
    xor eax, 56
    mov [rsi + r10*4], eax
    inc r10d
    jmp .enc3_xor56

.enc3_diag:
    ; if offdiag[pos0] > 0 || (offdiag[pos0]==0 && offdiag[pos1] > 0) flipdiag all
    lea r8, [tb_offdiag]
    mov eax, [rsi]
    movsx ebx, byte [r8 + rax]
    cmp ebx, 0
    jg .enc3_do_flipdiag
    jne .enc3_test45
    mov eax, [rsi + 4]
    movsx ebx, byte [r8 + rax]
    cmp ebx, 0
    jle .enc3_test45

.enc3_do_flipdiag:
    lea r8, [tb_flipdiag]
    xor r10d, r10d
.enc3_flipdiag_loop:
    cmp r10d, r12d
    jae .enc3_test45
    mov eax, [rsi + r10*4]
    movzx eax, byte [r8 + rax]
    mov [rsi + r10*4], eax
    inc r10d
    jmp .enc3_flipdiag_loop

.enc3_test45:
    ; if test45[pos1] && triangle[pos0] == triangle[pos1]
    lea r8, [tb_test45]
    mov eax, [rsi + 4]
    movzx eax, byte [r8 + rax]
    test eax, eax
    jz .enc3_idx

    lea r8, [tb_triangle]
    mov eax, [rsi]
    mov ecx, [rsi + 4]
    movzx ebx, byte [r8 + rax]
    movzx r9d, byte [r8 + rcx]
    cmp ebx, r9d
    jne .enc3_idx

    ; swap(pos0,pos1)
    mov [rsi], ecx
    mov [rsi + 4], eax

    ; pos[i] = flipdiag[pos[i] ^ 0x38]
    lea r8, [tb_flipdiag]
    xor r10d, r10d
.enc3_flipdiag_xor56_loop:
    cmp r10d, r12d
    jae .enc3_idx
    mov eax, [rsi + r10*4]
    xor eax, 56
    movzx eax, byte [r8 + rax]
    mov [rsi + r10*4], eax
    inc r10d
    jmp .enc3_flipdiag_xor56_loop

.enc3_idx:
    lea r8, [tb_triangle]
    mov eax, [rsi]
    mov ecx, [rsi + 4]
    movzx ebx, byte [r8 + rax]    ; tri(pos0)

    lea r8, [tb_PP_idx]
    mov eax, ebx
    imul eax, eax, 64
    add eax, ecx
    movsx r10d, word [r8 + rax*2]
    cmp r10d, 0
    jl .fail

    mov r13d, 2                   ; i = 2
    mov r11, r10                  ; idx
    imul r11, qword [r15]         ; idx *= factor[0]

.tail_outer:
    cmp r13d, r12d
    jae .tail_done

    mov r14d, [rdi + r13*4]       ; t = norm[i]
    test r14d, r14d
    jle .fail

    ; sort groups of identical pieces
    mov r8d, r13d
.sort_j:
    mov eax, r13d
    add eax, r14d
    cmp r8d, eax
    jae .sort_done
    mov r9d, r8d
    inc r9d
.sort_k:
    cmp r9d, eax
    jae .sort_j_next
    mov ebx, [rsi + r8*4]
    mov ecx, [rsi + r9*4]
    cmp ebx, ecx
    jle .sort_k_next
    mov [rsi + r8*4], ecx
    mov [rsi + r9*4], ebx
.sort_k_next:
    inc r9d
    jmp .sort_k
.sort_j_next:
    inc r8d
    jmp .sort_j
.sort_done:
    xor r10, r10                  ; s = 0
    mov r8d, r13d                 ; m = i
.sum_m:
    mov eax, r13d
    add eax, r14d
    cmp r8d, eax
    jae .sum_done

    mov ebx, [rsi + r8*4]         ; p
    xor r9d, r9d                  ; j = 0
    xor ecx, ecx                  ; l = 0
.sum_l:
    cmp ecx, r13d
    jae .sum_l_done
    mov eax, [rsi + rcx*4]
    cmp ebx, eax
    setg al
    movzx eax, al
    add r9d, eax
    inc ecx
    jmp .sum_l
.sum_l_done:

    mov eax, ebx
    sub eax, r9d                  ; n = p - j
    cmp eax, 0
    jl .fail

    push rdi
    push rsi
    push rdx
    mov edi, r8d
    sub edi, r13d
    inc edi                       ; k = m - i + 1
    mov esi, eax
    call tb_subfactor             ; C(n, k)
    pop rdx
    pop rsi
    pop rdi
    add r10, rax

    inc r8d
    jmp .sum_m

.sum_done:
    mov rax, [r15 + r13*8]
    imul r10, rax
    add r11, r10

    add r13d, r14d
    jmp .tail_outer

.tail_done:
    mov rdx, r11
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax
    xor edx, edx

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbx
    ret

; ============================================================
; tb_encode_pawn_idx - idx pre pawnful TB (podla syzygy encode_pawn)
; Vstup: pozicie v tb_tmp_pos[0..tb_num-1] (v poradi pieces[] tabulky)
; Vystup: eax = 1 success / 0 fail, rdx = idx
; Pouziva: tb_tmp_pos, tb_num, tb_pawns0, tb_pawns1, tb_norm, tb_factor,
;          tb_flap, tb_ptwist, tb_pawnidx, tb_binomial
; ============================================================
global tb_encode_pawn_idx
tb_encode_pawn_idx:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r15d, [tb_num]
    cmp r15d, 2
    jb .fail

    ; ak je prvy pesiak na file e-h, zrkadli vsetky policka
    lea rsi, [tb_tmp_pos]
    mov eax, [rsi]
    test eax, 4
    jz .mirror_done
    xor ecx, ecx
.mirror_loop:
    cmp ecx, r15d
    jae .mirror_done
    mov eax, [rsi + rcx*4]
    xor eax, 7
    mov [rsi + rcx*4], eax
    inc ecx
    jmp .mirror_loop
.mirror_done:

    ; sort pawns[1..pawns0-1] podla ptwist zostupne
    mov r13d, [tb_pawns0]
    cmp r13d, 1
    jle .pawns_sorted
    mov r14d, 1
.sort_i:
    mov eax, r14d
    inc eax
    cmp eax, r13d
    jae .pawns_sorted
    mov r12d, eax
.sort_j:
    cmp r12d, r13d
    jae .sort_i_next
    mov eax, [rsi + r14*4]
    mov ebx, [rsi + r12*4]
    lea rdx, [tb_ptwist]
    movzx eax, byte [rdx + rax]
    movzx ebx, byte [rdx + rbx]
    cmp eax, ebx
    jge .sort_j_next
    ; swap
    mov eax, [rsi + r14*4]
    mov ebx, [rsi + r12*4]
    mov [rsi + r14*4], ebx
    mov [rsi + r12*4], eax
.sort_j_next:
    inc r12d
    jmp .sort_j
.sort_i_next:
    inc r14d
    jmp .sort_i
.pawns_sorted:

    ; idx = pawnidx[t][flap[pos[0]]]
    mov eax, [rsi]
    lea rdx, [tb_flap]
    movzx eax, byte [rdx + rax]
    mov r12d, eax                 ; flap[pos0]
    mov r11d, r13d
    dec r11d                      ; t = pawns0 - 1
    mov rax, r11
    imul rax, rax, 24
    add rax, r12
    lea rdx, [tb_pawnidx]
    mov r10, [rdx + rax*8]        ; idx (qword)

    ; for i = t; i > 0; i--
    mov r14d, r11d
.pawn_binom_loop:
    cmp r14d, 0
    jle .pawn_binom_done
    mov eax, [rsi + r14*4]
    lea rdx, [tb_ptwist]
    movzx eax, byte [rdx + rax]   ; ptwist[pos[i]]
    mov ebx, r11d
    sub ebx, r14d
    inc ebx                       ; t - i + 1
    mov rdx, rbx
    imul rdx, rdx, 64
    add rdx, rax
    lea rax, [tb_binomial]
    add r10, [rax + rdx*8]
    dec r14d
    jmp .pawn_binom_loop
.pawn_binom_done:

    ; idx *= factor[0]
    lea rax, [tb_factor]
    mov rax, [rax]
    imul r10, rax

    ; remaining pawns (pawns1)
    mov r14d, r13d                ; i = pawns0
    mov r13d, [tb_pawns1]
    mov eax, r14d
    add eax, r13d                 ; t = i + pawns1
    cmp eax, r14d
    je .pawns1_skip
    mov r12d, eax
    ; sort pos[i..t-1] vzostupne
    mov r8d, r14d
.p1_sort_i:
    mov eax, r8d
    inc eax
    cmp eax, r12d
    jae .p1_sort_done
    mov r9d, eax
.p1_sort_j:
    cmp r9d, r12d
    jae .p1_sort_i_next
    mov eax, [rsi + r8*4]
    mov ebx, [rsi + r9*4]
    cmp eax, ebx
    jle .p1_sort_j_next
    mov [rsi + r8*4], ebx
    mov [rsi + r9*4], eax
.p1_sort_j_next:
    inc r9d
    jmp .p1_sort_j
.p1_sort_i_next:
    inc r8d
    jmp .p1_sort_i
.p1_sort_done:
    ; s = sum binomial[m-i+1][p - j - 8]
    xor r11, r11                  ; s
    mov r8d, r14d                 ; m
.p1_sum:
    cmp r8d, r12d
    jae .p1_sum_done
    mov eax, [rsi + r8*4]
    xor r9, r9                    ; j
    xor ecx, ecx                  ; count all previous pieces (0..m-1)
.p1_count:
    cmp ecx, r14d
    jae .p1_have_count
    mov ebx, [rsi + rcx*4]
    cmp eax, ebx
    jle .p1_count_next
    inc r9d
.p1_count_next:
    inc ecx
    jmp .p1_count
.p1_have_count:
    sub eax, r9d
    sub eax, 8
    mov ebx, r8d
    sub ebx, r14d
    inc ebx
    mov rdx, rbx
    imul rdx, rdx, 64
    add rdx, rax
    lea rax, [tb_binomial]
    add r11, [rax + rdx*8]
    inc r8d
    jmp .p1_sum
.p1_sum_done:
    lea rax, [tb_factor]
    mov rax, [rax + r14*8]
    imul r11, rax
    add r10, r11
    mov r14d, r12d                ; i = t
.pawns1_skip:

    ; zvysne skupiny figur
.tail_loop:
    cmp r14d, r15d
    jae .done
    mov r12d, [tb_norm + r14*4]   ; t = norm[i]
    cmp r12d, 0
    jle .fail
    mov eax, r14d
    add eax, r12d                 ; i + t
    mov r13d, eax
    ; sort pos[i..i+t-1]
    mov r8d, r14d
.tail_sort_i:
    mov eax, r8d
    inc eax
    cmp eax, r13d
    jae .tail_sort_done
    mov r9d, eax
.tail_sort_j:
    cmp r9d, r13d
    jae .tail_sort_i_next
    mov eax, [rsi + r8*4]
    mov ebx, [rsi + r9*4]
    cmp eax, ebx
    jle .tail_sort_j_next
    mov [rsi + r8*4], ebx
    mov [rsi + r9*4], eax
.tail_sort_j_next:
    inc r9d
    jmp .tail_sort_j
.tail_sort_i_next:
    inc r8d
    jmp .tail_sort_i
.tail_sort_done:
    ; s = sum binomial[m-i+1][p - j]
    xor r11, r11
    mov r8d, r14d
.tail_sum:
    cmp r8d, r13d
    jae .tail_sum_done
    mov eax, [rsi + r8*4]
    xor r9, r9
    xor ecx, ecx                  ; count all previous pieces (0..m-1)
.tail_count:
    cmp ecx, r14d
    jae .tail_have_count
    mov ebx, [rsi + rcx*4]
    cmp eax, ebx
    jle .tail_count_next
    inc r9d
.tail_count_next:
    inc ecx
    jmp .tail_count
.tail_have_count:
    sub eax, r9d
    mov ebx, r8d
    sub ebx, r14d
    inc ebx
    mov rdx, rbx
    imul rdx, rdx, 64
    add rdx, rax
    lea rax, [tb_binomial]
    add r11, [rax + rdx*8]
    inc r8d
    jmp .tail_sum
.tail_sum_done:
    lea rax, [tb_factor]
    mov rax, [rax + r14*8]
    imul r11, rax
    add r10, r11
    mov r14d, r13d
    jmp .tail_loop

.done:
    mov rdx, r10
    mov eax, 1
    jmp .return
.fail:
    xor eax, eax
    xor edx, edx
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; tb_pairs_decode_symbol_idx - decode raw symbol zo setup_pairs a idx
; Vstup: rdi = setup_pairs ptr, rsi = map_end, rdx = tb_size, rcx = idx
; Vystup: eax = 1 success / 0 fail, edx = raw symbol
; ============================================================
