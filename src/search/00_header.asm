; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; search.asm - NegaMax search s make/unmake
; ============================================================

%include "chess.inc"

DEFAULT REL

; A/B diagnostika heuristik (default = zapnute)
%ifndef ENABLE_PROBCUT
%define ENABLE_PROBCUT 1
%endif
%ifndef ENABLE_RFP
%define ENABLE_RFP 1
%endif
%ifndef ENABLE_RAZOR
%define ENABLE_RAZOR 1
%endif
%ifndef ENABLE_NULL_PRUNE
%define ENABLE_NULL_PRUNE 1
%endif
%ifndef ENABLE_LMP
%define ENABLE_LMP 1
%endif
%ifndef ENABLE_FUTILITY
%define ENABLE_FUTILITY 1
%endif
%ifndef ENABLE_LMR
%define ENABLE_LMR 1
%endif
%ifndef LMR_INDEX_MIN
%define LMR_INDEX_MIN 5
%endif
%ifndef LMR_DEPTH_MIN
%define LMR_DEPTH_MIN 3
%endif
%ifndef LMR_BASE_REDUCTION
%define LMR_BASE_REDUCTION 1
%endif
%ifndef LMR_EXTRA_NON_IMPROVING
%define LMR_EXTRA_NON_IMPROVING 1
%endif
%ifndef ENABLE_SINGULAR
%define ENABLE_SINGULAR 1
%endif
%ifndef ENABLE_TT
%define ENABLE_TT 1
%endif
%ifndef ENABLE_QDELTA
%define ENABLE_QDELTA 1
%endif
%ifndef ENABLE_CORR_HISTORY
%define ENABLE_CORR_HISTORY 1
%endif
%ifndef ENABLE_SEE_AUDIT
%define ENABLE_SEE_AUDIT 0
%endif
%ifndef ENABLE_PL_INFRA
%define ENABLE_PL_INFRA 1
%endif
%ifndef ENABLE_PL_INVARIANT
%define ENABLE_PL_INVARIANT 0
%endif

UNDO_ENTRY_SIZE      equ 256
UNDO_BASE_SIZE       equ 16
UNDO_PL_SNAPSHOT_OFF equ 16
PL_STATE_SIZE        equ 240
PL_LISTS_SIZE        equ 192     ; 12 * 16
PL_COUNTS_SIZE       equ 12      ; 12 * 1

; Search pruning konstanty (E9)
RAZOR_MARGIN    equ 250         ; razoring: eval + margin < alpha pri depth 1
FUTILITY_MARGIN equ 150         ; futility: margin = FUTILITY_MARGIN * depth (d1: 150, d2: 300)
EVAL_NONE       equ 0x7FFFFF00  ; sentinel: ziadny static eval (uzol v sachu)

%define PROT_READ   1
%define PROT_WRITE  2
%define MAP_SHARED  1
%define MAP_ANON    32
%define SIGCHLD     17
%define FUTEX_WAIT  0
%define FUTEX_WAKE  1

section .data

q_capture_value:
    dd 0, 100, 320, 330, 500, 900, 0

trace_w_init_prefix: db "info string wtrace init best_init=", 0
trace_w_alpha_init:  db " alpha_init=", 0
trace_w_stm:         db " stm=", 0
trace_w_fen:         db " fen=", 0
trace_w_reply_prefix: db "info string wtrace reply move=", 0
trace_w_score:       db " score=", 0
trace_w_flag:        db " flag=", 0
trace_w_alpha:       db " alpha=", 0
trace_w_beta:        db " beta=", 0
trace_w_eval:        db " eval_search=", 0
trace_w_final_prefix: db "info string wtrace final best=", 0
trace_w_returned:    db " returned=", 0
trace_w_flag_exact:  db "exact", 0
trace_w_flag_fl:     db "fail-low", 0
trace_w_flag_fh:     db "fail-high", 0

evalchk_pre_hdr:     db "info string evalchk pre_guard mismatch ply=", 0
evalchk_post_hdr:    db "info string evalchk post_eval mismatch ply=", 0
evalchk_list:        db " list=", 0
evalchk_scan:        db " scan=", 0
evalchk_fen:         db "info string evalchk fen=", 0
evalchk_cmp:         db "info string evalchk compare pl_equal=", 0
evalchk_first_list:  db " first_diff_list=", 0
evalchk_first_off:   db " first_diff_off=", 0
evalchk_first_idx:   db " first_diff_idx=", 0
evalchk_first_cur:   db " cur=", 0
evalchk_first_reb:   db " reb=", 0
evalchk_counts:      db "info string evalchk counts ", 0
evalchk_lists:       db "info string evalchk list_head ", 0
evalchk_l9:          db "info string evalchk list9_count cur/reb=", 0
evalchk_c_prefix:    db "c", 0
evalchk_r_prefix:    db "r", 0
evalchk_i_prefix:    db " i", 0
evalchk_eq:          db "=", 0
evalchk_slash:       db "/", 0
evalchk_space:       db " ", 0

%if ENABLE_SEE_AUDIT = 1
see_audit_prefix:        db "info string see_audit calls=", 0
see_audit_repeats_txt:   db " repeats=", 0
see_audit_qnodes_txt:    db " qnodes=", 0
see_audit_ratio_txt:     db " calls_per_qnode_x1000=", 0
%endif

section .bss

undo_stack:     resb 64*UNDO_ENTRY_SIZE ; miesto pre 64 undo zaznamov
undo_sp:        resq 1          ; offset (v bajtoch) do undo_stack
nnue_delta_applied: resb 1      ; E10/F2: nnue2_move_delta(_inv) vratil 1
pl_dirty:       resb 1          ; 1 = piece-list stav treba rebuildnut z board
pl_lists:       resb PL_LISTS_SIZE ; [12][16] zoznamy stvorcov pre figury
pl_counts:      resb PL_COUNTS_SIZE ; [12] pocty prvkov v zoznamoch
pl_pad:         resb (PL_STATE_SIZE - PL_LISTS_SIZE - PL_COUNTS_SIZE)
pl_verify_lists:  resb PL_LISTS_SIZE
pl_verify_counts: resb PL_COUNTS_SIZE
pl_verify_pad:    resb (PL_STATE_SIZE - PL_LISTS_SIZE - PL_COUNTS_SIZE)
pl_dbg_stage:     resb 1
search_timespec: resq 2
search_ply:     resq 1          ; vzdialenost od rootu (pre mat skore + kille)
killers:        resd 2*64       ; dva killer tahy na kazdy ply
history:        resd 2*64*64    ; [side][from][to] history heuristic
cap_history:    resd 6*64*6     ; [figura][to][obet] capture history heuristic
countermoves:   resw 64*64      ; [prev_from][prev_to] -> quiet tah, ktory refutoval
cont_history:   resd 64*64*64   ; [prev_to][from][to] 1-ply continuation history
cont_history2:  resd 64*64*64   ; [prev2_to][from][to] 2-ply continuation history
corr_history:   resd 2*1024     ; [side][hash&1023] eval correction (centipawns*64)
move_stack:     resw 64         ; tah odohrany na danom ply (0 = null ply)
eval_stack:     resd 64         ; static eval na kazdom ply (pre improving flag)
root_best_move: resd 1          ; best move z predchadzajucej ID iteracie
null_stack:     resb 64*16      ; ulozene stavy pre null-move (side/ep/hash/halfmove)
asp_alpha:      resd 1          ; aspiration window (root)
asp_beta:       resd 1
asp_delta:      resd 1
asp_use:        resd 1          ; 1 = pouzi asp window (nastavuje uci_go)
asp_retry:      resd 1          ; pocet aspiration re-search retry
asp_prev_depth: resd 1          ; hlbska z predch. iteracie (kontrola continuity ID)
root_alpha:     resd 1          ; aktualne alpha v root slucke
root_trace_count:  resd 1       ; diagnostika: pocet top root kandidatov (max 5)
root_trace_moves:  resw 5       ; diagnostika: root tahy (zoradene podla skore)
root_trace_scores: resd 5       ; diagnostika: root skore (zoradene zostupne)
root_diag_count:   resd 1       ; detailny root log: pocet zaznamov
root_diag_moves:   resw 256     ; tah
root_diag_scores:  resd 256     ; vratene score
root_diag_alpha:   resd 256     ; alpha okno final callu
root_diag_beta:    resd 256     ; beta okno final callu
root_diag_flag:    resb 256     ; 0=exact,1=fail-low,2=fail-high
root_diag_nodes:   resq 256     ; uzly na root tah
root_diag_pv0:     resw 256     ; prvy child PV tah
root_diag_a_tmp:   resd 1
root_diag_b_tmp:   resd 1
root_diag_nodes_start: resq 1
trace_white_enable:  resb 1     ; zapina cieleny trace White uzla po d4e5
trace_white_active:  resb 1     ; interny flag pre aktualny uzol
trace_root_target:   resb 1     ; 1 ak root aktualne prehladava d4e5 vetvu
trace_move_alpha:    resd 1
trace_move_beta:     resd 1
trace_char:          resb 1
smp_worker_mode: resd 1         ; 1 = volanie z helper procesu (rovno do single rezimu)
smp_child_pids:    resq 8

; --- Lightweight profilove countery (bench/report; inkrement = 1 instr) ---
prof_qnodes:    resq 1          ; uzly v quiescence
prof_evals:     resq 1          ; volania evaluate
prof_movegen:   resq 1          ; volania generate_all_moves
prof_makes:     resq 1          ; volania make_move
prof_unmakes:   resq 1          ; volania unmake_move
prof_allprune:  resq 1          ; all-prune fallbacky v negamax

%if ENABLE_SEE_AUDIT = 1
see_audit_calls:    resq 1
see_audit_repeats:  resq 1
see_audit_table:    resq 16384   ; open-addressing set klucov (move,position)
%endif

section .text

global make_move, unmake_move, quiescence, negamax, search_best_move, perft
global pl_rebuild_from_board
global pl_dirty
global pl_lists, pl_counts
global asp_alpha, asp_beta, asp_delta, asp_use, asp_retry
global root_trace_count, root_trace_moves, root_trace_scores
global root_diag_count, root_diag_moves, root_diag_scores, root_diag_alpha, root_diag_beta
global root_diag_flag, root_diag_nodes, root_diag_pv0
global trace_white_enable
global smp_worker_mode, smp_child_pids
global prof_qnodes, prof_evals, prof_movegen, prof_makes, prof_unmakes, prof_allprune

extern board, side, castle, enpassant, halfmove, fullmove
extern moved_piece, captured_piece
extern move_list, move_count
extern pv_moves, pv_moves_len, pv_table, pv_len, root_pv_table, root_pv_len
extern nodes_searched, search_last_score
extern search_limits, uci_stop_flag
extern apply_move, update_position_state
extern pos_bb_move_delta
extern generate_all_moves, is_in_check, evaluate
extern promo_pieces, moved_piece, captured_piece
extern see
extern compute_hash
extern hash_delta_pieces, hash_delta_state
extern nnue2_move_delta, nnue2_move_delta_inv, nnue_acc_hash
extern tt_probe, tt_store, position_hash
extern check_repetition
extern hash_history, hash_count
extern tb_piece_count, tb_probe_wdl, tb_path_len
extern uci_syzygy_probe_depth
extern search_poll_input
extern book_lookup_all, book_moves, book_moves_len, book_mode, book_search_depth, book_rating_flag
extern singular_excl
extern smp_check_stop, smp_signal_stop
extern write_cstr, print_number, msg_newline
extern uci_emit_fen, uci_print_move_token
extern uci_print_signed_number

; ============================================================
; search_eval_checked - dual-check evaluate (list-path vs board-path)
; Pri mismatch vypise diagnostiku a skonci exit(76).
; Vystup: eax = evaluate (normalna cesta, z pohladu bieleho)
; Poznamka: wrapper drzi vlastny frame a zachovava ABI discipline.
; ============================================================
search_eval_checked:
    sub rsp, 64

%if ENABLE_PL_INFRA = 1 && ENABLE_PL_INVARIANT = 1
    ; PRE-GUARD: pred evaluate over, ze aktualny list stav sedi s rebuildom
    ; (porovnanie iba aktivnych slotov podla count).
    cmp byte [pl_dirty], 0
    jne .evalchk_pre_done

    ; snapshot aktualneho list stavu (current) do verify bloku
    lea rsi, [pl_lists]
    lea rdi, [pl_verify_lists]
    mov ecx, PL_STATE_SIZE/8
    rep movsq

    ; rebuild expected z board[64]
    call pl_rebuild_from_board

    ; active-only compare current(snapshot) vs rebuild(expected)
    mov r11, rsp
    call .evalchk_compare_active
    cmp dword [rsp + 8], 1
    je .evalchk_pre_restore

    mov dword [rsp + 0], -1 ; pre-guard nema list/scan score
    mov dword [rsp + 4], -1
    mov dword [rsp + 24], 0 ; phase=0 (pre)
    jmp .evalchk_dump_abort

.evalchk_pre_restore:
    ; vrat current list stav zo snapshotu, aby search pokracoval bez zmeny
    lea rsi, [pl_verify_lists]
    lea rdi, [pl_lists]
    mov ecx, PL_STATE_SIZE/8
    rep movsq
    mov byte [pl_dirty], 0
.evalchk_pre_done:
%endif

    ; Primarny vysledok (normalna evaluate cesta)
    call evaluate
    mov dword [rsp + 0], eax

%if ENABLE_PL_INFRA = 1 && ENABLE_PL_INVARIANT = 1
    ; Porovnavaj len ked by evaluate isla list-path cestou
    cmp byte [pl_dirty], 0
    jne .evalchk_done

    ; Druhy beh cez board-path (dočasne pl_dirty=1)
    mov byte [pl_dirty], 1
    call evaluate
    mov dword [rsp + 4], eax
    mov byte [pl_dirty], 0

    mov eax, dword [rsp + 0]
    cmp eax, dword [rsp + 4]
    je .evalchk_done

    ; Snapshot aktualneho PL stavu pred rebuild compare (post-eval)
    lea rsi, [pl_lists]
    lea rdi, [pl_verify_lists]
    mov ecx, PL_STATE_SIZE/8
    rep movsq

    ; Očakávaný stav z board[64]
    call pl_rebuild_from_board

    mov r11, rsp
    call .evalchk_compare_active
    mov dword [rsp + 24], 1 ; phase=1 (post)
    jmp .evalchk_dump_abort

.evalchk_compare_active:
    ; Vstup: pl_verify_* = current snapshot, pl_* = rebuild expected
    ; Vystup lokalov:
    ; [rsp+8]=pl_equal, [rsp+12]=first_idx, [rsp+16]=cur, [rsp+20]=reb
    ; [rsp+28]=first_list, [rsp+32]=first_off
    ; [rsp+36]=list9_cur_count, [rsp+40]=list9_reb_count
    mov dword [r11 + 8], 1
    mov dword [r11 + 12], -1
    mov dword [r11 + 16], 0
    mov dword [r11 + 20], 0
    mov dword [r11 + 28], -1
    mov dword [r11 + 32], -1
    movzx eax, byte [pl_verify_counts + 9]
    mov dword [r11 + 36], eax
    movzx eax, byte [pl_counts + 9]
    mov dword [r11 + 40], eax

    xor ecx, ecx                ; list idx 0..11
.evalchk_ca_list_loop:
    cmp ecx, 12
    jge .evalchk_ca_done
    movzx r14d, byte [pl_verify_counts + rcx] ; cur count (snapshot)
    movzx r15d, byte [pl_counts + rcx]        ; reb count (board rebuild)

    ; count mismatch => okamzity mismatch
    cmp r14d, r15d
    je .evalchk_ca_members
    mov dword [r11 + 8], 0
    cmp dword [r11 + 12], -1
    jne .evalchk_ca_next_list
    mov dword [r11 + 28], ecx
    mov dword [r11 + 32], 0
    mov eax, ecx
    shl eax, 4
    mov dword [r11 + 12], eax
    mov dword [r11 + 16], r14d
    mov dword [r11 + 20], r15d
    jmp .evalchk_ca_next_list

.evalchk_ca_members:
    xor ebx, ebx                ; member idx v rebuild liste
.evalchk_ca_mem_loop:
    cmp ebx, r15d
    jge .evalchk_ca_next_list

    ; sq = rebuild[list][member]
    mov eax, ecx
    shl eax, 4
    add eax, ebx
    movzx esi, byte [pl_lists + rax]

    ; hladanie sq v snapshot/current liste
    xor edx, edx
.evalchk_ca_find_loop:
    cmp edx, r14d
    jl .evalchk_ca_find_cmp
    ; sq sa nenasiel => mismatch
    mov dword [r11 + 8], 0
    cmp dword [r11 + 12], -1
    jne .evalchk_ca_mem_next
    mov dword [r11 + 28], ecx
    mov dword [r11 + 32], ebx
    mov eax, ecx
    shl eax, 4
    add eax, ebx
    mov dword [r11 + 12], eax
    mov dword [r11 + 16], esi
    mov dword [r11 + 20], 255
    jmp .evalchk_ca_mem_next
.evalchk_ca_find_cmp:
    mov eax, ecx
    shl eax, 4
    add eax, edx
    movzx edi, byte [pl_verify_lists + rax]
    cmp edi, esi
    je .evalchk_ca_found
    inc edx
    jmp .evalchk_ca_find_loop

.evalchk_ca_found:
.evalchk_ca_mem_next:
    inc ebx
    jmp .evalchk_ca_mem_loop

.evalchk_ca_next_list:
    inc ecx
    jmp .evalchk_ca_list_loop

.evalchk_ca_done:
    ret

.evalchk_dump_abort:
    ; Header podla fazy + ply + list/scan
    cmp dword [rsp + 24], 0
    jne .evalchk_dump_post
    lea rdi, [evalchk_pre_hdr]
    jmp .evalchk_dump_hdr
.evalchk_dump_post:
    lea rdi, [evalchk_post_hdr]
.evalchk_dump_hdr:
    call write_cstr
    mov rax, [search_ply]
    call print_number
    lea rdi, [evalchk_list]
    call write_cstr
    movsxd rax, dword [rsp + 0]
    call uci_print_signed_number
    lea rdi, [evalchk_scan]
    call write_cstr
    movsxd rax, dword [rsp + 4]
    call uci_print_signed_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; FEN dump
    lea rdi, [evalchk_fen]
    call write_cstr
    call uci_emit_fen
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; list9 count explicitne (poziadavka)
    lea rdi, [evalchk_l9]
    call write_cstr
    mov eax, dword [rsp + 36]
    call print_number
    lea rdi, [evalchk_slash]
    call write_cstr
    mov eax, dword [rsp + 40]
    call print_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; counts dump: c0/r0 c1/r1 ... c11/r11
    lea rdi, [evalchk_counts]
    call write_cstr
    xor ecx, ecx
.evalchk_counts_loop:
    cmp ecx, 12
    jge .evalchk_counts_done
    lea rdi, [evalchk_i_prefix]
    call write_cstr
    mov eax, ecx
    call print_number
    lea rdi, [evalchk_eq]
    call write_cstr
    lea rdi, [evalchk_c_prefix]
    call write_cstr
    movzx eax, byte [pl_verify_counts + rcx]
    call print_number
    lea rdi, [evalchk_slash]
    call write_cstr
    lea rdi, [evalchk_r_prefix]
    call write_cstr
    movzx eax, byte [pl_counts + rcx]
    call print_number
    lea rdi, [evalchk_space]
    call write_cstr
    inc ecx
    jmp .evalchk_counts_loop
.evalchk_counts_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    ; list head dump: prvych 32 bajtov listov, side-by-side c/r
    lea rdi, [evalchk_lists]
    call write_cstr
    xor ecx, ecx
.evalchk_lists_loop:
    cmp ecx, 32
    jge .evalchk_lists_done
    lea rdi, [evalchk_i_prefix]
    call write_cstr
    mov eax, ecx
    call print_number
    lea rdi, [evalchk_eq]
    call write_cstr
    lea rdi, [evalchk_c_prefix]
    call write_cstr
    movzx eax, byte [pl_verify_lists + rcx]
    call print_number
    lea rdi, [evalchk_slash]
    call write_cstr
    lea rdi, [evalchk_r_prefix]
    call write_cstr
    movzx eax, byte [pl_lists + rcx]
    call print_number
    lea rdi, [evalchk_space]
    call write_cstr
    inc ecx
    jmp .evalchk_lists_loop
.evalchk_lists_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    lea rdi, [evalchk_cmp]
    call write_cstr
    mov eax, dword [rsp + 8]
    call print_number
    lea rdi, [evalchk_first_list]
    call write_cstr
    movsxd rax, dword [rsp + 28]
    call uci_print_signed_number
    lea rdi, [evalchk_first_off]
    call write_cstr
    movsxd rax, dword [rsp + 32]
    call uci_print_signed_number
    lea rdi, [evalchk_first_idx]
    call write_cstr
    movsxd rax, dword [rsp + 12]
    call uci_print_signed_number
    lea rdi, [evalchk_first_cur]
    call write_cstr
    mov eax, dword [rsp + 16]
    call print_number
    lea rdi, [evalchk_first_reb]
    call write_cstr
    mov eax, dword [rsp + 20]
    call print_number
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_newline
    mov rdx, 1
    syscall

    mov rax, SYS_EXIT
    mov rdi, 76
    syscall
%endif

.evalchk_done:
    mov eax, dword [rsp + 0]
    add rsp, 64
    ret

; ============================================================
; check_time - periodicka kontrola timeoutu pre UCI search
; Vystup: eax = 1 ak treba zastavit, inak 0
; Pozor: volajuce negamax/quiescence maju v rdi/rsi/rdx/rcx argumenty
; (ukladaju ich az po call), preto su tu okrem rbx ulozene aj tie.
; ============================================================
