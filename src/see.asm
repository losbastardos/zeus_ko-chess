; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; see.asm - Static Exchange Evaluation (swap algorithm)
; ============================================================

%include "chess.inc"

DEFAULT REL

section .data

global see

; hodnoty figur v centipwnych (zhoda s eval.asm)
see_values:
    dd 0            ; EMPTY
    dd 100          ; PAWN
    dd 320          ; KNIGHT
    dd 330          ; BISHOP
    dd 500          ; ROOK
    dd 900          ; QUEEN
    dd 20000        ; KING

section .text

extern board, side
extern promo_pieces

; ============================================================
; see - staticka vymenna evaluacia tahu na aktualnej pozicii
; Vstup:  ax = 16-bit tah (from/to/flags)
; Vystup: eax = skore v centipwnych z pohladu strany, ktora taha prva
;         (kladne = vymena je pre nu vyhodna)
; Algoritmus: klasicky swap algorithm. gain[0] = hodnota branej
; figury (pre en passant pesiak za cielom), potom sa strany striedaju
; a vzdy berie najmenej hodnotna figura utocica na cielove policko.
; Board sa pracuje na vlastnej kopii na stacku (64B) - po "zbrati"
; utocnika dalsim scanom sa automaticky odhali x-ray za nim.
; Zaver: fold gain[d-1] = min(gain[d-1], -gain[d]).
; ============================================================
see:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 200            ; [rbp-104..rbp-41] = board kopia (64B),
                            ; [rbp-232..rbp-105] = gain[32] (128B), 8B pad

    movzx eax, ax           ; sanita: ocisti bity nad 16
    movzx r12d, ax
    shr r12d, 6
    and r12d, 0x3F          ; r12 = to
    mov ebx, eax            ; ebx = cely tah (from | to<<6 | flags<<12)

    ; vymenna sekvencia zacina superom tahajuceho
    lea rax, [side]
    movzx eax, byte [rax]
    xor eax, 1
    mov r13d, eax           ; r13 = side to move vo vymene (0/1)

    ; skopiruj board na stack
    lea rsi, [board]
    lea rdi, [rbp - 104]
    mov ecx, 64
.copy_loop:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz .copy_loop
    lea r14, [rbp - 104]    ; r14 = base kopie board

    ; occupancy mask pre kopiu boardu (bit sq je 1 ak sq != EMPTY)
    xor rax, rax
    xor ecx, ecx
.occ_loop:
    movzx edx, byte [r14 + rcx]
    test edx, edx
    jz .occ_next
    bts rax, rcx
.occ_next:
    inc ecx
    cmp ecx, 64
    jl .occ_loop
    mov [rbp - 240], rax

    ; ---- gain[0] = hodnota branej figury ----
    mov eax, ebx
    shr eax, 12
    cmp eax, FLAG_ENPASSANT
    je .cap_ep
    movzx ecx, byte [r14 + r12]
    and ecx, PIECE_MASK
    lea rdx, [see_values]
    mov ecx, dword [rdx + rcx*4]
    mov [rbp - 232], ecx
    jmp .cap_done
.cap_ep:
    lea rdx, [see_values]
    mov ecx, dword [rdx + PAWN*4]
    mov [rbp - 232], ecx
.cap_done:

    ; ---- aplikuj uvodny tah na kopii ----
    mov ecx, ebx
    and ecx, 0x3F           ; from
    movzx edx, byte [r14 + rcx]     ; tahana figura (s farbou)
    lea rsi, [side]
    movzx esi, byte [rsi]
    shl esi, 3              ; farba tahajuceho (0/8)
    mov eax, ebx
    shr eax, 12
    cmp eax, FLAG_PROMO_Q
    jb .no_promo
    cmp eax, FLAG_PROMO_N
    ja .no_promo
    lea rdi, [promo_pieces]
    movzx edi, byte [rdi + rax]     ; promo figura pre flag (rax = 1..4)
    or edi, esi
    mov edx, edi            ; nova figura na 'to' (typ | farba)
.no_promo:
    mov [r14 + r12], dl     ; board[to] = tahana / promovana figura
    mov eax, ebx
    and eax, 0x3F
    mov byte [r14 + rax], EMPTY
    ; occupancy: from vymaz, to nastav
    mov rdx, [rbp - 240]
    btr rdx, rax
    bts rdx, r12
    mov [rbp - 240], rdx
    ; en passant: odstran aj zajateho pesiaca (za 'to' v smere tahu)
    mov eax, ebx
    shr eax, 12
    cmp eax, FLAG_ENPASSANT
    jne .apply_done
    lea rsi, [side]
    movzx esi, byte [rsi]
    test esi, esi
    jnz .ep_black
    lea rax, [r12 - 8]      ; biely bral pesiaca na to - 8
    jmp .ep_clear
.ep_black:
    lea rax, [r12 + 8]      ; cierny bral pesiaca na to + 8
.ep_clear:
    mov byte [r14 + rax], EMPTY
    mov rdx, [rbp - 240]
    btr rdx, rax
    mov [rbp - 240], rdx
.apply_done:

    ; r15 = hodnota figury aktualne na 'to'
    movzx eax, byte [r14 + r12]
    and eax, PIECE_MASK
    lea rdx, [see_values]
    mov r15d, dword [rdx + rax*4]

    ; ---- swap loop: najdi utocnika, pripocitaj gain, presun na 'to' ----
    xor ebx, ebx            ; rbx = d (pocet dalsich brani v poradi)
.swap_loop:
    mov rax, [rbp - 240]
    mov rsi, r14
    mov edx, r12d
    mov ecx, r13d
    call see_find_attacker
    cmp eax, -1
    je .swap_done
    inc ebx
    lea rcx, [rbp - 232]
    mov edx, dword [rcx + rbx*4 - 4]    ; gain[d-1]
    mov r8d, r15d
    sub r8d, edx
    mov dword [rcx + rbx*4], r8d        ; gain[d] = val(na to) - gain[d-1]
    ; presun utocnika na 'to' (odkryje pripadny x-ray za nim)
    mov rdx, [rbp - 240]
    btr rdx, rax
    mov [rbp - 240], rdx
    movzx edx, byte [r14 + rax]
    mov byte [r14 + rax], EMPTY
    mov [r14 + r12], dl
    and edx, PIECE_MASK
    lea rcx, [see_values]
    mov r15d, dword [rcx + rdx*4]
    xor r13d, 1
    jmp .swap_loop
.swap_done:

    ; ---- fold: gain[d-1] = min(gain[d-1], -gain[d]) ----
.fold_loop:
    test ebx, ebx
    jz .fold_done
    lea rcx, [rbp - 232]
    mov edx, dword [rcx + rbx*4]
    neg edx
    mov eax, dword [rcx + rbx*4 - 4]
    cmp eax, edx
    cmovg eax, edx
    mov dword [rcx + rbx*4 - 4], eax
    dec ebx
    jmp .fold_loop
.fold_done:
    mov eax, dword [rbp - 232]

    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; see_find_attacker - najde NAJMENEJ hodnotnu figuru danej strany,
;                     ktora utoci na target (na kopii board)
; Vstup:  rax = occupancy mask kopie boardu,
;         rsi = base kopie board[64], edx = target, ecx = side (0/1)
; Vystup: rax = policko utocnika (0..63), alebo -1
; Clobber: rax, rcx, rdx, rdi, r8-r11 (rsi, rbx, r12-r15 zachovane)
; ============================================================
see_find_attacker:
    push rbx
    push r15
    mov r10d, edx           ; target
    shl ecx, 3
    mov r11d, ecx           ; farba hladanej strany (0/8)
    mov r8d, -1             ; best sq
    mov r9d, 0x7FFFFFFF     ; best value
    mov rbx, rax            ; set bit = ne-prazdne policko
.scan:
    test rbx, rbx
    jz .done
    bsf rcx, rbx
    lea rax, [rbx - 1]
    and rbx, rax
    movzx r15d, byte [rsi + rcx]
    mov edx, r15d
    and edx, COLOR_MASK
    cmp edx, r11d
    jne .scan
    ; utoci figura na rcx target r10?
    mov edi, ecx
    push rcx
    call see_attacks
    pop rcx
    test eax, eax
    jz .scan
    mov eax, r15d
    and eax, PIECE_MASK
    lea rdx, [see_values]
    mov edx, dword [rdx + rax*4]
    cmp edx, r9d
    jge .scan
    mov r9d, edx
    mov r8d, ecx
    cmp edx, 100            ; pesiak = minimum, lepsie uz niet
    je .done
    jmp .scan
.done:
    mov eax, r8d
    pop r15
    pop rbx
    ret

; ============================================================
; see_attacks - testuje, ci figura na policku sq utoci na target
; Vstup:  rsi = base kopie board[64], edi = sq, r10d = target,
;         r11d = farba hladanej strany (0/8)
; Vystup: eax = 1 ak utoci, inak 0
; Clobber: rax, rcx, rdx (r8/r9 pouziva, ale zachovava)
; ============================================================
see_attacks:
    push r8
    push r9
    movzx eax, byte [rsi + rdi]
    test eax, eax
    jz .no
    mov ecx, eax
    and ecx, COLOR_MASK
    cmp ecx, r11d
    jne .no
    and eax, PIECE_MASK
    cmp eax, PAWN
    je .pawn
    cmp eax, KNIGHT
    je .knight
    cmp eax, BISHOP
    je .sliding_bishop
    cmp eax, ROOK
    je .sliding_rook
    cmp eax, QUEEN
    je .sliding_queen
    cmp eax, KING
    je .king
.no:
    xor eax, eax
    jmp .done
.yes:
    mov eax, 1
.done:
    pop r9
    pop r8
    ret

; --- Pesiaci ---
.pawn:
    mov ecx, r10d
    sub ecx, edi            ; delta = target - sq
    test r11d, r11d
    jnz .pawn_black
    cmp ecx, 7              ; biely utoci +7/+9
    je .pawn_df
    cmp ecx, 9
    je .pawn_df
    jmp .no
.pawn_black:
    cmp ecx, -7             ; cierny utoci -7/-9
    je .pawn_df
    cmp ecx, -9
    je .pawn_df
    jmp .no
.pawn_df:
    mov eax, r10d
    and eax, 7
    mov ecx, edi
    and ecx, 7
    sub eax, ecx
    cmp eax, 1
    je .yes
    cmp eax, -1
    je .yes
    jmp .no

; --- Jazdci: (|df|,|dr|) == (1,2) alebo (2,1) ---
.knight:
    mov eax, r10d
    and eax, 7
    mov ecx, edi
    and ecx, 7
    sub eax, ecx            ; df
    mov r9d, eax
    neg r9d
    cmovs r9d, eax          ; r9 = |df|
    mov ecx, r10d
    shr ecx, 3
    mov edx, edi
    shr edx, 3
    sub ecx, edx            ; dr
    mov edx, ecx
    neg edx
    cmovs edx, ecx          ; rdx = |dr|
    cmp r9d, 1
    jne .knight_2
    cmp edx, 2
    je .yes
    jmp .no
.knight_2:
    cmp r9d, 2
    jne .no
    cmp edx, 1
    je .yes
    jmp .no

; --- Kral: |df| <= 1 a |dr| <= 1 (a sq != target) ---
.king:
    mov eax, r10d
    and eax, 7
    mov ecx, edi
    and ecx, 7
    sub eax, ecx
    mov r9d, eax
    neg r9d
    cmovs r9d, eax          ; r9 = |df|
    mov ecx, r10d
    shr ecx, 3
    mov edx, edi
    shr edx, 3
    sub ecx, edx
    mov edx, ecx
    neg edx
    cmovs edx, ecx          ; rdx = |dr|
    cmp r9d, 1
    jg .no
    cmp edx, 1
    jg .no
    cmp edi, r10d
    je .no
    jmp .yes

; --- Sliding figury: najprv otestuj zarovnanie, potom chodzi luc ---
.sliding_bishop:
    mov r8d, 1              ; mod: iba diagonalne
    jmp .sliding
.sliding_rook:
    mov r8d, 2              ; mod: iba vodorovne/zvisle
    jmp .sliding
.sliding_queen:
    mov r8d, 3              ; mod: oboje
.sliding:
    mov eax, r10d
    and eax, 7
    mov ecx, edi
    and ecx, 7
    sub eax, ecx            ; df
    mov ecx, r10d
    shr ecx, 3
    mov edx, edi
    shr edx, 3
    sub ecx, edx            ; dr
    mov r9d, eax
    neg r9d
    cmovs r9d, eax          ; r9 = |df|
    mov edx, ecx
    neg edx
    cmovs edx, ecx          ; rdx = |dr|
    ; kontrola zarovnania podla typu
    cmp r8d, 1
    je .al_diag
    cmp r8d, 2
    je .al_straight
    ; dama: diagonalne ALEBO rovne
    cmp r9d, edx
    je .al_diag_nz
    test r9d, r9d
    jnz .no                 ; |df| != |dr| a |df| != 0 -> nie je aligned
    test edx, edx
    jz .no
    jmp .walk
.al_diag_nz:
    test r9d, r9d
    jz .no                  ; df == dr == 0
    jmp .walk
.al_diag:
    cmp r9d, edx
    jne .no
    test r9d, r9d
    jz .no
    jmp .walk
.al_straight:
    test r9d, r9d
    jz .al_str_v
    test edx, edx
    jnz .no                 ; rovne: dr musi byt 0
    jmp .walk
.al_str_v:
    test edx, edx
    jz .no
    jmp .walk
.walk:
    ; step = sign(df) + 8*sign(dr) -> r9d; cur = sq -> edx
    mov r9d, eax
    sar r9d, 31
    xor r8d, r8d
    test eax, eax
    setg r8b
    or r9d, r8d             ; sign(df)
    mov r8d, ecx
    sar r8d, 31
    xor edx, edx
    test ecx, ecx
    setg dl
    or r8d, edx             ; sign(dr)
    lea r9d, [r9d + r8d*8]  ; step
    mov edx, edi            ; cur
.walk_loop:
    add edx, r9d
    cmp edx, r10d
    je .yes                 ; dosli sme na target: utoci
    movzx eax, byte [rsi + rdx]
    test eax, eax
    jnz .no                 ; blokovane inou figurou
    jmp .walk_loop