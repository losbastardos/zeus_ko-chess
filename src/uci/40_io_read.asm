uci_parse_int:
    push rbx
    push rcx
    xor rax, rax
    xor rcx, rcx
.loop:
    cmp rcx, rsi
    jge .done
    movzx rbx, byte [move_buf + rdi + rcx]
    sub rbx, '0'
    cmp rbx, 9
    ja .error
    imul rax, 10
    add rax, rbx
    inc rcx
    jmp .loop
.error:
    xor rax, rax
.done:
    pop rcx
    pop rbx
    ret

; ============================================================
; input_read_byte - precita jeden bajt stdin (najprv z input_pend)
; Vystup: al = bajt, rax = -1 ak EOF
; Nici len caller-saved registre (rax, rcx, rdx, rsi, r11)
; ============================================================
input_read_byte:
    mov rax, [input_pend_len]
    test rax, rax
    jz .from_stdin

    ; vyber prvy bajt z input_pend a zvysok posun do lava
    lea rsi, [input_pend]
    movzx r11d, byte [rsi]
    mov rcx, 1
.shift:
    cmp rcx, rax
    jae .shift_done
    mov dl, [rsi + rcx]
    mov [rsi + rcx - 1], dl
    inc rcx
    jmp .shift
.shift_done:
    dec rax
    mov [input_pend_len], rax
    movzx eax, r11b
    ret

.from_stdin:
    mov rax, SYS_READ
    xor edi, edi
    lea rsi, [input_pend]        ; buffer je prazdny, citame rovno do neho
    mov edx, 1
    syscall
    cmp rax, 1
    jne .eof
    movzx eax, byte [input_pend]
    ret

.eof:
    mov rax, -1
    ret

; ============================================================
; uci_read_line - nacita jeden riadok do move_buf
; Vystup: rax = dlzka riadku (bez newline), -1 ak EOF
; ============================================================
uci_read_line:
    push rbx
    push r12
    xor r12, r12

.read_loop:
    call input_read_byte
    cmp rax, -1
    je .eof
    mov [move_buf + r12], al
    cmp al, 10
    je .done
    inc r12
    cmp r12, 4095
    jl .read_loop

.consume:
    call input_read_byte
    cmp rax, -1
    je .done
    cmp al, 10
    je .done
    jmp .consume

.eof:
    mov rax, -1
    pop r12
    pop rbx
    ret

.done:
    mov [move_buf_len], r12
    mov byte [move_buf + r12], 0
    mov rax, r12
    pop r12
    pop rbx
    ret

; ============================================================
; uci_loop - hlavna UCI slucka
; ============================================================
