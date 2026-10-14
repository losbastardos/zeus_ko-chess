
; ============================================================
; tb_piece_count - spocita neprazdne policka na sachovnici
; Vystup: eax = pocet figurok na sachovnici (0..64)
; ============================================================
tb_piece_count:
    ; Ked je piece-list stav clean, sucet pl_counts je ekvivalentny board scanu.
    cmp byte [pl_dirty], 0
    jne .scan_board
    xor eax, eax
    xor ecx, ecx
.sum_counts:
    cmp ecx, 12
    jae .done
    movzx edx, byte [pl_counts + rcx]
    add eax, edx
    inc ecx
    jmp .sum_counts

.scan_board:
    lea rdx, [board]
    xor eax, eax
    xor ecx, ecx
.scan:
    cmp ecx, 64
    jae .done
    cmp byte [rdx + rcx], EMPTY
    je .next
    inc eax
.next:
    inc ecx
    jmp .scan
.done:

    ret
