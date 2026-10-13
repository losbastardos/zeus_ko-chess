perft:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rbp, rsp
    mov r15, rdi            ; depth uloz pred helper volaniami

%if ENABLE_PL_INFRA = 1
    cmp qword [undo_sp], 0
    jne .perft_have_pl
    call pl_rebuild_from_board
.perft_have_pl:
%endif

    test r15, r15
    jnz .recurse
    mov rax, 1
    jmp .done

.recurse:
    call generate_all_moves
    movzx r14, word [move_count]
    test r14, r14
    jz .zero

    ; lokalna kopia zoznamu tahov
    mov rax, r14
    shl rax, 1
    add rax, 15
    and rax, ~15
    sub rsp, rax

    lea rsi, [move_list]
    mov rdi, rsp
    mov rcx, r14
.copy_loop:
    mov ax, [rsi]
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    dec rcx
    jnz .copy_loop

    xor r13, r13            ; celkovy pocet
    xor r12, r12            ; index tahu

.move_loop:
    cmp r12, r14
    jge .loop_done

    movzx rax, word [rsp + r12*2]

    push r12
    push r13
    call make_move

    mov rdi, r15
    dec rdi
    call perft
    mov rbx, rax            ; uloz vysledok

    call unmake_move

    pop r13
    pop r12
    add r13, rbx
    inc r12
    jmp .move_loop

.loop_done:
    mov rax, r13
    jmp .done

.zero:
    xor rax, rax

.done:
    mov rsp, rbp
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; ============================================================
; collect_pv - ulozi celu PV do pv_moves[] (pre panel/UCI)
; Pouziva predpocitanu pv_table z searchu (rychlejsie ako TT sonda).
; ============================================================
collect_pv:
    push rsi
    push rdi
    push rcx
    push rax

    mov rax, [root_pv_len]  ; dlzka root PV
    cmp rax, 40
    jle .len_ok
    mov rax, 40
.len_ok:
    mov [pv_moves_len], rax

    mov rcx, rax
    lea rsi, [root_pv_table] ; zdroj
    lea rdi, [pv_moves]      ; ciel
    rep movsw

    pop rax
    pop rcx
    pop rdi
    pop rsi
    ret

; ============================================================
; book_pick_move - knizny tah s volitenym vypoctom
; book_mode=0: legacy — prvy knizny tah (okamzity)
; book_mode=1: "thinking book" — engine si vypocita svoj najlepsi tah
;   na book_search_depth (search_best_move) a knizny tah overi:
;   - ak je search-best v knihe -> hra sa search-best (kniha suhlasi)
;   - inak sa knizny tah ohodnoti (make/negamax/unmake); ak je v
;     margine BOOK_MARGIN cp od search-best, hra sa knizny (zachova
;     opening znalost/inventory), inak prevezme search-best
; Vystup: rax = 16-bit tah, 0 = ziaden knizny tah
; ============================================================
%define BOOK_MARGIN 80

global book_pick_move
book_pick_move:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov byte [book_rating_flag], 1
    call book_lookup_all          ; naplni book_moves / book_moves_len
    mov r12, [book_moves_len]
    test r12, r12
    jz .none
    cmp byte [book_mode], 0
    je .first
    ; vlastny vypocet: najlepsi tah na nizkej hlbke
    movzx rdi, byte [book_search_depth]
    call search_best_move
    mov rbx, rax                  ; search-best move
    test rbx, rbx
    jz .first                     ; search nenasiel nic -> knizny prvy
    mov r13d, dword [search_last_score]  ; search-best skore
    ; je search-best v knihe?
    xor rcx, rcx
.find_loop:
    cmp rcx, r12
    jae .verify_book
    lea rax, [book_moves]
    movzx edx, word [rax + rcx*2]
    cmp edx, ebx
    je .return_best               ; kniha suhlasi s vypoctom
    inc rcx
    jmp .find_loop
.verify_book:
    ; ohodnot prvy knizny tah
    lea rax, [book_moves]
    movzx r14d, word [rax]
    mov rax, r14
    call make_move
    movzx rdi, byte [book_search_depth]
    dec rdi
    mov rsi, -INF
    mov rdx, INF
    mov rcx, 1
    call negamax
    neg eax                       ; skore knizneho tahu z pohladu root
    mov r15d, eax
    call unmake_move
    ; knizny v margine? -> hra sa knizny, inak search-best
    mov eax, r13d
    sub eax, r15d                 ; search_best - book
    cmp eax, BOOK_MARGIN
    jg .return_book
.return_best:
    mov rax, rbx
    jmp .ret
.return_book:
    mov eax, r14d
    jmp .ret
.first:
    lea rax, [book_moves]
    movzx eax, word [rax]
    jmp .ret
.none:
    xor eax, eax
.ret:
    mov byte [book_rating_flag], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

