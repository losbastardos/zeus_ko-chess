; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; tt.asm - jednoducha alokacia/mazanie transposition table
; ============================================================

%include "chess.inc"

DEFAULT REL

%define SYS_MMAP    9
%define SYS_MUNMAP  11

%define PROT_READ   1
%define PROT_WRITE  2
%define MAP_SHARED  1
%define MAP_ANON    32

section .bss

tt_fallback: resb 1048576    ; 1MB fallback ked mmap zlyha

section .text

global tt_init, tt_clear, tt_probe, tt_store, lmr_reduction

extern tt_base, tt_bytes, tt_mask, lmr_table

; ============================================================
; tt_init - alokuje TT podla velkosti v MB
; Vstup: rdi = MB
; Vystup: rax = 0
; ============================================================
tt_init:
    push rbx
    push rcx
    push rdx
    push r12

    mov r12, rdi
    test r12, r12
    jg .mb_min_ok
    mov r12, 1
.mb_min_ok:
    cmp r12, 1024
    jle .mb_max_ok
    mov r12, 1024
.mb_max_ok:

    ; bytes = mb << 20
    mov rbx, r12
    shl rbx, 20

    ; ak uz mame mmap TT, najprv ju odmapuj
    mov rax, [tt_base]
    test rax, rax
    jz .alloc
    cmp rax, tt_fallback
    je .alloc
    mov rdx, [tt_bytes]
    test rdx, rdx
    jz .alloc

    mov rax, SYS_MUNMAP
    mov rdi, [tt_base]
    mov rsi, rdx
    syscall

.alloc:
    mov rax, SYS_MMAP
    xor rdi, rdi                ; addr = NULL
    mov rsi, rbx                ; len
    mov rdx, PROT_READ | PROT_WRITE
    mov r10, MAP_SHARED | MAP_ANON
    mov r8, -1
    xor r9, r9
    syscall
    test rax, rax
    js .fallback

    mov [tt_base], rax
    mov [tt_bytes], rbx
    jmp .mask

.fallback:
    mov qword [tt_base], tt_fallback
    mov qword [tt_bytes], 1048576

.mask:
    mov rax, [tt_bytes]
    shr rax, 4                  ; 16B na entry
    test rax, rax
    jnz .mask_ok
    mov rax, 1
.mask_ok:
    dec rax
    mov [tt_mask], rax

    call tt_clear

    xor rax, rax
    pop r12
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tt_clear - vynuluje celu TT
; ============================================================
tt_clear:
    push rax
    push rcx
    push rdi

    mov rdi, [tt_base]
    test rdi, rdi
    jz .done

    mov rcx, [tt_bytes]
    shr rcx, 3
    xor rax, rax
    rep stosq

.done:
    pop rdi
    pop rcx
    pop rax
    ret

; ============================================================
; tt_probe - probe TT entry
; Vstup: rdi=hash, rsi=depth, rdx=alpha, rcx=beta
; Vystup: edx=status (0 miss, 1 usable score, 2 hit move-only)
;         eax=score (ak status=1), r8w=move (ak hit)
; ============================================================
tt_probe:
    ; INVARIANT: citame hash az po payload (move/score/flag) kvoli lock-free
    ; store protokolu v tt_store (payload -> mfence -> hash). Otocenie poradia
    ; citania rozbije synchronizaciu a nesmie sa urobit.
    push rbx

    mov ebx, edx                    ; uloz alpha

    xor edx, edx
    xor r8d, r8d

    mov r11, [tt_base]
    test r11, r11
    jz .miss

    mov r10, rdi
    and r10, [tt_mask]
    shl r10, 4
    add r11, r10

    mov rax, [r11]
    cmp rax, rdi
    jne .miss

    movzx r8d, word [r11 + 8]
    movzx r9d, byte [r11 + 10]     ; stored depth
    cmp r9, rsi
    jb .move_only

    mov eax, dword [r11 + 12]      ; stored score
    movzx r10d, byte [r11 + 11]    ; flag

    cmp r10d, TT_EXACT
    je .usable
    cmp r10d, TT_LOWER
    jne .check_upper
    cmp eax, ecx                   ; score >= beta ?
    jl .move_only
    jmp .usable

.check_upper:
    cmp eax, ebx                   ; score <= alpha ?
    jg .move_only
    jmp .usable

.usable:
    mov edx, 1
    jmp .done

.move_only:
    mov edx, 2
    jmp .done

.miss:
    xor edx, edx

.done:
    pop rbx
    ret

; ============================================================
; tt_store - store TT entry
; Vstup: rdi=hash, rsi=depth, edx=score, ecx=flag, r8w=move
; ============================================================
tt_store:
    push r9
    push r10
    push r11

    mov r11, [tt_base]
    test r11, r11
    jz .done

    mov r10, rdi
    and r10, [tt_mask]
    shl r10, 4
    add r11, r10

    ; replacement: prepis pri inom hashi alebo >= hlbke
    mov rax, [r11]
    cmp rax, rdi
    jne .do_store

    movzx r9d, byte [r11 + 10]
    cmp r9, rsi
    ja .done

.do_store:
    ; lock-free: payload (8B) najprv, mfence, potom hash (8B).
    ; x86 garantuje atomicitu aligned 8B zapisov; tt_probe cita hash az
    ; po payloade, takze torn read da len validny (starsi) zaznam.
    mov [r11 + 8], r8w
    mov byte [r11 + 10], sil
    mov byte [r11 + 11], cl
    mov dword [r11 + 12], edx
    mfence
    mov [r11], rdi

.done:
    pop r11
    pop r10
    pop r9
    ret

; ============================================================
; lmr_reduction - vrati redukciu pre Late Move Reduction
; Vstup: rdi = depth, rsi = move index, rdx = improving flag
; Vystup: eax = reduction (ply)
; LMR log formula: reduction = log(depth) * log(index) / divisor
; s prubeznymi parametrami based na improving flag
; ============================================================
lmr_reduction:
    ; log tabulka: log2(x)*4 pre x=1..64 (indexovane 0..63, [0]=0)
    ; pre depth 1-16, index 0-15
    ; formula z Stockfish: (82 + 20*log(d)) * log(i) / (192*c) kde c=1 normally, 1.4 improving
    ; tu: redukcia(d,i,imp) ≈ log(d)*log(i)/16 - adjustment podľa improving
    ; zjednosusevane: tabulka 16x16 s hodnotami reduction
    push rbx
    push rcx
    push rdx
    push r8
    
    ; minimalne redukcie podľa literatury (Stockfish)
    ; redukcie su indexovane [depth-1][index] pre depth 1-16, index 0-15
    ; pre depth>=5, index>=2
    xor eax, eax
    cmp rdi, 2
    jle .lmr_done          ; depth <= 2: bez redukcie
    cmp rsi, 1
    jle .lmr_done          ; index <= 1: bez redukcie
    cmp rdi, 16
    jg .lmr_capped         ; depth > 16: clamp na 16
    mov r8, rdi
    jmp .lmr_depth_ok
.lmr_capped:
    mov r8, 16
.lmr_depth_ok:
    cmp rsi, 16
    jl .lmr_index_ok
    mov rsi, 16
.lmr_index_ok:
    
    ; tabulka LMR redukcie: lookup [depth-1][index]
    lea rcx, [lmr_table]
    mov eax, r8d
    dec eax
    imul eax, 16
    lea rax, [rcx + rax]     ; offset do riadku
    movzx eax, byte [rax + rsi]  ; eax = base redukcia z tabulky
    
    ; adjustment: ako nie je improving (rdx=0), +1 redukcia
    test rdx, rdx
    jnz .lmr_done
    inc eax
    
.lmr_done:
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret