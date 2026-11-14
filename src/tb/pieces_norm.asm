; ============================================================
; pieces_norm.asm - pieces/norm/factor parser pre pawnless TB
; ============================================================

section .text

; ============================================================
; tb_setup_pieces_piece
; Vstup: rdi = map base, rsi = map_size
; Vystup: eax = 1 success / 0 fail
; Pozn.: ocakava ze [tb_num] je nastavene (pocet figur na sachovnici)
; ============================================================
tb_setup_pieces_piece:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    mov r8, rdi
    mov r9, rsi

    cmp r9, 16
    jb .fail

    mov eax, [tb_num]
    cmp eax, 2
    jb .fail
    cmp eax, 8
    ja .fail

    ; flags nibble -> enc_type
    movzx eax, byte [r8 + 4]
    shr eax, 4
    test eax, eax
    jz .enc_done
    dec eax
.enc_done:
    mov [tb_enc_type], eax

    ; order byte (nibble pre bside 0/1)
    movzx r10d, byte [r8 + 5]

    ; data sanity: pieces bytes od +6 musi pokryt [tb_num]
    mov eax, [tb_num]
    mov ecx, eax
    add ecx, 6
    cmp rcx, r9
    ja .fail

    ; clear norm/factor/pieces
    lea rdi, [tb_pieces]
    xor eax, eax
    mov ecx, 16
    rep stosb

    lea rdi, [tb_norm]
    xor eax, eax
    mov ecx, 16
    rep stosd

    lea rdi, [tb_factor]
    xor eax, eax
    mov ecx, 16
    rep stosq

    ; pieces[0][i] = low nibble, pieces[1][i] = high nibble
    lea r11, [r8 + 6]
    xor edx, edx
.copy_loop:
    cmp edx, [tb_num]
    jae .copied
    movzx eax, byte [r11 + rdx]
    mov ecx, eax
    and ecx, 0x0f
    mov [tb_pieces + rdx], cl
    shr eax, 4
    mov [tb_pieces + 8 + rdx], al
    inc edx
    jmp .copy_loop
.copied:

    ; enc_type odvod z materialu pieces[0] (Syzygy set_norm_piece semantics)
    call tb_derive_enc_type_from_pieces0
    mov [tb_enc_type], eax

    ; bside 0
    lea rdi, [tb_pieces]
    lea rsi, [tb_norm]
    call tb_set_norm_piece
    lea rdi, [tb_factor]
    lea rsi, [tb_norm]
    movzx edx, r10b
    and edx, 0x0f
    call tb_calc_factors_piece
    mov [tb_tb_size], rax

    ; bside 1
    lea rdi, [tb_pieces + 8]
    lea rsi, [tb_norm + 8*4]
    call tb_set_norm_piece
    lea rdi, [tb_factor + 8*8]
    lea rsi, [tb_norm + 8*4]
    movzx edx, r10b
    shr edx, 4
    call tb_calc_factors_piece
    mov [tb_tb_size + 8], rax

    mov eax, 1
    jmp .done

.fail:
    xor eax, eax

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_derive_enc_type_from_pieces0
; Vstup: [board] (pozicia s materialom nacitanej tabulky), [tb_num]
; Vystup: eax = enc_type
; Logika (ako python-chess setup_pieces_piece / probe.c):
; - j = pocet (farba,typ) instancii s presne 1 vyskytom, pocitane
;   SEPARATNE pre bielu a ciernu stranu (kralie sa nezaratavaju)
; - ak j >= 3 -> enc_type=0
; - ak j == 2 -> enc_type=2
; - inak enc_type = 1 + min_count_gt1 (per farba/typ)
; Pozn.: povodne sa pocitalo cez zlucene tb_pieces[0] bez rozlisenia
; farieb, co pre KQvKQ/KRvKR (0 singletonov) dalo enc_type=3 namiesto 0
; a tym zly tb_size=1 -> nespravny WDL decode (delta 30/31).
; ============================================================
tb_derive_enc_type_from_pieces0:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    ; counting[0..5]  = biele P,N,B,R,Q,K; counting[6..11] = cierne
    sub rsp, 48
    lea rdi, [rsp]
    xor eax, eax
    mov ecx, 12
.zero_loop:
    mov dword [rdi + rcx*4 - 4], 0
    loop .zero_loop

    ; jediny prechod board[64]
    lea rdx, [board]
    xor eax, eax
.board_loop:
    cmp eax, 64
    jae .board_done
    movzx ecx, byte [rdx + rax]
    test ecx, ecx
    jz .board_next
    mov r8d, ecx
    and r8d, 7                    ; typ
    cmp r8d, PAWN
    jb .board_next                ; prazdne(0) mimo rozsah
    cmp r8d, KING
    ja .board_next
    ; index: PAWN..QUEEN -> 0..4, KING -> 5
    cmp r8d, KING
    je .idx_king
    sub r8d, PAWN
    jmp .idx_ready
.idx_king:
    mov r8d, 5
.idx_ready:
    test ecx, BLACK
    jz .count_store
    add r8d, 6                    ; cierna strana do horneho pola
.count_store:
    inc dword [rdi + r8*4]
.board_next:
    inc eax
    jmp .board_loop

.board_done:
    ; j = pocet count==1; mincnt = min count>1
    xor r10d, r10d                ; j
    mov r11d, 255                 ; min_count_gt1
    xor ebx, ebx
.classify_loop:
    cmp ebx, 12
    jae .classify_done
    mov eax, [rdi + rbx*4]
    cmp eax, 1
    jne .not_single
    inc r10d
    jmp .classify_next
.not_single:
    cmp eax, 2
    jl .classify_next
    cmp eax, r11d
    jae .classify_next
    mov r11d, eax
.classify_next:
    inc ebx
    jmp .classify_loop

.classify_done:
    add rsp, 48
    cmp r10d, 3
    jae .denc_enc0
    cmp r10d, 2
    je .denc_enc2
    cmp r11d, 255
    jne .denc_have_min
    mov eax, 3                    ; fallback na enc_type=3 ak nebolo multi
    jmp .denc_done

.denc_have_min:
    mov eax, r11d
    inc eax
    jmp .denc_done

.denc_enc0:
    xor eax, eax
    jmp .denc_done

.denc_enc2:
    mov eax, 2

.denc_done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_set_norm_piece
; Vstup: rdi = pieces[8] source, rsi = norm[8] destination
; ============================================================
tb_set_norm_piece:
    push rbx
    push rcx
    push rdx
    push r8
    push r9

    mov eax, [tb_enc_type]
    cmp eax, 0
    je .enc0
    cmp eax, 2
    je .enc2
    ; enc_type >= 3 mimo aktualny scope: conservative fallback
    mov ebx, eax
    dec ebx
    jmp .base_ready
.enc0:
    mov ebx, 3
    jmp .base_ready
.enc2:
    mov ebx, 2
.base_ready:
    mov [rsi], ebx

    mov ecx, ebx
    mov edx, [tb_num]
.outer:
    cmp ecx, edx
    jae .done
    mov r8d, ecx
.inner:
    cmp r8d, edx
    jae .inner_done
    movzx eax, byte [rdi + r8]
    movzx r9d, byte [rdi + rcx]
    cmp eax, r9d
    jne .inner_done
    inc dword [rsi + rcx*4]
    inc r8d
    jmp .inner
.inner_done:
    add ecx, [rsi + rcx*4]
    jmp .outer

.done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_calc_factors_piece
; Vstup: rdi = factor[8], rsi = norm[8], edx = order nibble
; Vystup: rax = tb_size
; ============================================================
tb_calc_factors_piece:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    mov eax, [tb_enc_type]
    cmp eax, 0
    je .enc_ok
    cmp eax, 2
    je .enc_ok
    cmp eax, 3
    je .enc_ok
    xor eax, eax
    jmp .done

.enc_ok:
    ; General Syzygy-like calc_factors_piece pre enc_type 0/2/3.
    ; n = 64 - norm[0], f = 1
    mov r8, rdi                   ; factor ptr
    mov r9, rsi                   ; norm ptr
    mov r10d, edx                 ; order

    mov eax, 64
    sub eax, [r9]
    mov r11d, eax                 ; n

    mov rax, 1                    ; f
    mov ebx, [r9]                 ; i = norm[0]
    xor ecx, ecx                  ; k = 0

.enc3_loop:
    mov edx, [tb_num]
    cmp ebx, edx
    jl .enc3_body
    cmp ecx, r10d
    jne .enc3_finish

.enc3_body:
    cmp ecx, r10d
    jne .enc3_group

    ; factor[0] = f; f *= pivfac[enc_type]
    mov [r8], rax
    mov edx, [tb_enc_type]
    cmp edx, 0
    je .pivot_0
    cmp edx, 2
    je .pivot_2
    imul rax, 278
    jmp .pivot_done
.pivot_0:
    imul rax, 31332
    jmp .pivot_done
.pivot_2:
    imul rax, 462
.pivot_done:
    inc ecx
    jmp .enc3_loop

.enc3_group:
    ; factor[i] = f
    mov [r8 + rbx*8], rax

    ; f *= subfactor(norm[i], n)
    mov edi, [r9 + rbx*4]
    mov esi, r11d
    push rax
    push rcx
    push rbx
    push r8
    push r9
    push r10
    push r11
    call tb_subfactor
    mov rdx, rax
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbx
    pop rcx
    pop rax
    imul rax, rdx

    ; n -= norm[i]; i += norm[i]
    mov edx, [r9 + rbx*4]
    sub r11d, edx
    add ebx, edx

    inc ecx
    jmp .enc3_loop

.enc3_finish:
    ; f je final tb_size

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_subfactor(k, n) = C(n, k)
; Vstup: edi = k, esi = n
; Vystup: rax = result
; ============================================================
tb_subfactor:
    push rbx
    push rcx
    push rdx
    push r8

    mov ecx, edi
    mov ebx, esi
    mov rax, rbx
    mov r8, 1
    cmp ecx, 1
    jle .div
    mov edx, 1
.loop:
    cmp edx, ecx
    jae .div
    dec rbx
    imul rax, rbx
    inc edx
    imul r8, rdx
    jmp .loop
.div:
    xor edx, edx
    div r8

    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_setup_pieces_pawn - nastavenie pieces/norm/factor pre pawnful TB
; Vstup: edi = file (0..3), esi = bside (0/1), edx = pawns0, ecx = pawns1
; Vystup: eax = 1 success / 0 fail
; Pozn.: naplni tb_pieces, tb_norm, tb_factor, tb_pawns0/1, tb_tb_size
; ============================================================
global tb_setup_pieces_pawn
tb_setup_pieces_pawn:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                 ; file
    mov r13d, esi                 ; bside
    mov [tb_pawns0], edx
    mov [tb_pawns1], ecx

    mov rax, [tb_map]
    test rax, rax
    jz .fail
    lea r15, [rax + 5]            ; data start po flags byte

    mov eax, [tb_num]
    cmp eax, 2
    jb .fail
    cmp eax, 8
    ja .fail
    mov r14d, eax                 ; num

    mov eax, 1
    cmp ecx, 0
    je .have_s
    inc eax
.have_s:
    mov ebx, eax                  ; s = 1 + (pawns1 > 0)

    ; offset do file recordu
    mov eax, r14d
    add eax, ebx
    imul eax, r12d
    add r15, rax                  ; r15 = data pre dany file

    ; order/order2 z prveho/druheho bajtu podla bside
    movzx eax, byte [r15]
    test r13d, r13d
    jz .order_low
    shr eax, 4
.order_low:
    and eax, 0x0f
    mov r11d, eax                 ; order

    cmp dword [tb_pawns1], 0
    je .no_order2
    movzx eax, byte [r15 + 1]
    test r13d, r13d
    jz .order2_low
    shr eax, 4
.order2_low:
    and eax, 0x0f
    mov r10d, eax                 ; order2
    jmp .order2_ready
.no_order2:
    mov r10d, 0x0f
.order2_ready:

    ; pieces bajty zacinaju za order bajtmi
    mov eax, ebx
    lea r9, [r15 + rax]           ; pieces data ptr

    ; vycisti polia
    lea rdi, [tb_pieces]
    xor eax, eax
    mov ecx, 16
    rep stosb
    lea rdi, [tb_norm]
    mov ecx, 16
    rep stosd
    lea rdi, [tb_factor]
    mov ecx, 16
    rep stosq

    ; kopiruj pieces pre zvoleny bside
    xor ecx, ecx
.copy_loop:
    cmp ecx, r14d
    jae .copied
    movzx eax, byte [r9 + rcx]
    test r13d, r13d
    jz .pc_low
    shr eax, 4
    jmp .pc_store
.pc_low:
    and eax, 0x0f
.pc_store:
    mov [tb_pieces + rcx], al
    inc ecx
    jmp .copy_loop
.copied:

    ; nastav norm pre pawns
    mov eax, [tb_pawns0]
    mov [tb_norm], eax
    cmp dword [tb_pawns1], 0
    je .norm_tail
    mov eax, [tb_pawns0]
    mov ecx, [tb_pawns1]
    mov [tb_norm + rax*4], ecx
.norm_tail:
    ; norm pre zvysne skupiny identickych figur
    mov ecx, [tb_pawns0]
    add ecx, [tb_pawns1]
.norm_outer:
    cmp ecx, r14d
    jae .norm_done
    mov r8d, ecx
.norm_inner:
    cmp r8d, r14d
    jae .norm_inner_done
    movzx eax, byte [tb_pieces + r8]
    movzx edi, byte [tb_pieces + rcx]
    cmp eax, edi
    jne .norm_inner_done
    inc dword [tb_norm + rcx*4]
    inc r8d
    jmp .norm_inner
.norm_inner_done:
    add ecx, [tb_norm + rcx*4]
    jmp .norm_outer
.norm_done:

    ; vypocitaj factor
    mov edi, r12d
    mov esi, r11d
    mov edx, r10d
    call tb_calc_factors_pawn
    mov [tb_tb_size], rax

    mov eax, 1
    jmp .done
.fail:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; tb_calc_factors_pawn - vypocet factor[] pre pawnful tabulku
; Vstup: edi = file, esi = order, edx = order2
; Pouziva: tb_norm, tb_num, tb_pawns0, tb_pawns1, tb_pfactor
; Vystup: rax = tb_size, naplni tb_factor
; ============================================================
global tb_calc_factors_pawn
tb_calc_factors_pawn:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r15d, edi                 ; file
    mov r14d, esi                 ; order
    mov r13d, edx                 ; order2

    mov eax, [tb_norm]
    mov r12d, eax                 ; i = norm[0]
    cmp r13d, 0x0f
    je .no_order2
    mov ecx, [tb_norm + r12*4]
    add r12d, ecx
.no_order2:
    mov ebx, 64
    sub ebx, r12d                 ; n = 64 - i

    mov r11, 1                    ; f
    xor r10d, r10d                ; k
    mov eax, [tb_num]
    mov r9d, eax                  ; num

.loop:
    cmp r12d, r9d
    jl .body
    cmp r10d, r14d
    je .body
    cmp r10d, r13d
    jne .done_loop
.body:
    cmp r10d, r14d
    jne .check_order2
    ; k == order: factor[0] = f; f *= pfactor[norm[0]-1][file]
    lea rax, [tb_factor]
    mov [rax], r11
    mov r8d, [tb_norm]
    dec r8d
    imul r8, r8, 32                ; kazdy riadok tb_pfactor ma 4 qwords
    mov rax, r15
    imul rax, rax, 8
    add r8, rax
    lea rax, [tb_pfactor]
    mov rax, [rax + r8]
    imul r11, rax
    inc r10d
    jmp .loop
.check_order2:
    cmp r10d, r13d
    jne .regular_group
    ; k == order2: factor[norm[0]] = f; f *= subfactor(norm[norm[0]], 48 - norm[0])
    mov ecx, [tb_norm]
    lea rax, [tb_factor]
    mov [rax + rcx*8], r11
    mov edi, [tb_norm + rcx*4]
    mov esi, 48
    sub esi, ecx
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    call tb_subfactor
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    imul r11, rax
    inc r10d
    jmp .loop
.regular_group:
    ; factor[i] = f
    lea rax, [tb_factor]
    mov [rax + r12*8], r11
    ; f *= subfactor(norm[i], n)
    mov edi, [tb_norm + r12*4]
    mov esi, ebx
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    call tb_subfactor
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    imul r11, rax
    mov ecx, [tb_norm + r12*4]
    sub ebx, ecx
    add r12d, ecx
    inc r10d
    jmp .loop
.done_loop:
    mov rax, r11
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
