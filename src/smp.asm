; ============================================================
; smp.asm - Lazy SMP helper procesy (clone bez CLONE_VM)
; Ucel: shared stop-flag stranka + spawn/reap helperov.
; Helperi maju vlastny BSS (COW), zdielaju len TT (MAP_SHARED)
; a tuto stop stranku. Bestmove vzdy z hlavneho procesu.
; ============================================================

%include "chess.inc"

DEFAULT REL

; SYS_MMAP chyba v chess.inc, definujeme lokalne (SYS_EXIT, SYS_WAIT4,
; SYS_CLOCK_GETTIME, SYS_CLONE, CLOCK_MONOTONIC uz existuju)
%define SYS_MMAP        9
%define SYS_MUNMAP      11
%define PROT_RW         3        ; PROT_READ|PROT_WRITE
%define MAP_SH_ANON     0x21     ; MAP_SHARED|MAP_ANONYMOUS
%define MAP_ANON        34       ; MAP_PRIVATE|MAP_ANONYMOUS (inak EINVAL)
%define SIGCHLD         17

%define SMP_MAX_WORKERS 7
%define SMP_STACK_SIZE  (8*1024*1024)

section .bss
smp_status: resd 1
smp_timespec: resq 2
smp_stack_tops: resq SMP_MAX_WORKERS   ; topy mmap stackov (parent ich nepoužíva)

section .text

global smp_init, smp_clear_stop, smp_check_stop, smp_signal_stop
global smp_spawn_helpers, smp_stop_and_reap, smp_worker_main
extern smp_shared, smp_child_count
extern uci_threads, uci_stop_flag
extern search_best_move, search_last_score, nodes_searched, asp_use
extern smp_worker_mode, smp_child_pids, search_limits

; ============================================================
; smp_init - vytvor (alebo zrecykluj) MAP_SHARED stranku
; ============================================================
smp_init:
    cmp qword [smp_shared], 0
    jne .clear
    mov rax, SYS_MMAP
    xor rdi, rdi
    mov rsi, 4096
    mov rdx, PROT_RW
    mov r10, MAP_SH_ANON
    mov r8, -1
    xor r9, r9
    syscall
    cmp rax, -4096
    ja .fail            ; chyba: shared stop nepojde, SMP sa vypne
    mov [smp_shared], rax
.clear:
    mov rax, [smp_shared]
    mov byte [rax], 0
.fail:
    ret

; ============================================================
; smp_clear_stop - vynuluj stop flag pre novy search
; ============================================================
smp_clear_stop:
    mov rax, [smp_shared]
    test rax, rax
    jz .done
    mov byte [rax], 0
    mov qword [rax + 8], 0      ; vynuluj agregovane helper uzly z predch. searchu
.done:
    ret

; ============================================================
; smp_check_stop - eax=1 ak helperi/hlavny proces signalizoval stop
; Bezpecne volatelne z lubovolneho procesu.
; ============================================================
smp_check_stop:
    mov rax, [smp_shared]
    test rax, rax
    jz .no
    cmp byte [rax], 0
    je .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; ============================================================
; smp_signal_stop - nastav stop pre vsetky helper procesy
; ============================================================
smp_signal_stop:
    mov rax, [smp_shared]
    test rax, rax
    jz .done
    mov byte [rax], 1
.done:
    ret

; ============================================================
; smp_spawn_helpers - spusti (uci_threads - 1) helper procesov
; Vstup: nic (berie [uci_threads]); pozicia + search_limits su finalne.
; Helperi zdedia COW kopiu celeho stavu (board, undo, limity).
; ============================================================
smp_spawn_helpers:
    push rbx
    push r12
    mov r12d, 1                  ; worker index 1..uci_threads-1
.loop:
    mov eax, [uci_threads]
    cmp r12d, eax
    jge .done
    cmp r12d, 8
    jge .done
    ; vlastny stack pre helper (COW kopiu dostane child)
    mov rax, SYS_MMAP
    xor rdi, rdi
    mov rsi, SMP_STACK_SIZE
    mov rdx, PROT_RW
    mov r10, MAP_ANON            ; 0x20, privatny
    mov r8, -1
    xor r9, r9
    syscall
    cmp rax, -4096
    ja .done                     ; mmap zlyhal: pokracujeme s menej helpermi
    lea rbx, [rax + SMP_STACK_SIZE]  ; top stacku
    mov [smp_stack_tops + r12*8 - 8], rbx
    ; clone(SIGCHLD) bez CLONE_VM = lightweight proces
    mov rax, SYS_CLONE
    mov rdi, SIGCHLD
    mov rsi, rbx                 ; child stack top
    xor rdx, rdx
    xor r10, r10
    xor r8, r8
    syscall
    test rax, rax
    js .done                     ; clone zlyhal: menej helperov
    jz .child
    ; parent: uloz pid
    mov [smp_child_pids + r12*8], rax
    inc dword [smp_child_count]
    inc r12d
    jmp .loop
.child:
    ; child: register state je zdedeny (rax=0), worker index je v r12
    mov rdi, r12
    jmp smp_worker_main          ; worker nikdy nevracia
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; smp_worker_main - vstup helpera (vlastny BSS, vlastny stack)
; rdi = worker index. Hra full-root ID slucku, plni zdielanu TT.
; Kontroluje len shared stop + vlastny hard limit (stdin NEPOLLUJ).
; ============================================================
smp_worker_main:
    push rbx
    push r12
    push r13
    sub rsp, 8                   ; alignment: vstup rsp=0 (jmp bez retaddr), po 3 push ≡8; call vyzaduje ≡0
    mov rbx, rdi                 ; worker index (pre pripadnu diagnostiku)
    mov dword [smp_worker_mode], 1   ; zabrani rekurzivnemu SMP dispatch
    mov r12, 1                   ; depth
.id_loop:
    call smp_check_stop
    test eax, eax
    jnz .done
    ; hard time limit (vlastna kopia search_limits)
    movzx eax, byte [search_limits + 0]
    cmp eax, 3                   ; infinite
    je .no_limit
    cmp eax, 4                   ; ponder
    je .no_limit
    mov rax, [search_limits + 64]    ; hard_limit ms
    test rax, rax
    jz .no_limit
    mov rax, SYS_CLOCK_GETTIME
    mov rdi, CLOCK_MONOTONIC
    lea rsi, [smp_timespec]
    syscall
    test rax, rax
    js .no_limit
    mov rax, [smp_timespec]
    imul rax, 1000
    mov r13, rax
    mov rax, [smp_timespec + 8]
    mov rcx, 1000000
    xor rdx, rdx
    div rcx
    add rax, r13
    sub rax, [search_limits + 48]    ; elapsed ms
    cmp rax, [search_limits + 64]
    jge .done
.no_limit:
    mov dword [asp_use], 0           ; helper bez aspiration window
    mov qword [nodes_searched], 0
    mov rdi, r12
    call search_best_move
    ; agreguj uzly tejto iteracie do zdielanej stranky (+8);
    ; search_best_move resetuje nodes_searched kazdu iteraciu, preto pripocitavame tu
    mov rcx, [smp_shared]
    test rcx, rcx
    jz .no_agg
    mov rax, [nodes_searched]
    lock add [rcx + 8], rax
.no_agg:
    inc r12
    cmp r12, 64
    jle .id_loop
.done:
    mov eax, SYS_EXIT
    xor edi, edi
    syscall

; ============================================================
; smp_stop_and_reap - signalizuj stop a pockaj na vsetkych helperov
; ============================================================
smp_stop_and_reap:
    call smp_signal_stop
.reap_loop:
    cmp dword [smp_child_count], 0
    jle .unmap_stacks
    mov rax, SYS_WAIT4
    mov rdi, -1                  ; lubovolne dieta
    lea rsi, [smp_status]
    xor edx, edx
    xor r10d, r10d
    syscall
    test rax, rax
    js .unmap_stacks             ; chyba (zombie uz nie su) - koncime
    dec dword [smp_child_count]
    jmp .reap_loop
.unmap_stacks:
    ; uvolnime vsetky mmap helper stacky (aj tych, ktorym clone zlyhal);
    ; po munmape slot vynulujeme, aby sa pri dalsom go znova mmmapli
    ; counter v rbx: syscall prepsie rcx (return RIP), ecx by slucku zrusil
    push rbx
    mov ebx, 1
.unmap_loop:
    cmp ebx, SMP_MAX_WORKERS
    jg .unmap_done
    mov rsi, [smp_stack_tops + rbx*8 - 8]
    test rsi, rsi
    jz .unmap_next
    mov rax, SYS_MUNMAP
    lea rdi, [rsi - SMP_STACK_SIZE]
    mov rsi, SMP_STACK_SIZE
    syscall
    mov qword [smp_stack_tops + rbx*8 - 8], 0
.unmap_next:
    inc ebx
    jmp .unmap_loop
.unmap_done:
    pop rbx
.done:
    ret
