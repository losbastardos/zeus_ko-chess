; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; main.asm - hlavny vstup a herna slucka
; ============================================================

%include "chess.inc"

%define BENCH_DEPTH 13         ; fixna hlbka benchu (na nezatazenom ~7-15 s, pri zatazeni do ~60 s)

DEFAULT REL

section .data

; akumulatory profiloveho rozpadu pre bench (sucet cez vsetky FEN)
bench_acc_qnodes:  dq 0
bench_acc_evals:   dq 0
bench_acc_movegen: dq 0
bench_acc_makes:   dq 0
bench_acc_unmakes: dq 0

menu_header:
    db 27,"[96m+---------------------+",27,"[0m",10
menu_header_len equ $ - menu_header

menu_header_mid_left:
    db 27,"[96m|",27,"[0m","      ",27,"[33m",0

menu_header_mid_right:
    db 27,"[0m","       ",27,"[96m|",27,"[0m",10,0

menu_header_bottom:
    db 27,"[96m+---------------------+",27,"[0m",10,10
menu_header_bottom_len equ $ - menu_header_bottom

menu_modes:
    db 27,"[96mSelect Game Mode:",27,"[0m",10
    db "  ",27,"[33m1",27,"[0m"," - 1 Player ",27,"[90m(vs Computer)",27,"[0m",10
    db "  ",27,"[33m2",27,"[0m"," - 2 Players ",27,"[90m(Local)",27,"[0m",10
    db "  ",27,"[33m3",27,"[0m"," - Puzzles ",27,"[90m(Tactical training)",27,"[0m",10
    db "  ",27,"[33m4",27,"[0m"," - Vision ",27,"[90m(Whole-board awareness)",27,"[0m",10
    db "  ",27,"[33m5",27,"[0m"," - Online ",27,"[90m(Play a person - live or over days)",27,"[0m",10,10
menu_modes_len equ $ - menu_modes

menu_modes_sk:
    db 27,"[96mVyber Rezim Hry:",27,"[0m",10
    db "  ",27,"[33m1",27,"[0m"," - 1 Hrac ",27,"[90m(vs Pocitac)",27,"[0m",10
    db "  ",27,"[33m2",27,"[0m"," - 2 Hraci ",27,"[90m(Lokalne)",27,"[0m",10
    db "  ",27,"[33m3",27,"[0m"," - Puzzle ",27,"[90m(Takticky trening)",27,"[0m",10
    db "  ",27,"[33m4",27,"[0m"," - Vizia ",27,"[90m(Cela sachovnica)",27,"[0m",10
    db "  ",27,"[33m5",27,"[0m"," - Online ",27,"[90m(Hra proti cloveku)",27,"[0m",10,10
menu_modes_sk_len equ $ - menu_modes_sk

menu_prompt:
    db 27,"[90mEnter choice (1-5): ",27,"[0m"
menu_prompt_len equ $ - menu_prompt

menu_prompt_sk:
    db 27,"[90mZadaj volbu (1-5): ",27,"[0m"
menu_prompt_sk_len equ $ - menu_prompt_sk

menu_invalid:
    db 27,"[31mNeplatna volba. Zadaj 1-5.",27,"[0m",10
menu_invalid_len equ $ - menu_invalid

menu_invalid_en:
    db 27,"[31mInvalid choice. Enter 1-5.",27,"[0m",10
menu_invalid_en_len equ $ - menu_invalid_en

menu_unavailable:
    db 27,"[31mTento rezim zatial nie je dostupny. Skus 1 alebo 2.",27,"[0m",10
menu_unavailable_len equ $ - menu_unavailable

menu_unavailable_en:
    db 27,"[31mThis mode is not available yet. Try 1 or 2.",27,"[0m",10
menu_unavailable_en_len equ $ - menu_unavailable_en

menu_nl:
    db 10

; argument cmdline pre priamy UCI rezim (./chess --uci)
uci_arg_str:
    db "--uci", 0

strength_title:
    db 27,"[96mSelect Computer Strength:",27,"[0m",10
    db "  ",27,"[33m1",27,"[0m"," - Beginner ",27,"[90m(ELO 800)",27,"[0m",10
    db "  ",27,"[33m2",27,"[0m"," - Easy ",27,"[90m(ELO 1200)",27,"[0m",10
    db "  ",27,"[33m3",27,"[0m"," - Medium ",27,"[90m(ELO 1500)",27,"[0m",10
    db "  ",27,"[33m4",27,"[0m"," - Hard ",27,"[90m(ELO 1800)",27,"[0m",10
    db "  ",27,"[33m5",27,"[0m"," - Expert ",27,"[90m(ELO 2200)",27,"[0m",10
    db "  ",27,"[33m6",27,"[0m"," - Master ",27,"[90m(ELO 2600)",27,"[0m",10
strength_title_len equ $ - strength_title

strength_prompt:
    db 27,"[90mEnter choice (1-6) or ELO number: ",27,"[0m"
strength_prompt_len equ $ - strength_prompt

strength_title_sk:
    db 27,"[96mVyber Silu Pocitaca:",27,"[0m",10
    db "  ",27,"[33m1",27,"[0m"," - Zaciatocnik ",27,"[90m(ELO 800)",27,"[0m",10
    db "  ",27,"[33m2",27,"[0m"," - Lahky ",27,"[90m(ELO 1200)",27,"[0m",10
    db "  ",27,"[33m3",27,"[0m"," - Stredny ",27,"[90m(ELO 1500)",27,"[0m",10
    db "  ",27,"[33m4",27,"[0m"," - Tazky ",27,"[90m(ELO 1800)",27,"[0m",10
    db "  ",27,"[33m5",27,"[0m"," - Expert ",27,"[90m(ELO 2200)",27,"[0m",10
    db "  ",27,"[33m6",27,"[0m"," - Master ",27,"[90m(ELO 2600)",27,"[0m",10
strength_title_sk_len equ $ - strength_title_sk

strength_prompt_sk:
    db 27,"[90mZadaj volbu (1-6) alebo ELO cislo: ",27,"[0m"
strength_prompt_sk_len equ $ - strength_prompt_sk

color_title:
    db 27,"[96mSelect Your Color:",27,"[0m",10
    db "  ",27,"[33m1",27,"[0m"," - White ",27,"[90m(Move first)",27,"[0m",10
    db "  ",27,"[33m2",27,"[0m"," - Black ",27,"[90m(Move second)",27,"[0m",10
    db "  ",27,"[33m[Enter]",27,"[0m"," - Random ",27,"[90m(Let fate decide)",27,"[0m",10
color_title_len equ $ - color_title

color_prompt:
    db 27,"[90mEnter choice or press Enter: ",27,"[0m"
color_prompt_len equ $ - color_prompt

color_title_sk:
    db 27,"[96mVyber Svoju Farbu:",27,"[0m",10
    db "  ",27,"[33m1",27,"[0m"," - Biela ",27,"[90m(Hras prvy)",27,"[0m",10
    db "  ",27,"[33m2",27,"[0m"," - Cierna ",27,"[90m(Hras druhy)",27,"[0m",10
    db "  ",27,"[33m[Enter]",27,"[0m"," - Nahodne ",27,"[90m(Nech rozhodne osud)",27,"[0m",10
color_title_sk_len equ $ - color_title_sk

color_prompt_sk:
    db 27,"[90mZadaj volbu alebo stlac Enter: ",27,"[0m"
color_prompt_sk_len equ $ - color_prompt_sk

menu_invalid_1_6:
    db 27,"[31mNeplatna volba. Zadaj 1-6 alebo ELO cislo.",27,"[0m",10
menu_invalid_1_6_len equ $ - menu_invalid_1_6

menu_invalid_1_6_en:
    db 27,"[31mInvalid choice. Enter 1-6 or ELO number.",27,"[0m",10
menu_invalid_1_6_en_len equ $ - menu_invalid_1_6_en

tbtest_prefix:      db "TBTEST pieces=", 0
tbtest_wdl_prefix:  db "TBTEST wdl=", 0
tbtest_dtz_prefix:  db "TBTEST dtz=", 0
tbtest_map_prefix:  db "TBTEST map_bytes=", 0
tbtest_path_prefix: db "TBTEST path=", 0
tbtest_wdl_payload_prefix: db "TBTEST wdl_payload_byte=", 0
tbtest_dtz_payload_prefix: db "TBTEST dtz_payload_byte=", 0
tbtest_wdl_off_prefix: db "TBTEST wdl_payload_off=", 0
tbtest_dtz_off_prefix: db "TBTEST dtz_payload_off=", 0
tbtest_wdl_flags_prefix: db "TBTEST wdl_flags=", 0
tbtest_dtz_flags_prefix: db "TBTEST dtz_flags=", 0
tbtest_wdl_hdr_off_prefix: db "TBTEST wdl_pairs_hdr_off=", 0
tbtest_dtz_hdr_off_prefix: db "TBTEST dtz_pairs_hdr_off=", 0
tbtest_wdl_blocks_prefix: db "TBTEST wdl_pairs_blocks=", 0
tbtest_dtz_blocks_prefix: db "TBTEST dtz_pairs_blocks=", 0
tbtest_wdl_syms_prefix: db "TBTEST wdl_pairs_syms=", 0
tbtest_dtz_syms_prefix: db "TBTEST dtz_pairs_syms=", 0
tbtest_wdl_blocksize_prefix: db "TBTEST wdl_pairs_blocksize=", 0
tbtest_dtz_blocksize_prefix: db "TBTEST dtz_pairs_blocksize=", 0
tbtest_wdl_idxbits_prefix: db "TBTEST wdl_pairs_idxbits=", 0
tbtest_dtz_idxbits_prefix: db "TBTEST dtz_pairs_idxbits=", 0
tbtest_wdl_const_prefix: db "TBTEST wdl_pairs_const=", 0
tbtest_dtz_const_prefix: db "TBTEST dtz_pairs_const=", 0
bbtest_prefix:      db "BBTEST mismatches=", 0
bbtest_magics_prefix: db "BBTEST magics_mismatches=", 0
bbtest_total_prefix:  db "BBTEST total_mismatches=", 0

section .text
global _start

extern init_board, print_title, print_board, print_prompt, print_newline
extern pos_magics_init
extern read_move, print_move_list
extern generate_all_moves, parse_user_move, find_move, apply_move
extern update_position_state
extern toggle_board_view
extern is_in_check
extern search_best_move, print_move
extern compute_hash, perft, print_number
extern init_hash_history, record_hash, check_repetition
extern load_config, config_get, parse_int, book_load_all, book_lookup
extern load_lang_pack, lang_get
extern uci_loop
extern clear_history, record_move, book_lookup_all, print_status
extern pgn_san_begin, pgn_write_move, pgn_new_game, pgn_quit, pgn_result
extern bench_fens, bench_fens_count
extern bench_str_header, bench_str_fens_mid, bench_str_nodes, bench_str_time, bench_str_nps
extern prof_qnodes, prof_evals, prof_movegen, prof_makes, prof_unmakes
extern bench_str_p_qnodes, bench_str_p_main, bench_str_p_evals, bench_str_p_movegen
extern bench_str_p_makes, bench_str_p_unmakes
extern bench_str_bench_line, bench_str_time_ms, bench_str_nps_eq, bench_str_depth_eq
extern bench_str_pct, bench_str_pct_end
extern book_rating_flag
extern config_filename, key_book, default_book, key_eco, default_eco, key_search_depth, default_search_depth, key_debug, default_debug
extern key_language, default_language, key_syzygy, default_syzygy, key_book_mode, default_book_mode, key_book_search_depth, default_book_search_depth, key_eval_mode, default_eval_mode, key_nnue_file, default_nnue_file, key_threads, default_threads
extern eco_load, eco_test_print
extern lang_file_en, lang_file_sk
extern lkey_menu_title, ldef_menu_title
extern lkey_menu_select, ldef_menu_select
extern lkey_menu_mode_1, ldef_menu_mode_1
extern lkey_menu_mode_2, ldef_menu_mode_2
extern lkey_menu_mode_3, ldef_menu_mode_3
extern lkey_menu_mode_4, ldef_menu_mode_4
extern lkey_menu_mode_5, ldef_menu_mode_5
extern lkey_menu_prompt, ldef_menu_prompt
extern lkey_menu_invalid_1_5, ldef_menu_invalid_1_5
extern lkey_menu_unavailable, ldef_menu_unavailable
extern lkey_strength_title, ldef_strength_title
extern lkey_strength_opt_1, ldef_strength_opt_1
extern lkey_strength_opt_2, ldef_strength_opt_2
extern lkey_strength_opt_3, ldef_strength_opt_3
extern lkey_strength_opt_4, ldef_strength_opt_4
extern lkey_strength_opt_5, ldef_strength_opt_5
extern lkey_strength_opt_6, ldef_strength_opt_6
extern lkey_strength_prompt, ldef_strength_prompt
extern lkey_strength_invalid, ldef_strength_invalid
extern lkey_color_title, ldef_color_title
extern lkey_color_opt_white, ldef_color_opt_white
extern lkey_color_opt_black, ldef_color_opt_black
extern lkey_color_opt_random, ldef_color_opt_random
extern lkey_color_prompt, ldef_color_prompt
extern lkey_prompt_move, ldef_prompt_move
extern lkey_prompt_invalid_input, ldef_prompt_invalid_input
extern lkey_status_white, ldef_status_white
extern lkey_status_black, ldef_status_black
extern lkey_mode_engine_white, ldef_mode_engine_white
extern lkey_mode_engine_black, ldef_mode_engine_black
extern lkey_mode_both, ldef_mode_both
extern lkey_mode_none, ldef_mode_none
extern lkey_panel_white_took, ldef_panel_white_took
extern lkey_panel_black_took, ldef_panel_black_took
extern lkey_panel_moves, ldef_panel_moves
extern lkey_panel_book, ldef_panel_book
extern lkey_panel_pv, ldef_panel_pv
extern lkey_panel_help_move, ldef_panel_help_move
extern lkey_panel_help_flip, ldef_panel_help_flip
extern lkey_panel_help_help, ldef_panel_help_help
extern lkey_panel_help_summary, ldef_panel_help_summary
extern lang_txt_menu_title, lang_txt_menu_select, lang_txt_menu_mode_1, lang_txt_menu_mode_2, lang_txt_menu_mode_3, lang_txt_menu_mode_4, lang_txt_menu_mode_5
extern lang_txt_menu_prompt, lang_txt_menu_invalid_1_5, lang_txt_menu_unavailable
extern lang_txt_strength_title, lang_txt_strength_opt_1, lang_txt_strength_opt_2, lang_txt_strength_opt_3
extern lang_txt_strength_opt_4, lang_txt_strength_opt_5, lang_txt_strength_opt_6
extern lang_txt_strength_prompt, lang_txt_strength_invalid
extern lang_txt_color_title, lang_txt_color_opt_white, lang_txt_color_opt_black, lang_txt_color_opt_random, lang_txt_color_prompt
extern lang_txt_prompt_move, lang_txt_prompt_invalid_input
extern lang_txt_status_white, lang_txt_status_black
extern lang_txt_mode_engine_white, lang_txt_mode_engine_black, lang_txt_mode_both, lang_txt_mode_none
extern lang_txt_panel_white_took, lang_txt_panel_black_took, lang_txt_panel_moves, lang_txt_panel_book, lang_txt_panel_pv
extern lang_txt_panel_help_move, lang_txt_panel_help_flip, lang_txt_panel_help_help, lang_txt_panel_help_summary
extern search_depth, debug, book_mode, book_search_depth, eval_mode
extern gfx_init, gfx_run
extern sdl_gfx_init, sdl_gfx_run
extern msg_engine, msg_engine_len
extern msg_error_illegal, msg_error_illegal_len
extern msg_checkmate, msg_checkmate_len
extern msg_stalemate, msg_stalemate_len
extern msg_draw_50, msg_draw_50_len
extern msg_draw_rep, msg_draw_rep_len
extern msg_new_game, msg_new_game_len
extern msg_view_white, msg_view_white_len
extern write_cstr
extern uci_id_name, uci_id_author, uci_ok
extern uci_opt_hash, uci_opt_ownbook, uci_opt_ponder, uci_opt_syzygy, uci_opt_syzygy_depth, uci_opt_overhead, uci_opt_evalmode, uci_opt_threads
extern msg_view_black, msg_view_black_len
extern move_buf, move_buf_len, move_count, side, board_flip, perft_depth, halfmove, engine_side, uci_requested
extern gfx_active_backend
extern lang_is_en
extern uci_own_book, uci_stop_flag, uci_ponder, uci_hash_size, uci_move_overhead, uci_syzygy_probe_depth, uci_threads
extern tt_init, pst_init, book_pick_move, nnue_load, nnue2_load, nnue2_refresh, nnue2_ready
extern parse_fen_string, uci_now_ms
extern nodes_searched
extern suite_cmd_text, suite_snapshot_save, suite_snapshot_restore
extern tb_init, tb_probe_wdl, tb_probe_dtz, tb_piece_count, tb_map_size, tb_file_path
extern pos_validate
extern pos_magics_validate
extern tb_wdl_payload_probe_byte, tb_dtz_payload_probe_byte
extern tb_wdl_payload_probe_off, tb_dtz_payload_probe_off
extern tb_wdl_header_flags, tb_dtz_header_flags
extern tb_wdl_pairs_header_off, tb_dtz_pairs_header_off
extern tb_wdl_pairs_num_blocks, tb_dtz_pairs_num_blocks
extern tb_wdl_pairs_num_syms, tb_dtz_pairs_num_syms
extern tb_wdl_pairs_blocksize, tb_dtz_pairs_blocksize
extern tb_wdl_pairs_idxbits, tb_dtz_pairs_idxbits
extern tb_wdl_pairs_is_const, tb_dtz_pairs_is_const

%define SYS_GETPID 39

; ============================================================
; menu_read_line - nacita kratky riadok do move_buf
; Vystup: [move_buf_len]
; ============================================================
menu_read_line:
    push rax
    push rbx
    push r12

    xor r12, r12
.read_loop:
    mov rax, SYS_READ
    mov rdi, STDIN
    lea rsi, [move_buf + r12]
    mov rdx, 1
    syscall
    cmp rax, 1
    je .have_char
    ; EOF/chyba na zaciatku riadku (r12==0): stdin je zatvoreny - ciste ukonci
    ; proces (inak by menu na EOF slucke spalovalo CPU donekonecna)
    test r12, r12
    jnz .done
    call pgn_quit
    mov rax, SYS_EXIT
    xor edi, edi
    syscall
.have_char:
    movzx rbx, byte [move_buf + r12]
    cmp rbx, 10
    je .done
    inc r12
    cmp r12, 31
    jl .read_loop

.consume:
    mov rax, SYS_READ
    mov rdi, STDIN
    lea rsi, [move_buf + 31]
    mov rdx, 1
    syscall
    cmp rax, 1
    jne .done
    movzx rbx, byte [move_buf + 31]
    cmp rbx, 10
    jne .consume

.done:
    mov [move_buf_len], r12
    mov byte [move_buf + r12], 0

    pop r12
    pop rbx
    pop rax
    ret

; ============================================================
; menu_parse_uint - parse decimal from move_buf
; Vystup: rax=value, rdx=1 valid / 0 invalid
; ============================================================
menu_parse_uint:
    push rbx
    push rcx

    xor rax, rax
    xor rdx, rdx
    xor rcx, rcx
    mov rbx, [move_buf_len]
    test rbx, rbx
    jz .out

.loop:
    cmp rcx, rbx
    jge .ok
    movzx rdx, byte [move_buf + rcx]
    sub rdx, '0'
    cmp rdx, 9
    ja .bad
    imul rax, 10
    add rax, rdx
    inc rcx
    jmp .loop

.ok:
    mov rdx, 1
    jmp .out

.bad:
    xor rax, rax
    xor rdx, rdx

.out:
    pop rcx
    pop rbx
    ret

; ============================================================
; copy_cstr_limit - skopiruje C-string do ciela s limitom
; Vstup: rdi=dst, rsi=src, rcx=max bytes
; ============================================================
copy_cstr_limit:
    push rax
    push rbx
    test rcx, rcx
    jz .done
    dec rcx
    xor rbx, rbx
.loop:
    cmp rbx, rcx
    jae .term
    mov al, [rsi + rbx]
    mov [rdi + rbx], al
    test al, al
    jz .done
    inc rbx
    jmp .loop
.term:
    mov byte [rdi + rbx], 0
.done:
    pop rbx
    pop rax
    ret

; ============================================================
; load_text_key - nacita text pre key (fallback default) do buffera
; Vstup: rdi=key, rsi=default, rdx=dst, rcx=max
; ============================================================
load_text_key:
    push r8
    push r9
    mov r8, rdx
    mov r9, rcx
    call lang_get
    mov rdi, r8
    mov rsi, rax
    mov rcx, r9
    call copy_cstr_limit
    pop r9
    pop r8
    ret

; ============================================================
; print_cstr_line - vypise C-string a newline
; Vstup: rdi=string
; ============================================================
print_cstr_line:
    push rdi
    call write_cstr
    call print_newline
    pop rdi
    ret

; ============================================================
; load_language_texts - nacita jazykovy pack + textovy slovnik
; ============================================================
load_language_texts:
    push rax
    push rbx

    cmp byte [lang_is_en], 0
    je .load_sk
    lea rdi, [lang_file_en]
    jmp .load_pack
.load_sk:
    lea rdi, [lang_file_sk]
.load_pack:
    call load_lang_pack

    lea rdi, [lkey_menu_title]
    lea rsi, [ldef_menu_title]
    lea rdx, [lang_txt_menu_title]
    mov rcx, 64
    call load_text_key

    lea rdi, [lkey_menu_select]
    lea rsi, [ldef_menu_select]
    lea rdx, [lang_txt_menu_select]
    mov rcx, 128
    call load_text_key

    lea rdi, [lkey_menu_mode_1]
    lea rsi, [ldef_menu_mode_1]
    lea rdx, [lang_txt_menu_mode_1]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_menu_mode_2]
    lea rsi, [ldef_menu_mode_2]
    lea rdx, [lang_txt_menu_mode_2]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_menu_mode_3]
    lea rsi, [ldef_menu_mode_3]
    lea rdx, [lang_txt_menu_mode_3]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_menu_mode_4]
    lea rsi, [ldef_menu_mode_4]
    lea rdx, [lang_txt_menu_mode_4]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_menu_mode_5]
    lea rsi, [ldef_menu_mode_5]
    lea rdx, [lang_txt_menu_mode_5]
    mov rcx, 128
    call load_text_key

    lea rdi, [lkey_menu_prompt]
    lea rsi, [ldef_menu_prompt]
    lea rdx, [lang_txt_menu_prompt]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_menu_invalid_1_5]
    lea rsi, [ldef_menu_invalid_1_5]
    lea rdx, [lang_txt_menu_invalid_1_5]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_menu_unavailable]
    lea rsi, [ldef_menu_unavailable]
    lea rdx, [lang_txt_menu_unavailable]
    mov rcx, 128
    call load_text_key

    lea rdi, [lkey_strength_title]
    lea rsi, [ldef_strength_title]
    lea rdx, [lang_txt_strength_title]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_strength_opt_1]
    lea rsi, [ldef_strength_opt_1]
    lea rdx, [lang_txt_strength_opt_1]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_strength_opt_2]
    lea rsi, [ldef_strength_opt_2]
    lea rdx, [lang_txt_strength_opt_2]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_strength_opt_3]
    lea rsi, [ldef_strength_opt_3]
    lea rdx, [lang_txt_strength_opt_3]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_strength_opt_4]
    lea rsi, [ldef_strength_opt_4]
    lea rdx, [lang_txt_strength_opt_4]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_strength_opt_5]
    lea rsi, [ldef_strength_opt_5]
    lea rdx, [lang_txt_strength_opt_5]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_strength_opt_6]
    lea rsi, [ldef_strength_opt_6]
    lea rdx, [lang_txt_strength_opt_6]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_strength_prompt]
    lea rsi, [ldef_strength_prompt]
    lea rdx, [lang_txt_strength_prompt]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_strength_invalid]
    lea rsi, [ldef_strength_invalid]
    lea rdx, [lang_txt_strength_invalid]
    mov rcx, 128
    call load_text_key

    lea rdi, [lkey_color_title]
    lea rsi, [ldef_color_title]
    lea rdx, [lang_txt_color_title]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_color_opt_white]
    lea rsi, [ldef_color_opt_white]
    lea rdx, [lang_txt_color_opt_white]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_color_opt_black]
    lea rsi, [ldef_color_opt_black]
    lea rdx, [lang_txt_color_opt_black]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_color_opt_random]
    lea rsi, [ldef_color_opt_random]
    lea rdx, [lang_txt_color_opt_random]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_color_prompt]
    lea rsi, [ldef_color_prompt]
    lea rdx, [lang_txt_color_prompt]
    mov rcx, 128
    call load_text_key

    lea rdi, [lkey_prompt_move]
    lea rsi, [ldef_prompt_move]
    lea rdx, [lang_txt_prompt_move]
    mov rcx, 192
    call load_text_key
    lea rdi, [lkey_prompt_invalid_input]
    lea rsi, [ldef_prompt_invalid_input]
    lea rdx, [lang_txt_prompt_invalid_input]
    mov rcx, 192
    call load_text_key

    lea rdi, [lkey_status_white]
    lea rsi, [ldef_status_white]
    lea rdx, [lang_txt_status_white]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_status_black]
    lea rsi, [ldef_status_black]
    lea rdx, [lang_txt_status_black]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_mode_engine_white]
    lea rsi, [ldef_mode_engine_white]
    lea rdx, [lang_txt_mode_engine_white]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_mode_engine_black]
    lea rsi, [ldef_mode_engine_black]
    lea rdx, [lang_txt_mode_engine_black]
    mov rcx, 128
    call load_text_key
    lea rdi, [lkey_mode_both]
    lea rsi, [ldef_mode_both]
    lea rdx, [lang_txt_mode_both]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_mode_none]
    lea rsi, [ldef_mode_none]
    lea rdx, [lang_txt_mode_none]
    mov rcx, 96
    call load_text_key

    lea rdi, [lkey_panel_white_took]
    lea rsi, [ldef_panel_white_took]
    lea rdx, [lang_txt_panel_white_took]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_panel_black_took]
    lea rsi, [ldef_panel_black_took]
    lea rdx, [lang_txt_panel_black_took]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_panel_moves]
    lea rsi, [ldef_panel_moves]
    lea rdx, [lang_txt_panel_moves]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_panel_book]
    lea rsi, [ldef_panel_book]
    lea rdx, [lang_txt_panel_book]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_panel_pv]
    lea rsi, [ldef_panel_pv]
    lea rdx, [lang_txt_panel_pv]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_panel_help_move]
    lea rsi, [ldef_panel_help_move]
    lea rdx, [lang_txt_panel_help_move]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_panel_help_flip]
    lea rsi, [ldef_panel_help_flip]
    lea rdx, [lang_txt_panel_help_flip]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_panel_help_help]
    lea rsi, [ldef_panel_help_help]
    lea rdx, [lang_txt_panel_help_help]
    mov rcx, 96
    call load_text_key
    lea rdi, [lkey_panel_help_summary]
    lea rsi, [ldef_panel_help_summary]
    lea rdx, [lang_txt_panel_help_summary]
    mov rcx, 96
    call load_text_key

    pop rbx
    pop rax
    ret

; ============================================================
; configure_vs_engine - strength + color submenu
; ============================================================
configure_vs_engine:
    push rax
    push rbx
    push rcx
    push rdx

.strength_loop:
    lea rdi, [lang_txt_strength_title]
    call print_cstr_line
    lea rdi, [lang_txt_strength_opt_1]
    call print_cstr_line
    lea rdi, [lang_txt_strength_opt_2]
    call print_cstr_line
    lea rdi, [lang_txt_strength_opt_3]
    call print_cstr_line
    lea rdi, [lang_txt_strength_opt_4]
    call print_cstr_line
    lea rdi, [lang_txt_strength_opt_5]
    call print_cstr_line
    lea rdi, [lang_txt_strength_opt_6]
    call print_cstr_line
    lea rdi, [lang_txt_strength_prompt]
    call write_cstr

    call menu_read_line
    mov rax, [move_buf_len]
    test rax, rax
    jz .strength_default

    cmp rax, 1
    jne .strength_elo
    movzx eax, byte [move_buf]
    sub eax, '0'
    cmp eax, 1
    jl .strength_bad
    cmp eax, 6
    jg .strength_bad
    mov [search_depth], al
    jmp .color_menu

.strength_elo:
    call menu_parse_uint
    test rdx, rdx
    jz .strength_bad
    cmp rax, 1000
    jl .d1
    cmp rax, 1400
    jl .d2
    cmp rax, 1700
    jl .d3
    cmp rax, 2000
    jl .d4
    cmp rax, 2400
    jl .d5
    mov byte [search_depth], 6
    jmp .color_menu
.d1:
    mov byte [search_depth], 1
    jmp .color_menu
.d2:
    mov byte [search_depth], 2
    jmp .color_menu
.d3:
    mov byte [search_depth], 3
    jmp .color_menu
.d4:
    mov byte [search_depth], 4
    jmp .color_menu
.d5:
    mov byte [search_depth], 5
    jmp .color_menu

.strength_default:
    mov byte [search_depth], 1
    jmp .color_menu

.strength_bad:
    lea rdi, [lang_txt_strength_invalid]
    call print_cstr_line
    jmp .strength_loop

.color_menu:
    lea rdi, [lang_txt_color_title]
    call print_cstr_line
    lea rdi, [lang_txt_color_opt_white]
    call print_cstr_line
    lea rdi, [lang_txt_color_opt_black]
    call print_cstr_line
    lea rdi, [lang_txt_color_opt_random]
    call print_cstr_line
    lea rdi, [lang_txt_color_prompt]
    call write_cstr

    call menu_read_line
    mov rax, [move_buf_len]
    test rax, rax
    jz .color_random
    cmp rax, 1
    jne .color_bad

    movzx eax, byte [move_buf]
    cmp al, '1'
    je .color_white
    cmp al, '2'
    je .color_black
    jmp .color_bad

.color_white:
    mov byte [engine_side], 1
    mov byte [board_flip], 0
    jmp .done

.color_black:
    mov byte [engine_side], 0
    mov byte [board_flip], 1
    jmp .done

.color_random:
    mov rax, SYS_GETPID
    syscall
    test al, 1
    jz .color_white
    jmp .color_black

.color_bad:
    lea rdi, [lang_txt_menu_invalid_1_5]
    call print_cstr_line
    jmp .color_menu

.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================
; select_game_mode - uvodne menu a vyber rezimu
; Vystup: [engine_side] = 1 (vs engine) alebo 3 (2 players)
; ============================================================
select_game_mode:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

.menu_loop:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, menu_header
    mov rdx, menu_header_len
    syscall

    lea rdi, [menu_header_mid_left]
    call write_cstr
    lea rdi, [lang_txt_menu_title]
    call write_cstr
    lea rdi, [menu_header_mid_right]
    call write_cstr

    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, menu_header_bottom
    mov rdx, menu_header_bottom_len
    syscall

    lea rdi, [lang_txt_menu_select]
    call print_cstr_line
    lea rdi, [lang_txt_menu_mode_1]
    call print_cstr_line
    lea rdi, [lang_txt_menu_mode_2]
    call print_cstr_line
    lea rdi, [lang_txt_menu_mode_3]
    call print_cstr_line
    lea rdi, [lang_txt_menu_mode_4]
    call print_cstr_line
    lea rdi, [lang_txt_menu_mode_5]
    call print_cstr_line
    call print_newline
    lea rdi, [lang_txt_menu_prompt]
    call write_cstr
    call menu_read_line
    cmp qword [move_buf_len], 0
    je .default_mode

.process:
    ; "uci" na vstupe = priamy prechod do UCI rezimu (GUI protokol)
    ; akceptuj aj CRLF variantu "uci\r"
    mov rax, [move_buf_len]
    cmp rax, 3
    je .uci_check
    cmp rax, 4
    jne .process_modes
    cmp byte [move_buf+3], 13
    jne .process_modes
.uci_check:
    cmp byte [move_buf], 'u'
    jne .process_modes
    cmp byte [move_buf+1], 'c'
    jne .process_modes
    cmp byte [move_buf+2], 'i'
    jne .process_modes
    mov byte [uci_requested], 1
    jmp .done

.process_modes:
    movzx eax, byte [move_buf]
    cmp al, '1'
    je .mode_vs_engine
    cmp al, '2'
    je .mode_two_players
    cmp al, '3'
    je .mode_unavailable
    cmp al, '4'
    je .mode_unavailable
    cmp al, '5'
    je .mode_unavailable

    lea rdi, [lang_txt_menu_invalid_1_5]
    call print_cstr_line
    jmp .menu_loop

.mode_unavailable:
    lea rdi, [lang_txt_menu_unavailable]
    call print_cstr_line
    jmp .menu_loop

.mode_vs_engine:
    mov byte [engine_side], 1
    call configure_vs_engine
    jmp .done

.mode_two_players:
    mov byte [engine_side], 3
    jmp .done

.default_mode:
    mov byte [engine_side], 1

.done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, menu_nl
    mov rdx, 1
    syscall

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================
; Hlavny vstup programu
; ============================================================
_start:
    ; argv: ak argv[1] == "--uci", nastav uci_requested este pred inicializaciou
    ; ([rsp]=argc, [rsp+16]=argv[1]; RSP je tu 16B zarovnany, bez callov)
    cmp qword [rsp], 2
    jl .no_uci_arg
    mov rsi, [rsp+16]
    lea rdi, [uci_arg_str]
    xor rcx, rcx
.uci_arg_cmp:
    mov al, [rdi+rcx]
    cmp al, [rsi+rcx]
    jne .no_uci_arg
    test al, al
    jz .uci_arg_hit
    inc rcx
    jmp .uci_arg_cmp
.uci_arg_hit:
    mov byte [uci_requested], 1
.no_uci_arg:
    call init_board
    call pos_magics_init           ; E10/F1: naplnenie magic_attacks (raz)
    call init_hash_history
    call record_hash
    call clear_history
    mov byte [engine_side], 1
    mov byte [uci_own_book], 1
    mov byte [uci_ponder], 0
    mov byte [uci_stop_flag], 0
    mov dword [uci_hash_size], 64
    mov dword [uci_move_overhead], 100
    mov dword [uci_syzygy_probe_depth], 1
    mov dword [uci_threads], 1
    mov rdi, 64
    call tt_init
    call pst_init

    ; nacitaj konfiguraciu
    lea rdi, [config_filename]
    call load_config

    ; nacitaj opening book
    lea rdi, [key_book]
    lea rsi, [default_book]
    call config_get
    mov rdi, rax
    call book_load_all

    ; nacitaj opening kniznicu ECO kodov (eco.bin; chyba = tiche vypnutie)
    lea rdi, [key_eco]
    lea rsi, [default_eco]
    call config_get
    mov rdi, rax
    call eco_load

    ; language: en/sk
    lea rdi, [key_language]
    lea rsi, [default_language]
    call config_get
    mov byte [lang_is_en], 0
    cmp byte [rax], 'e'
    jne .lang_done
    cmp byte [rax+1], 'n'
    jne .lang_done
    mov byte [lang_is_en], 1
.lang_done:
    call load_language_texts

    ; Syzygy TB cesta (volitelne; prazdny string = bez TB)
    lea rdi, [key_syzygy]
    lea rsi, [default_syzygy]
    call config_get
    mov rdi, rax
    call tb_init

    ; nacitaj search depth
    lea rdi, [key_search_depth]
    lea rsi, [default_search_depth]
    call config_get
    mov rsi, rax
    call parse_int
    test rax, rax
    jg .depth_ok
    mov rax, 3
.depth_ok:
    cmp rax, 6
    jle .depth_store
    mov rax, 6
.depth_store:
    mov [search_depth], al

    ; nacitaj debug prepinac
    lea rdi, [key_debug]
    lea rsi, [default_debug]
    call config_get
    mov rsi, rax
    call parse_int
    test rax, rax
    setnz byte [debug]

    ; nacitaj book_mode (0 = instant, 1 = vyber knizneho tahu searchom)
    lea rdi, [key_book_mode]
    lea rsi, [default_book_mode]
    call config_get
    mov rsi, rax
    call parse_int
    test rax, rax
    setnz byte [book_mode]

    ; nacitaj book_search_depth (1..8)
    lea rdi, [key_book_search_depth]
    lea rsi, [default_book_search_depth]
    call config_get
    mov rsi, rax
    call parse_int
    test rax, rax
    jg .bsd_ok
    mov rax, 4
.bsd_ok:
    cmp rax, 8
    jle .bsd_store
    mov rax, 8
.bsd_store:
    mov [book_search_depth], al

    ; eval_mode (0 classic, 1 linear NNUE, 2 NNUE 1-skryta-vrstva)
    lea rdi, [key_eval_mode]
    lea rsi, [default_eval_mode]
    call config_get
    mov rsi, rax
    call parse_int
    cmp rax, 2
    jle .em_ok
    mov rax, 2
.em_ok:
    test rax, rax
    jns .em_nonneg
    xor rax, rax
.em_nonneg:
    mov [eval_mode], al
    cmp byte [eval_mode], 0
    je .eval_done
    lea rdi, [key_nnue_file]
    lea rsi, [default_nnue_file]
    call config_get
    mov rdi, rax
    cmp byte [eval_mode], 2
    je .load_v2
    call nnue_load
    jmp .load_done
.load_v2:
    call nnue2_load
.load_done:
    test eax, eax
    jz .eval_done
    mov byte [eval_mode], 0    ; fallback classic pri chybe siete
.eval_done:
    ; Pri eval_mode=2 po uspesnom loade siete zosynchronizuj akumulator
    ; na aktualnu inicializovanu poziciu, aby UCI diagnostika nezacinala
    ; v stave acc_valid=0.
    cmp byte [eval_mode], 2
    jne .eval_refresh_done
    cmp byte [nnue2_ready], 1
    jne .eval_refresh_done
    call nnue2_refresh
.eval_refresh_done:

    ; pocet threadov (P2 scaffold pre Lazy SMP): clamp 1..8
    lea rdi, [key_threads]
    lea rsi, [default_threads]
    call config_get
    mov rsi, rax
    call parse_int
    cmp rax, 1
    jge .threads_min_ok
    mov rax, 1
.threads_min_ok:
    cmp rax, 8
    jle .threads_store
    mov rax, 8
.threads_store:
    mov [uci_threads], eax

    cmp byte [uci_requested], 0
    jne .do_uci             ; --uci na cmdline: menu sa preskoci
    call select_game_mode
    cmp byte [uci_requested], 0
    jne .do_uci
    call print_title

.game_loop:
    ; 50-tahove pravidlo
    cmp byte [halfmove], 100
    jl .check_moves
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_draw_50
    mov rdx, msg_draw_50_len
    syscall
    mov byte [pgn_result], 3    ; 1/2-1/2
    jmp .done

.check_moves:
    call check_repetition
    test rax, rax
    jz .no_repetition
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_draw_rep
    mov rdx, msg_draw_rep_len
    syscall
    mov byte [pgn_result], 3    ; 1/2-1/2
    jmp .done

.no_repetition:
    call generate_all_moves
    call book_lookup_all

    movzx rax, word [move_count]
    test rax, rax
    jnz .has_moves

    movzx rax, byte [side]
    call is_in_check
    test rax, rax
    jz .stalemate

    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov byte [pgn_result], 1    ; vyhrá biely
    cmp byte [side], 0
    jne .mate_result_done       ; side = strana na tahu = zmatovaná
    mov byte [pgn_result], 2    ; vyhrá čierny
.mate_result_done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_checkmate
    mov rdx, msg_checkmate_len
    syscall
    jmp .done

.stalemate:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_stalemate
    mov rdx, msg_stalemate_len
    syscall
    mov byte [pgn_result], 3    ; 1/2-1/2
    jmp .done

.has_moves:
    call print_board
    call print_status

    ; ma engine hrat aktualnu stranu?
    movzx rax, byte [engine_side]
    cmp rax, 2              ; oboch
    je .engine_turn
    cmp rax, 3              ; ziaden
    je .user_turn
    movzx rcx, byte [side]
    cmp rax, rcx
    je .engine_turn

.user_turn:

    call print_prompt
    call read_move
    cmp rax, 1
    je .done
    cmp rax, 2
    je .game_loop
    cmp rax, 3
    je .do_new
    cmp rax, 4
    je .do_go
    cmp rax, 5
    je .do_uci
    cmp rax, 6
    je .do_suite_cmd
    cmp rax, 7
    je .do_suite_cmd
    cmp rax, 8
    je .do_bench

    mov al, [move_buf]
    cmp al, 'l'
    je .do_list
    cmp al, 'f'
    je .check_flip_cmd
    cmp al, 'p'
    je .do_perft
    cmp al, 'g'
    je .check_g_cmd
    cmp al, 't'
    je .check_t_cmd
    cmp al, 'b'
    je .check_b_cmd
    cmp al, 'e'
    je .check_e_cmd

.try_move:
    call parse_user_move
    call find_move
    test rax, rax
    jz .illegal

    call pgn_san_begin          ; SAN jadro (move_list este obsahuje legálne tahy)
    push rax
    call apply_move
    pop rax
    call update_position_state
    call record_move
    call compute_hash
    call record_hash
    call pgn_write_move         ; append do games.pgn (real-time)
    jmp .game_loop

.engine_turn:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_engine
    mov rdx, msg_engine_len
    syscall

    cmp byte [uci_own_book], 0
    je .no_book
    cmp byte [book_mode], 0
    jne .think_book
    call book_lookup
    test rax, rax
    jnz .book_move
    jmp .no_book
.think_book:
    call book_pick_move
    test rax, rax
    jnz .book_move
.no_book:
    movzx rdi, byte [search_depth]
    call search_best_move

.book_move:
    call pgn_san_begin          ; SAN jadro (move_list este obsahuje legálne tahy)
    push rax
    call print_move
    pop rax
    call apply_move
    call update_position_state
    call record_move
    call compute_hash
    call record_hash
    call pgn_write_move         ; append do games.pgn (real-time)
    jmp .game_loop

.do_list:
    call print_move_list
    jmp .game_loop

.check_flip_cmd:
    cmp qword [move_buf_len], 4
    jne .try_move
    cmp byte [move_buf+1], 'l'
    jne .try_move
    cmp byte [move_buf+2], 'i'
    jne .try_move
    cmp byte [move_buf+3], 'p'
    jne .try_move
    jmp .do_flip

.do_perft:
    movzx rdi, byte [perft_depth]
    call perft
    call print_number
    call print_newline
    jmp .game_loop

.do_bench:
    ; Zobraz popis bench: "Bench: prehladavam N FEN pozicii do hlbky D"
    lea rdi, [bench_str_header]
    call write_cstr
    mov rax, bench_fens_count
    call print_number
    lea rdi, [bench_str_fens_mid]
    call write_cstr
    mov rax, BENCH_DEPTH
    call print_number
    call print_newline

    ; vynuluj profilove akumulatory
    xor eax, eax
    mov [bench_acc_qnodes], rax
    mov [bench_acc_evals], rax
    mov [bench_acc_movegen], rax
    mov [bench_acc_makes], rax
    mov [bench_acc_unmakes], rax

    ; cas start
    call uci_now_ms
    mov r15, rax                ; r15 = start time
    xor r14, r14                ; r14 = total nodes

    ; Uloz stav hry (board, side, castle, ep, hash_history, search_limits)
    call suite_snapshot_save

    ; bench nesmie zozierat stdin: vypni input polling pocas searchu
    ; (inak piped "quit" abortne search po prvych 128 uzloch)
    mov byte [book_rating_flag], 1

    ; --- prehladaj vsetky FEN pozicie do fixnej hlbky BENCH_DEPTH ---
    xor r13, r13                ; r13 = index
.bench_loop:
    cmp r13, bench_fens_count
    jge .bench_done

    ; Nacitaj FEN pointer
    lea rax, [bench_fens]
    mov rdi, [rax + r13*8]
    call parse_fen_string
    call init_hash_history
    call record_hash
    call clear_history

    ; Urob search do fixnej hlbky
    mov rdi, BENCH_DEPTH
    call search_best_move

    ; Pricti nodes (nodes_searched) a profilove countery
    mov rax, [nodes_searched]
    add r14, rax
    mov rax, [prof_qnodes]
    add [bench_acc_qnodes], rax
    mov rax, [prof_evals]
    add [bench_acc_evals], rax
    mov rax, [prof_movegen]
    add [bench_acc_movegen], rax
    mov rax, [prof_makes]
    add [bench_acc_makes], rax
    mov rax, [prof_unmakes]
    add [bench_acc_unmakes], rax

    inc r13
    jmp .bench_loop

.bench_done:
    ; Obnov stav hry
    call suite_snapshot_restore
    mov byte [book_rating_flag], 0

    ; Vypocitaj cas
    call uci_now_ms
    sub rax, r15                ; elapsed ms
    mov r15, rax

    ; NPS = nodes * 1000 / ms (r12 = nps, 0 ak cas 0)
    xor r12, r12
    test r15, r15
    jz .bench_nps_done
    mov rax, r14
    imul rax, 1000
    xor rdx, rdx
    div r15
    mov r12, rax
.bench_nps_done:

    ; --- human-readable sumar ---
    lea rdi, [bench_str_nodes]
    call write_cstr
    mov rax, r14
    call print_number
    lea rdi, [bench_str_time]
    call write_cstr
    mov rax, r15
    call print_number
    lea rdi, [bench_str_nps]
    call write_cstr
    mov rax, r12
    call print_number
    call print_newline

    ; --- strojovo citatelny riadok: bench: nodes=N time_ms=T nps=X depth=D ---
    lea rdi, [bench_str_bench_line]
    call write_cstr
    mov rax, r14
    call print_number
    lea rdi, [bench_str_time_ms]
    call write_cstr
    mov rax, r15
    call print_number
    lea rdi, [bench_str_nps_eq]
    call write_cstr
    mov rax, r12
    call print_number
    lea rdi, [bench_str_depth_eq]
    call write_cstr
    mov rax, BENCH_DEPTH
    call print_number
    call print_newline

    ; --- profilovy rozpad (percenta z total uzlov) ---
    ; qsearch %
    lea rdi, [bench_str_p_qnodes]
    call write_cstr
    mov rax, [bench_acc_qnodes]
    call print_number
    lea rdi, [bench_str_pct]
    call write_cstr
    mov rax, [bench_acc_qnodes]
    imul rax, 100
    xor rdx, rdx
    div r14
    mov rax, rax
    call print_number
    lea rdi, [bench_str_pct_end]
    call write_cstr
    call print_newline
    ; main search % (doplnok qsearchu do 100 %)
    lea rdi, [bench_str_p_main]
    call write_cstr
    mov rax, r14
    sub rax, [bench_acc_qnodes]
    mov r13, rax
    call print_number
    lea rdi, [bench_str_pct]
    call write_cstr
    mov rax, r13
    imul rax, 100
    xor rdx, rdx
    div r14
    call print_number
    lea rdi, [bench_str_pct_end]
    call write_cstr
    call print_newline
    ; evals
    lea rdi, [bench_str_p_evals]
    call write_cstr
    mov rax, [bench_acc_evals]
    call print_number
    lea rdi, [bench_str_pct]
    call write_cstr
    mov rax, [bench_acc_evals]
    imul rax, 100
    xor rdx, rdx
    div r14
    mov rax, rax
    call print_number
    lea rdi, [bench_str_pct_end]
    call write_cstr
    call print_newline
    ; movegen
    lea rdi, [bench_str_p_movegen]
    call write_cstr
    mov rax, [bench_acc_movegen]
    call print_number
    lea rdi, [bench_str_pct]
    call write_cstr
    mov rax, [bench_acc_movegen]
    imul rax, 100
    xor rdx, rdx
    div r14
    mov rax, rax
    call print_number
    lea rdi, [bench_str_pct_end]
    call write_cstr
    call print_newline
    ; makes / unmakes (pocet na 100 uzlov)
    lea rdi, [bench_str_p_makes]
    call write_cstr
    mov rax, [bench_acc_makes]
    call print_number
    call print_newline
    lea rdi, [bench_str_p_unmakes]
    call write_cstr
    mov rax, [bench_acc_unmakes]
    call print_number
    call print_newline
    jmp .game_loop

.do_flip:
    call toggle_board_view
    cmp byte [board_flip], 0
    jne .flip_black
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_view_white
    mov rdx, msg_view_white_len
    syscall
    jmp .game_loop

.flip_black:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_view_black
    mov rdx, msg_view_black_len
    syscall
    jmp .game_loop

.check_g_cmd:
    cmp qword [move_buf_len], 2
    je .check_go_cmd
    cmp qword [move_buf_len], 3
    jne .try_move
    cmp byte [move_buf+1], 'f'
    jne .try_move
    cmp byte [move_buf+2], 'x'
    jne .try_move
    jmp .do_gfx

.check_go_cmd:
    cmp byte [move_buf+1], 'o'
    jne .try_move
    jmp .do_go

.check_t_cmd:
    cmp qword [move_buf_len], 6
    jne .do_text
    cmp byte [move_buf+1], 'b'
    jne .do_text
    cmp byte [move_buf+2], 't'
    jne .do_text
    cmp byte [move_buf+3], 'e'
    jne .do_text
    cmp byte [move_buf+4], 's'
    jne .do_text
    cmp byte [move_buf+5], 't'
    jne .do_text
    jmp .do_tbtest

.check_b_cmd:
    cmp qword [move_buf_len], 6
    jne .do_text
    cmp byte [move_buf+1], 'b'
    jne .do_text
    cmp byte [move_buf+2], 't'
    jne .do_text
    cmp byte [move_buf+3], 'e'
    jne .do_text
    cmp byte [move_buf+4], 's'
    jne .do_text
    cmp byte [move_buf+5], 't'
    jne .do_text
    jmp .do_bbtest

.check_e_cmd:
    cmp qword [move_buf_len], 7
    jne .try_move
    cmp byte [move_buf+1], 'c'
    jne .try_move
    cmp byte [move_buf+2], 'o'
    jne .try_move
    cmp byte [move_buf+3], 't'
    jne .try_move
    cmp byte [move_buf+4], 'e'
    jne .try_move
    cmp byte [move_buf+5], 's'
    jne .try_move
    cmp byte [move_buf+6], 't'
    jne .try_move
    call eco_test_print
    jmp .game_loop

.do_bbtest:
    call pos_validate
    mov r12, rax
    call pos_magics_validate
    mov r13, rax

    lea rdi, [bbtest_prefix]
    call write_cstr
    mov rax, r12
    call print_number
    call print_newline

    lea rdi, [bbtest_magics_prefix]
    call write_cstr
    mov rax, r13
    call print_number
    call print_newline

    lea rdi, [bbtest_total_prefix]
    call write_cstr
    mov rax, r12
    add rax, r13
    call print_number
    call print_newline
    jmp .game_loop

.do_tbtest:
    call tb_piece_count
    mov r12, rax
    call tb_probe_wdl
    mov r13, rax
    call tb_probe_dtz
    mov r15, rax
    mov r14, [tb_map_size]

    lea rdi, [tbtest_prefix]
    call write_cstr
    mov rax, r12
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_prefix]
    call write_cstr
    mov rax, r13
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_prefix]
    call write_cstr
    mov rax, r15
    call print_number
    call print_newline

    lea rdi, [tbtest_map_prefix]
    call write_cstr
    mov rax, r14
    call print_number
    call print_newline

    lea rdi, [tbtest_path_prefix]
    call write_cstr
    lea rdi, [tb_file_path]
    call write_cstr
    call print_newline

    lea rdi, [tbtest_wdl_payload_prefix]
    call write_cstr
    movzx rax, byte [tb_wdl_payload_probe_byte]
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_off_prefix]
    call write_cstr
    mov rax, [tb_wdl_payload_probe_off]
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_flags_prefix]
    call write_cstr
    movzx rax, byte [tb_wdl_header_flags]
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_hdr_off_prefix]
    call write_cstr
    mov rax, [tb_wdl_pairs_header_off]
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_blocks_prefix]
    call write_cstr
    mov eax, [tb_wdl_pairs_num_blocks]
    movsxd rax, eax
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_syms_prefix]
    call write_cstr
    mov eax, [tb_wdl_pairs_num_syms]
    movsxd rax, eax
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_blocksize_prefix]
    call write_cstr
    movzx rax, byte [tb_wdl_pairs_blocksize]
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_idxbits_prefix]
    call write_cstr
    movzx rax, byte [tb_wdl_pairs_idxbits]
    call print_number
    call print_newline

    lea rdi, [tbtest_wdl_const_prefix]
    call write_cstr
    movzx rax, byte [tb_wdl_pairs_is_const]
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_payload_prefix]
    call write_cstr
    movzx rax, byte [tb_dtz_payload_probe_byte]
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_off_prefix]
    call write_cstr
    mov rax, [tb_dtz_payload_probe_off]
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_flags_prefix]
    call write_cstr
    movzx rax, byte [tb_dtz_header_flags]
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_hdr_off_prefix]
    call write_cstr
    mov rax, [tb_dtz_pairs_header_off]
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_blocks_prefix]
    call write_cstr
    mov eax, [tb_dtz_pairs_num_blocks]
    movsxd rax, eax
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_syms_prefix]
    call write_cstr
    mov eax, [tb_dtz_pairs_num_syms]
    movsxd rax, eax
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_blocksize_prefix]
    call write_cstr
    movzx rax, byte [tb_dtz_pairs_blocksize]
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_idxbits_prefix]
    call write_cstr
    movzx rax, byte [tb_dtz_pairs_idxbits]
    call print_number
    call print_newline

    lea rdi, [tbtest_dtz_const_prefix]
    call write_cstr
    movzx rax, byte [tb_dtz_pairs_is_const]
    call print_number
    call print_newline
    jmp .game_loop

.do_gfx:
    cmp byte [move_buf+1], 'f'
    jne .illegal
    cmp byte [move_buf+2], 'x'
    jne .illegal
    mov byte [gfx_active_backend], 0
    call gfx_init
    test rax, rax
    jz .run_gfx
    mov byte [gfx_active_backend], 1
    call sdl_gfx_init
    test rax, rax
    jnz .game_loop

.run_gfx:
    cmp byte [gfx_active_backend], 0
    jne .run_sdl
    call gfx_run
    jmp .game_loop

.run_sdl:
    call sdl_gfx_run
    jmp .game_loop

.do_text:
    cmp byte [move_buf+1], 'e'
    jne .illegal
    cmp byte [move_buf+2], 'x'
    jne .illegal
    cmp byte [move_buf+3], 't'
    jne .illegal
    jmp .game_loop

.do_new:
    push rbx
    mov bl, [engine_side]
    mov bh, [board_flip]
    call init_board
    mov [engine_side], bl
    mov [board_flip], bh
    pop rbx
    call init_hash_history
    call record_hash
    call clear_history
    call pgn_new_game           ; uzavrie PGN sekciu predchádzajúcej partie
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_new_game
    mov rdx, msg_new_game_len
    syscall
    jmp .game_loop

.do_go:
    mov byte [engine_side], 3
    jmp .engine_turn

.do_uci:
    lea rdi, [uci_id_name]
    call write_cstr
    lea rdi, [uci_id_author]
    call write_cstr
    lea rdi, [uci_opt_hash]
    call write_cstr
    lea rdi, [uci_opt_ownbook]
    call write_cstr
    lea rdi, [uci_opt_ponder]
    call write_cstr
    lea rdi, [uci_opt_syzygy]
    call write_cstr
    lea rdi, [uci_opt_syzygy_depth]
    call write_cstr
    lea rdi, [uci_opt_overhead]
    call write_cstr
    lea rdi, [uci_opt_evalmode]
    call write_cstr
    lea rdi, [uci_opt_threads]
    call write_cstr
    lea rdi, [uci_ok]
    call write_cstr
    call uci_loop
    jmp .done

.do_suite_cmd:
    call suite_cmd_text
    jmp .game_loop

.illegal:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_error_illegal
    mov rdx, msg_error_illegal_len
    syscall
    jmp .game_loop

.done:
    call pgn_quit               ; uzavrie partiu a zavrie games.pgn
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall