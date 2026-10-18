; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; legal.asm - legal move filter a detekcia sachu
; ============================================================

%include "chess.inc"

DEFAULT REL

section .text

global find_king, is_square_attacked, is_in_check, filter_legal_moves

extern board, side, move_list, move_count, promo_pieces
extern bb_pieces, bb_side, bb_occ
extern is_square_attacked_bb

; ============================================================
; find_king - najde policko krala danej strany
; Vstup:  rax = side (0 = biely, 1 = cierny)
; Vystup: rax = index policka 0..63, alebo -1
; M2a: bitboard cesta cez bb_pieces[side*6 + KING-1]
; ============================================================
find_king:
    push rbx
    mov ebx, eax
    imul ebx, 6
    lea rdx, [bb_pieces]
    mov rax, [rdx + rbx*8 + 5*8]    ; king slot pre stranu
    test rax, rax
    jz .not_found
    bsf rax, rax
    jmp .done

.not_found:
    mov rax, -1
.done:
    pop rbx
    ret

; ============================================================
; is_square_attacked - zisti, ci je policko napadnute superom
; Vstup:  rax = policko (0..63), rbx = side (0 = biely, 1 = cierny)
; Vystup: rax = 1 ak je napadnute, inak 0
; E10/F1: mailbox verzia nahradena wrapperom cez bitboard query
; (is_square_attacked_bb z position.asm). Podpis je identicky;
; invariant F1 zarucuje aktualny bb stav (ziaden sync tu netreba).
; ============================================================
is_square_attacked:
    jmp is_square_attacked_bb

; ============================================================
; is_in_check - zisti, ci je kral danej strany v sachu
; Vstup:  rax = side
; Vystup: rax = 1 ak je v sachu, inak 0
; Bitboard cesta: bsf krala + is_square_attacked_bb (bb stav je
; konzistentny vdaka invariantu F3, ziaden re-sync netreba)
; ============================================================
is_in_check:
    push rbx
    push r12

    mov r12, rax

    mov rax, r12
    call find_king
    cmp rax, -1
    jz .not_in_check

    mov rbx, r12
    call is_square_attacked_bb
    test rax, rax
    jz .not_in_check

    mov rax, 1
    jmp .done
.not_in_check:
    xor rax, rax
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; filter_legal_moves - odstrani z move_list tahy, po ktorych
;                      by vlastny kral zostal v sachu
;
; F3 pure-bit cesta: per tah sa aplikuje iba bitboard delta
; (btr from / bts to + capture/EP/castle delty), zavola sa
; is_square_attacked_bb(king_sq, own) a delta sa revertuje XORom.
; board[64] sa vobec nedotyka (hot cesta bez mailbox make/unmake).
;
; filter_apply_move:  vstup r12 = tah
;                     vystup rbx = from, r13 = to, r14 = flags,
;                            r15 = captured byte (0 ak nie je)
; filter_unmake_move: vstup rbx/r13/r14/r15 z apply (xor je
;                     samoinverzny, side = mover)
; ============================================================
filter_legal_moves:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    sub rsp, 16             ; [rsp] = from (pre castle kontrolu)

    xor rcx, rcx            ; index i
.loop:
    movzx rdx, word [move_count]
    cmp rcx, rdx
    jge .done

    lea rsi, [move_list]
    movzx r12, word [rsi + rcx*2]

    call filter_apply_move
    mov [rsp], rbx          ; uloz from

    ; --- kontrola: vlastny kral v sachu? ---
    ; kralove policko priamo z bitboardov (aktualne po apply)
    movzx eax, byte [side]
    imul eax, 6
    lea rdx, [bb_pieces]
    mov rax, [rdx + rax*8 + 5*8]
    test rax, rax
    jz .remove              ; kral chyba (nemalo by nastat) -> drop
    bsf rax, rax            ; king_sq
    movzx rbx, byte [side]
    push rcx                ; is_square_attacked_bb je interne rcx (caller-saved!)
    call is_square_attacked_bb   ; zachova r12-r15, rbx
    pop rcx
    test rax, rax
    jnz .remove

    ; specialna kontrola rosady: kral nesmie prechadzat cez sach
    cmp r14, FLAG_CASTLE
    jne .legal

    mov rbx, [rsp]          ; from
    mov rax, r13
    sub rax, rbx
    sar rax, 1              ; smer = +/-1
    push rax                ; [rsp+8] = smer po push rcx
    push rcx
    movzx rbx, byte [side]
    mov rax, [rsp+16]       ; from
    push rcx
    call is_square_attacked_bb
    pop rcx
    test rax, rax
    jnz .castle_bad
    mov rax, [rsp+16]
    add rax, [rsp+8]        ; from + smer
    movzx rbx, byte [side]
    push rcx
    call is_square_attacked_bb
    pop rcx
    test rax, rax
    jnz .castle_bad
    mov rax, [rsp+16]
    mov r8, [rsp+8]         ; smer do r8 (rcx = loop index musi ostat)
    lea rax, [rax + r8*2]   ; from + 2*smer (= to)
    movzx rbx, byte [side]
    push rcx
    call is_square_attacked_bb
    pop rcx
    test rax, rax
    jnz .castle_bad
    pop rcx
    pop rax
    jmp .legal

.castle_bad:
    pop rcx
    pop rax
    jmp .remove

.legal:
    inc rcx
    mov rbx, [rsp]          ; obnov from (king check ho prepisal na side)
    call filter_unmake_move
    jmp .loop

.remove:
    ; nelegalny: odstran zo zoznamu (move_list je nezavisly od board)
    lea rsi, [move_list]
    movzx rdx, word [move_count]
    dec rdx
    mov [move_count], dx
    cmp rcx, rdx
    je .remove_done         ; ak posledny, iba zniz pocet
    movzx r8, word [rsi + rdx*2]
    mov [rsi + rcx*2], r8w
.remove_done:
    mov rbx, [rsp]          ; obnov from (king check ho prepisal na side)
    call filter_unmake_move
    jmp .loop               ; neinkrementuj, skontroluj swapped move

.done:
    add rsp, 16

    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; ============================================================
; filter_apply_move - pure-bit aplikacia tahu r12 na bb stav
; (board[64] sa NEDOTYKA; typ hybanej figury sa zisti z bitov)
; Vystup: rbx = from, r13 = to, r14 = flags, r15 = captured byte
; Nici: rax, rcx, rdx, rsi, rdi, r8-r11
; ============================================================
filter_apply_move:
    push rcx                ; zachovaj index filter slucky
    movzx rbx, r12w
    and rbx, 0x3F           ; from
    movzx r13, r12w
    shr r13, 6
    and r13, 0x3F           ; to
    movzx r14, r12w
    shr r14, 12             ; flags

    movzx r10d, byte [side]
    mov r11d, r10d
    xor r11d, 1
    imul r10d, r10d, 6      ; vlastny base slot
    imul r11d, r11d, 6      ; superov base slot

    mov r8, 1
    mov ecx, ebx
    shl r8, cl              ; fbit
    mov r9, 1
    mov ecx, r13d
    shl r9, cl              ; tbit

    cmp r14, FLAG_ENPASSANT
    je .ep
    cmp r14, FLAG_CASTLE
    je .castle
    cmp r14, FLAG_PROMO_Q
    jb .normal
    cmp r14, FLAG_PROMO_N
    jbe .promo

; ---------- normalny tah ----------
.normal:
    ; najdi vlastny slot obsahujuci fbit (typ hybanej figury)
    xor ecx, ecx
.find_m:
    lea rdi, [bb_pieces]
    mov edx, r10d
    add edx, ecx
    test [rdi + rdx*8], r8
    jnz .found_m
    inc ecx
    cmp ecx, 6
    jl .find_m
    jmp .fin                ; nenajdene (nemalo by nastat)
.found_m:
    mov edx, r10d
    add edx, ecx
    xor [rdi + rdx*8], r8
    xor [rdi + rdx*8], r9
    jmp .common

; ---------- promocia ----------
.promo:
    lea rdi, [bb_pieces]
    xor [rdi + r10*8], r8           ; pesiac odchadza z from
    lea rdi, [promo_pieces]
    movzx ecx, byte [rdi + r14]     ; promo typ
    dec ecx
    add ecx, r10d
    lea rdi, [bb_pieces]
    xor [rdi + rcx*8], r9           ; promo figurka na to
    jmp .common

; ---------- spolocny tail: bb_side + bb_occ + capture ----------
.common:
    movzx edx, byte [side]
    lea rdi, [bb_side]
    xor [rdi + rdx*8], r8
    xor [rdi + rdx*8], r9
    lea rdi, [bb_occ]
    xor [rdi], r8                   ; from sa uvofnuje
    movzx edx, byte [side]
    xor edx, 1
    lea rdi, [bb_side]
    test [rdi + rdx*8], r9          ; je na to superova figura?
    jnz .cap
    xor r15d, r15d
    lea rdi, [bb_occ]
    xor [rdi], r9                   ; bez capture: to sa obsadzuje
    jmp .fin
.cap:
    ; najdi superov slot obsahujuci tbit
    xor ecx, ecx
.find_c:
    lea rdi, [bb_pieces]
    mov edx, r11d
    add edx, ecx
    test [rdi + rdx*8], r9
    jnz .found_c
    inc ecx
    cmp ecx, 6
    jl .find_c
    jmp .fin
.found_c:
    mov r15d, ecx
    inc r15d                        ; captured = typ | enemy<<3
    movzx edx, byte [side]
    xor edx, 1
    shl edx, 3
    or r15d, edx
    mov edx, r11d
    add edx, ecx
    lea rdi, [bb_pieces]
    xor [rdi + rdx*8], r9
    movzx edx, byte [side]
    xor edx, 1
    lea rdi, [bb_side]
    xor [rdi + rdx*8], r9
    jmp .fin

; ---------- en passant ----------
.ep:
    ; brany pesiac: biely to-8, cierny to+8
    mov rdx, r13
    cmp byte [side], 0
    jne .ep_black
    sub rdx, 8
    jmp .ep_sq
.ep_black:
    add rdx, 8
.ep_sq:
    mov ecx, edx
    mov rax, 1
    shl rax, cl                     ; epbit
    lea rdi, [bb_pieces]
    mov rsi, r8
    xor rsi, r9
    xor [rdi + r10*8], rsi          ; vlastny pesiak: from->to
    xor [rdi + r11*8], rax          ; superov pesiak prec
    movzx edx, byte [side]
    lea rdi, [bb_side]
    xor [rdi + rdx*8], rsi
    movzx edx, byte [side]
    xor edx, 1
    xor [rdi + rdx*8], rax
    xor rsi, rax
    lea rdi, [bb_occ]
    xor [rdi], rsi
    mov r15d, PAWN
    movzx edx, byte [side]
    xor edx, 1
    shl edx, 3
    or r15d, edx
    jmp .fin

; ---------- rosada ----------
.castle:
    mov rsi, r8
    xor rsi, r9                     ; kralovska delta
    lea rdi, [bb_pieces]
    xor [rdi + r10*8 + 40], rsi     ; kral slot
    ; veza: WK 7->5, WQ 0->3, BK 63->61, BQ 56->59
    cmp r13, 6
    je .c_wk
    cmp r13, 2
    je .c_wq
    cmp r13, 62
    je .c_bk
    mov ecx, 56
    mov edx, 59
    jmp .c_rook
.c_wk:
    mov ecx, 7
    mov edx, 5
    jmp .c_rook
.c_wq:
    mov ecx, 0
    mov edx, 3
    jmp .c_rook
.c_bk:
    mov ecx, 63
    mov edx, 61
.c_rook:
    mov rax, 1
    shl rax, cl                     ; rfbit
    mov ecx, edx
    mov rdx, 1
    shl rdx, cl                     ; rtbit
    xor rax, rdx                    ; delta veze
    lea rdi, [bb_pieces]
    xor [rdi + r10*8 + 24], rax
    xor rsi, rax                    ; celkova delta
    movzx edx, byte [side]
    lea rdi, [bb_side]
    xor [rdi + rdx*8], rsi
    lea rdi, [bb_occ]
    xor [rdi], rsi
    xor r15d, r15d                  ; captured = EMPTY

.fin:
    pop rcx
    ret

; ============================================================
; filter_unmake_move - inverzna delta (xor je samoinverzny)
; Vstup: rbx = from, r13 = to, r14 = flags, r15 = captured byte
;        (side = mover, neprepinane)
; ============================================================
filter_unmake_move:
    push rcx                ; zachovaj index filter slucky
    movzx r10d, byte [side]
    mov r11d, r10d
    xor r11d, 1
    imul r10d, r10d, 6
    imul r11d, r11d, 6

    mov r8, 1
    mov ecx, ebx
    shl r8, cl                      ; fbit
    mov r9, 1
    mov ecx, r13d
    shl r9, cl                      ; tbit

    cmp r14, FLAG_ENPASSANT
    je .u_ep
    cmp r14, FLAG_CASTLE
    je .u_castle
    cmp r14, FLAG_PROMO_Q
    jb .u_normal
    cmp r14, FLAG_PROMO_N
    jbe .u_promo

; ---------- normalny tah ----------
; po apply je moved figura na 'to': hladaj vlastny slot s tbit
.u_normal:
    xor ecx, ecx
.uf_m:
    lea rdi, [bb_pieces]
    mov edx, r10d
    add edx, ecx
    test [rdi + rdx*8], r9
    jnz .ufound_m
    inc ecx
    cmp ecx, 6
    jl .uf_m
    jmp .u_fin
.ufound_m:
    mov edx, r10d
    add edx, ecx
    xor [rdi + rdx*8], r9
    xor [rdi + rdx*8], r8
    jmp .u_common

; ---------- promocia ----------
.u_promo:
    lea rdi, [bb_pieces]
    lea rax, [promo_pieces]
    movzx ecx, byte [rax + r14]     ; promo typ
    dec ecx
    add ecx, r10d
    xor [rdi + rcx*8], r9           ; promo figurka prec z to
    xor [rdi + r10*8], r8           ; pesiak spat na from
    jmp .u_common

; ---------- spolocny tail ----------
.u_common:
    movzx edx, byte [side]
    lea rdi, [bb_side]
    xor [rdi + rdx*8], r9
    xor [rdi + rdx*8], r8
    lea rdi, [bb_occ]
    xor [rdi], r8                   ; from sa opat obsadzuje
    test r15b, r15b
    jnz .u_cap
    xor [rdi], r9                   ; bez capture: to sa uvofnovalo
    jmp .u_fin
.u_cap:
    ; zajata figurka spat na to
    mov ecx, r15d
    and ecx, PIECE_MASK
    dec ecx
    add ecx, r11d
    lea rdi, [bb_pieces]
    xor [rdi + rcx*8], r9
    movzx edx, byte [side]
    xor edx, 1
    lea rdi, [bb_side]
    xor [rdi + rdx*8], r9
    jmp .u_fin

; ---------- en passant ----------
.u_ep:
    mov rdx, r13
    cmp byte [side], 0
    jne .u_ep_black
    sub rdx, 8
    jmp .u_ep_sq
.u_ep_black:
    add rdx, 8
.u_ep_sq:
    mov ecx, edx
    mov rax, 1
    shl rax, cl                     ; epbit
    lea rdi, [bb_pieces]
    mov rsi, r8
    xor rsi, r9
    xor [rdi + r10*8], rsi          ; vlastny pesiak spat
    xor [rdi + r11*8], rax          ; superov pesiak spat
    movzx edx, byte [side]
    lea rdi, [bb_side]
    xor [rdi + rdx*8], rsi
    movzx edx, byte [side]
    xor edx, 1
    xor [rdi + rdx*8], rax
    xor rsi, rax
    lea rdi, [bb_occ]
    xor [rdi], rsi
    jmp .u_fin

; ---------- rosada ----------
.u_castle:
    mov rsi, r8
    xor rsi, r9
    lea rdi, [bb_pieces]
    xor [rdi + r10*8 + 40], rsi     ; kral slot
    cmp r13, 6
    je .u_wk
    cmp r13, 2
    je .u_wq
    cmp r13, 62
    je .u_bk
    mov ecx, 56
    mov edx, 59
    jmp .u_c_rook
.u_wk:
    mov ecx, 7
    mov edx, 5
    jmp .u_c_rook
.u_wq:
    mov ecx, 0
    mov edx, 3
    jmp .u_c_rook
.u_bk:
    mov ecx, 63
    mov edx, 61
.u_c_rook:
    mov rax, 1
    shl rax, cl
    mov ecx, edx
    mov rdx, 1
    shl rdx, cl
    xor rax, rdx
    lea rdi, [bb_pieces]
    xor [rdi + r10*8 + 24], rax
    xor rsi, rax
    movzx edx, byte [side]
    lea rdi, [bb_side]
    xor [rdi + rdx*8], rsi
    lea rdi, [bb_occ]
    xor [rdi], rsi

.u_fin:
    pop rcx
    ret
