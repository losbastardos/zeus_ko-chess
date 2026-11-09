; ============================================================
; material.asm - zber materialu a stavba canonical nazvu TB suboru
; ============================================================

section .bss

tb_board_pieces: resb 16        ; [0..7] white, [8..15] black (typy bez farby)

section .text

global tb_board_pieces

; ============================================================
; tb_material_scan - zozbiera ne-kralovske figury oboch stran
; Vystup: eax = pocet ne-kralovskych figur (0..16)
; ============================================================
tb_material_scan:
    push rbx
    push rcx
    push rdx
    push r8
    push r9

    lea rbx, [tb_board_pieces]
    xor ecx, ecx
.clear:
    cmp ecx, 16
    jae .clear_done
    mov byte [rbx + rcx], 0
    inc ecx
    jmp .clear
.clear_done:

    lea rdx, [board]
    xor ecx, ecx
    xor eax, eax
    xor r8d, r8d                  ; white idx
    xor r9d, r9d                  ; black idx
.scan:
    cmp ecx, 64
    jae .done
    movzx esi, byte [rdx + rcx]
    test esi, esi
    jz .next
    mov edi, esi
    and edi, PIECE_MASK
    cmp edi, KING
    je .next

    test esi, COLOR_MASK
    jz .white_piece

    cmp r9d, 8
    jae .count_only
    mov [rbx + 8 + r9], dil
    inc r9d
    jmp .count_only

.white_piece:
    cmp r8d, 8
    jae .count_only
    mov [rbx + r8], dil
    inc r8d

.count_only:
    inc eax
.next:
    inc ecx
    jmp .scan

.done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_build_canonical_name
; Vstup: rdi = destination buffer, rsi = offset po base dir + '/'
; Vystup: rax = novy offset, 0 pri chybe
; Format: K{white_sorted}vK{black_sorted}
; ============================================================
tb_build_canonical_name:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    ; count non-king pieces per side (0..8)
    xor r8d, r8d                  ; white cnt
    xor r9d, r9d                  ; black cnt
    xor edx, edx
.cnt_loop:
    cmp edx, 8
    jae .cnt_done
    movzx eax, byte [tb_board_pieces + rdx]
    test eax, eax
    jz .cnt_white_next
    inc r8d
.cnt_white_next:
    movzx eax, byte [tb_board_pieces + 8 + rdx]
    test eax, eax
    jz .cnt_black_next
    inc r9d
.cnt_black_next:
    inc edx
    jmp .cnt_loop
.cnt_done:

    ; material score per side (P=1, N/B=3, R=5, Q=9)
    xor r10d, r10d                ; white score
    xor r11d, r11d                ; black score
    xor edx, edx
.score_loop:
    cmp edx, 8
    jae .score_done

    movzx eax, byte [tb_board_pieces + rdx]
    call .piece_value
    add r10d, eax

    movzx eax, byte [tb_board_pieces + 8 + rdx]
    call .piece_value
    add r11d, eax

    inc edx
    jmp .score_loop
.score_done:
    xor edx, edx
    mov eax, r11d
    cmp eax, r10d
    setg dl                        ; dl=1 ak black score > white score

    ; side A = materialne silnejsia strana (pri rovnosti white)
    lea r10, [tb_board_pieces]        ; side A pieces
    lea r11, [tb_board_pieces + 8]    ; side B pieces
    test dl, dl
    jz .sides_ready
    lea r10, [tb_board_pieces + 8]
    lea r11, [tb_board_pieces]
.sides_ready:

    cmp r13, TB_PATH_MAX - 1
    jae .fail
    mov byte [r12 + r13], 'K'
    inc r13

    mov ecx, QUEEN
.sidea_type_loop:
    cmp ecx, PAWN
    jb .sidea_done
    xor edx, edx
.sidea_scan:
    cmp edx, 8
    jae .sidea_next_type
    movzx eax, byte [r10 + rdx]
    cmp eax, ecx
    jne .sidea_scan_next
    mov al, 'P'
    cmp ecx, PAWN
    je .sidea_emit
    mov al, 'N'
    cmp ecx, KNIGHT
    je .sidea_emit
    mov al, 'B'
    cmp ecx, BISHOP
    je .sidea_emit
    mov al, 'R'
    cmp ecx, ROOK
    je .sidea_emit
    mov al, 'Q'
.sidea_emit:
    cmp r13, TB_PATH_MAX - 1
    jae .fail
    mov [r12 + r13], al
    inc r13
.sidea_scan_next:
    inc edx
    jmp .sidea_scan
.sidea_next_type:
    dec ecx
    jmp .sidea_type_loop
.sidea_done:

    cmp r13, TB_PATH_MAX - 1
    jae .fail
    mov byte [r12 + r13], 'v'
    inc r13

    cmp r13, TB_PATH_MAX - 1
    jae .fail
    mov byte [r12 + r13], 'K'
    inc r13

    mov ecx, QUEEN
.sideb_type_loop:
    cmp ecx, PAWN
    jb .sideb_done
    xor edx, edx
.sideb_scan:
    cmp edx, 8
    jae .sideb_next_type
    movzx eax, byte [r11 + rdx]
    cmp eax, ecx
    jne .sideb_scan_next
    mov al, 'P'
    cmp ecx, PAWN
    je .sideb_emit
    mov al, 'N'
    cmp ecx, KNIGHT
    je .sideb_emit
    mov al, 'B'
    cmp ecx, BISHOP
    je .sideb_emit
    mov al, 'R'
    cmp ecx, ROOK
    je .sideb_emit
    mov al, 'Q'
.sideb_emit:
    cmp r13, TB_PATH_MAX - 1
    jae .fail
    mov [r12 + r13], al
    inc r13
.sideb_scan_next:
    inc edx
    jmp .sideb_scan
.sideb_next_type:
    dec ecx
    jmp .sideb_type_loop
.sideb_done:

    mov rax, r13
    jmp .done

.piece_value:
    ; vstup eax=piece type, vystup eax=value
    cmp eax, PAWN
    je .pv_p
    cmp eax, KNIGHT
    je .pv_n
    cmp eax, BISHOP
    je .pv_b
    cmp eax, ROOK
    je .pv_r
    cmp eax, QUEEN
    je .pv_q
    xor eax, eax
    ret
.pv_p:
    mov eax, 1
    ret
.pv_n:
.pv_b:
    mov eax, 3
    ret
.pv_r:
    mov eax, 5
    ret
.pv_q:
    mov eax, 9
    ret

.fail:
    xor eax, eax

.done:
    pop r13
    pop r12
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tb_material_symmetric
; Vstup: tb_board_pieces (naplnene tb_material_scan)
; Vystup: eax = 1 ak biely a cierny ne-kralovsky material je ako multiset
;         rovnaky (KXvKX symetria), inak 0
; ============================================================
global tb_material_symmetric
tb_material_symmetric:
    push rbx
    push rcx
    push rdx
    push r8
    push r9

    lea rbx, [tb_board_pieces]
    mov ecx, PAWN
.type_loop:
    cmp ecx, KING
    ja .sym
    xor edx, edx                  ; white count
    xor r8d, r8d                  ; black count
    xor r9d, r9d
.cnt:
    cmp r9d, 8
    jae .cnt_done
    movzx eax, byte [rbx + r9]
    cmp eax, ecx
    jne .cnt_b
    inc edx
.cnt_b:
    movzx eax, byte [rbx + 8 + r9]
    cmp eax, ecx
    jne .cnt_next
    inc r8d
.cnt_next:
    inc r9d
    jmp .cnt
.cnt_done:
    cmp edx, r8d
    jne .asym
    inc ecx
    jmp .type_loop
.sym:
    mov eax, 1
    jmp .ms_done
.asym:
    xor eax, eax
.ms_done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret
