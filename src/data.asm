; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; data.asm - vsetky globalne data a BSS premenne
; ============================================================

%include "chess.inc"

DEFAULT REL

; --- Inicializovane data ---
section .data

global initial_board, piece_chars

global knight_offsets, bishop_dirs, rook_dirs, king_dirs

global promo_pieces

global msg_title, msg_title_len
global book_filename

global msg_engine, msg_engine_len

global msg_prompt, msg_prompt_len

global msg_error_input, msg_error_input_len

global msg_error_illegal, msg_error_illegal_len

global msg_checkmate, msg_checkmate_len

global msg_stalemate, msg_stalemate_len
global msg_draw_50, msg_draw_50_len
global msg_draw_rep, msg_draw_rep_len
global msg_new_game, msg_new_game_len
global msg_view_white, msg_view_white_len
global msg_view_black, msg_view_black_len

global msg_move_count, msg_move_count_len

global msg_newline

global msg_files, msg_files_len
global msg_files_rev, msg_files_rev_len

global rank_char_buf, square_char_buf, square_str_buf, num_buf
global square_str_buf
global bench_str_header, bench_str_fens_mid, bench_str_nodes, bench_str_time, bench_str_nps
global bench_str_bench_line, bench_str_time_ms, bench_str_nps_eq, bench_str_depth_eq
global bench_str_p_qnodes, bench_str_p_main, bench_str_p_evals, bench_str_p_movegen
global bench_str_p_makes, bench_str_p_unmakes, bench_str_pct, bench_str_pct_end
global bench_fens, bench_fens_count

; Pociatocna pozicia
initial_board:
    db ROOK|WHITE,  KNIGHT|WHITE, BISHOP|WHITE, QUEEN|WHITE,
    db KING|WHITE,  BISHOP|WHITE, KNIGHT|WHITE, ROOK|WHITE
    db PAWN|WHITE,  PAWN|WHITE,   PAWN|WHITE,   PAWN|WHITE,
    db PAWN|WHITE,  PAWN|WHITE,   PAWN|WHITE,   PAWN|WHITE
    db 8 dup(EMPTY)
    db 8 dup(EMPTY)
    db 8 dup(EMPTY)
    db 8 dup(EMPTY)
    db PAWN|BLACK,  PAWN|BLACK,   PAWN|BLACK,   PAWN|BLACK,
    db PAWN|BLACK,  PAWN|BLACK,   PAWN|BLACK,   PAWN|BLACK
    db ROOK|BLACK,  KNIGHT|BLACK, BISHOP|BLACK, QUEEN|BLACK,
    db KING|BLACK,  BISHOP|BLACK, KNIGHT|BLACK, ROOK|BLACK

; ASCII znaky pre figury
piece_chars:
    db '.', 'P', 'N', 'B', 'R', 'Q', 'K', '?'
    db '.', 'p', 'n', 'b', 'r', 'q', 'k', '?'

; Smerove offsety
knight_offsets:  db -17, -15, -10, -6, 6, 10, 15, 17
bishop_dirs:     db -9, -7, 7, 9
rook_dirs:       db -8, -1, 1, 8
king_dirs:       db -9, -8, -7, -1, 1, 7, 8, 9

; Promocne figury pre kazdy flag
promo_pieces:
    db 0, QUEEN, ROOK, BISHOP, KNIGHT

; Retazce
msg_title:
    db "=== Sachovy engine (E4 - alpha-beta search) ===", 10, 0
msg_title_len equ $ - msg_title - 1

msg_engine:
    db "Engine: ", 0
msg_engine_len equ $ - msg_engine - 1

msg_prompt:
    db "Tah (e2e4, list, flip, perft N, bench, suite FILE [N], gfx, text, new, go, exit): ", 0
msg_prompt_len equ $ - msg_prompt - 1

msg_error_input:
    db "Neplatny vstup! e2e4, list, flip, perft N, bench, suite FILE [N], gfx, text, new, go, exit.", 10, 0
msg_error_input_len equ $ - msg_error_input - 1

bench_str_header: db "Bench: prehladavam ", 0
bench_str_fens_mid: db " FEN pozicii do hlbky ", 0
bench_str_nodes:  db "Uzly: ", 0
bench_str_time:   db ", cas (ms): ", 0
bench_str_nps:    db ", NPS: ", 0
bench_str_bench_line: db "bench: nodes=", 0
bench_str_time_ms: db " time_ms=", 0
bench_str_nps_eq: db " nps=", 0
bench_str_depth_eq: db " depth=", 0
bench_str_p_qnodes: db "prof qsearch: ", 0
bench_str_p_main:   db "prof main: ", 0
bench_str_p_evals:  db "prof evals: ", 0
bench_str_p_movegen: db "prof movegen: ", 0
bench_str_p_makes:  db "prof makes: ", 0
bench_str_p_unmakes: db "prof unmakes: ", 0
bench_str_pct:    db " (", 0
bench_str_pct_end: db "%)", 0

msg_error_illegal:
    db "Nelegalny tah!", 10, 0
msg_error_illegal_len equ $ - msg_error_illegal - 1

msg_checkmate:
    db "Mat! Koniec hry.", 10, 0
msg_checkmate_len equ $ - msg_checkmate - 1

msg_stalemate:
    db "Pat! Remiza.", 10, 0
msg_stalemate_len equ $ - msg_stalemate - 1

msg_draw_50:
    db "50-tahove pravidlo! Remiza.", 10, 0
msg_draw_50_len equ $ - msg_draw_50 - 1

msg_draw_rep:
    db "Tretie opakovnie pozicie! Remiza.", 10, 0
msg_draw_rep_len equ $ - msg_draw_rep - 1

msg_new_game:
    db "Nova hra.", 10, 0
msg_new_game_len equ $ - msg_new_game - 1

msg_view_white:
    db "Pohlad: biely dole.", 10, 0
msg_view_white_len equ $ - msg_view_white - 1

msg_view_black:
    db "Pohlad: cierny dole.", 10, 0
msg_view_black_len equ $ - msg_view_black - 1

msg_move_count:
    db "Pocet tahov: ", 0
msg_move_count_len equ $ - msg_move_count - 1

msg_newline:
    db 10

msg_files:
    db "  a b c d e f g h"
msg_files_len equ $ - msg_files

msg_files_rev:
    db "  h g f e d c b a"
msg_files_rev_len equ $ - msg_files_rev

global move_history, move_history_len
global captured_by_white, captured_by_white_len
global captured_by_black, captured_by_black_len
global book_moves, book_moves_len, pv_moves, pv_moves_len, pv_table, pv_len, root_pv_table, root_pv_len

global book_filename, config_filename, key_book, default_book, key_eco, default_eco, key_search_depth, default_search_depth
global key_language, default_language, key_syzygy, default_syzygy, key_book_mode, default_book_mode, key_book_search_depth, default_book_search_depth, key_eval_mode, default_eval_mode, key_nnue_file, default_nnue_file, key_threads, default_threads
global lang_file_en, lang_file_sk

global lkey_menu_title, ldef_menu_title
global lkey_menu_select, ldef_menu_select
global lkey_menu_mode_1, ldef_menu_mode_1
global lkey_menu_mode_2, ldef_menu_mode_2
global lkey_menu_mode_3, ldef_menu_mode_3
global lkey_menu_mode_4, ldef_menu_mode_4
global lkey_menu_mode_5, ldef_menu_mode_5
global lkey_menu_prompt, ldef_menu_prompt
global lkey_menu_invalid_1_5, ldef_menu_invalid_1_5
global lkey_menu_unavailable, ldef_menu_unavailable

global lkey_strength_title, ldef_strength_title
global lkey_strength_opt_1, ldef_strength_opt_1
global lkey_strength_opt_2, ldef_strength_opt_2
global lkey_strength_opt_3, ldef_strength_opt_3
global lkey_strength_opt_4, ldef_strength_opt_4
global lkey_strength_opt_5, ldef_strength_opt_5
global lkey_strength_opt_6, ldef_strength_opt_6
global lkey_strength_prompt, ldef_strength_prompt
global lkey_strength_invalid, ldef_strength_invalid

global lkey_color_title, ldef_color_title
global lkey_color_opt_white, ldef_color_opt_white
global lkey_color_opt_black, ldef_color_opt_black
global lkey_color_opt_random, ldef_color_opt_random
global lkey_color_prompt, ldef_color_prompt

global lkey_prompt_move, ldef_prompt_move
global lkey_prompt_invalid_input, ldef_prompt_invalid_input

global lkey_status_white, ldef_status_white
global lkey_status_black, ldef_status_black
global lkey_mode_engine_white, ldef_mode_engine_white
global lkey_mode_engine_black, ldef_mode_engine_black
global lkey_mode_both, ldef_mode_both
global lkey_mode_none, ldef_mode_none

global lkey_panel_white_took, ldef_panel_white_took
global lkey_panel_black_took, ldef_panel_black_took
global lkey_panel_moves, ldef_panel_moves
global lkey_panel_book, ldef_panel_book
global lkey_panel_pv, ldef_panel_pv
global lkey_panel_help_move, ldef_panel_help_move
global lkey_panel_help_flip, ldef_panel_help_flip
global lkey_panel_help_help, ldef_panel_help_help
global lkey_panel_help_summary, ldef_panel_help_summary

global key_framebuffer, default_framebuffer, key_mouse, default_mouse, key_debug, default_debug
global key_square_size, default_square_size, key_light_square, default_light_square
global key_dark_square, default_dark_square, key_highlight, default_highlight
global key_unicode_pieces, default_unicode_pieces, unicode_pieces
global cmdline_argc, cmdline_argv

book_filename:
    db "book.book", 0

config_filename:
    db "chess.ini", 0

key_book:
    db "book", 0

key_search_depth:
    db "search_depth", 0

key_language:
    db "language", 0

key_syzygy:
    db "syzygy", 0

default_book:
    db "book.book", 0

key_eco:
    db "eco", 0

default_eco:
    db "eco.bin", 0

default_search_depth:
    db "3", 0

default_language:
    db "en", 0

default_syzygy:
    db "", 0

key_book_mode:
    db "book_mode", 0

default_book_mode:
    db "1", 0

key_book_search_depth:
    db "book_search_depth", 0

default_book_search_depth:
    db "4", 0

key_eval_mode:
    db "eval_mode", 0

default_eval_mode:
    db "0", 0

key_nnue_file:
    db "nnue_file", 0

default_nnue_file:
    db "net2.nnue", 0

key_threads:
    db "threads", 0

default_threads:
    db "1", 0

lang_file_en:
    db "lang/en.ini", 0

lang_file_sk:
    db "lang/sk.ini", 0

lkey_menu_title: db "menu.title", 0
ldef_menu_title: db "CHESS", 0
lkey_menu_select: db "menu.select", 0
ldef_menu_select: db "Select Game Mode:", 0
lkey_menu_mode_1: db "menu.mode.1", 0
ldef_menu_mode_1: db "1 - 1 Player (vs Computer)", 0
lkey_menu_mode_2: db "menu.mode.2", 0
ldef_menu_mode_2: db "2 - 2 Players (Local)", 0
lkey_menu_mode_3: db "menu.mode.3", 0
ldef_menu_mode_3: db "3 - Puzzles (Tactical training)", 0
lkey_menu_mode_4: db "menu.mode.4", 0
ldef_menu_mode_4: db "4 - Vision (Whole-board awareness)", 0
lkey_menu_mode_5: db "menu.mode.5", 0
ldef_menu_mode_5: db "5 - Online (Play a person - live or over days)", 0
lkey_menu_prompt: db "menu.prompt", 0
ldef_menu_prompt: db "Enter choice (1-5): ", 0
lkey_menu_invalid_1_5: db "menu.invalid.1_5", 0
ldef_menu_invalid_1_5: db "Invalid choice. Enter 1-5.", 0
lkey_menu_unavailable: db "menu.unavailable", 0
ldef_menu_unavailable: db "This mode is not available yet. Try 1 or 2.", 0

lkey_strength_title: db "strength.title", 0
ldef_strength_title: db "Select Computer Strength:", 0
lkey_strength_opt_1: db "strength.opt.1", 0
ldef_strength_opt_1: db "1 - Beginner (ELO 800)", 0
lkey_strength_opt_2: db "strength.opt.2", 0
ldef_strength_opt_2: db "2 - Easy (ELO 1200)", 0
lkey_strength_opt_3: db "strength.opt.3", 0
ldef_strength_opt_3: db "3 - Medium (ELO 1500)", 0
lkey_strength_opt_4: db "strength.opt.4", 0
ldef_strength_opt_4: db "4 - Hard (ELO 1800)", 0
lkey_strength_opt_5: db "strength.opt.5", 0
ldef_strength_opt_5: db "5 - Expert (ELO 2200)", 0
lkey_strength_opt_6: db "strength.opt.6", 0
ldef_strength_opt_6: db "6 - Master (ELO 2600)", 0
lkey_strength_prompt: db "strength.prompt", 0
ldef_strength_prompt: db "Enter choice (1-6) or ELO number: ", 0
lkey_strength_invalid: db "strength.invalid", 0
ldef_strength_invalid: db "Invalid choice. Enter 1-6 or ELO number.", 0

lkey_color_title: db "color.title", 0
ldef_color_title: db "Select Your Color:", 0
lkey_color_opt_white: db "color.opt.white", 0
ldef_color_opt_white: db "1 - White (Move first)", 0
lkey_color_opt_black: db "color.opt.black", 0
ldef_color_opt_black: db "2 - Black (Move second)", 0
lkey_color_opt_random: db "color.opt.random", 0
ldef_color_opt_random: db "[Enter] - Random (Let fate decide)", 0
lkey_color_prompt: db "color.prompt", 0
ldef_color_prompt: db "Enter choice or press Enter: ", 0

lkey_prompt_move: db "prompt.move", 0
ldef_prompt_move: db "Move (e2e4, list, flip, perft N, suite FILE [N], gfx, text, new, go, exit): ", 0
lkey_prompt_invalid_input: db "prompt.invalid_input", 0
ldef_prompt_invalid_input: db "Invalid input! Use e2e4, list, flip, perft N, suite FILE [N], gfx, text, new, go, exit.", 0

lkey_status_white: db "status.white", 0
ldef_status_white: db "WHITE to move", 0
lkey_status_black: db "status.black", 0
ldef_status_black: db "BLACK to move", 0
lkey_mode_engine_white: db "status.mode.engine_white", 0
ldef_mode_engine_white: db "1-Player | You: Black", 0
lkey_mode_engine_black: db "status.mode.engine_black", 0
ldef_mode_engine_black: db "1-Player | You: White", 0
lkey_mode_both: db "status.mode.both", 0
ldef_mode_both: db "Engine vs Engine", 0
lkey_mode_none: db "status.mode.none", 0
ldef_mode_none: db "2-Players (Local)", 0

lkey_panel_white_took: db "panel.white_took", 0
ldef_panel_white_took: db "White took:", 0
lkey_panel_black_took: db "panel.black_took", 0
ldef_panel_black_took: db "Black took:", 0
lkey_panel_moves: db "panel.moves", 0
ldef_panel_moves: db "Moves:", 0
lkey_panel_book: db "panel.book", 0
ldef_panel_book: db "Book:", 0
lkey_panel_pv:   db "panel.pv", 0
ldef_panel_pv:   db "PV:", 0
lkey_panel_help_move: db "panel.help.move", 0
ldef_panel_help_move: db "e2e4 - make move", 0
lkey_panel_help_flip: db "panel.help.flip", 0
ldef_panel_help_flip: db "flip - flip board", 0
lkey_panel_help_help: db "panel.help.help", 0
ldef_panel_help_help: db "help - commands", 0
lkey_panel_help_summary: db "panel.help.summary", 0
ldef_panel_help_summary: db "e2e4 flip help", 0

key_framebuffer:
    db "framebuffer", 0
default_framebuffer:
    db "/dev/fb0", 0

key_mouse:
    db "mouse", 0
default_mouse:
    db "/dev/input/event0", 0

key_square_size:
    db "square_size", 0
default_square_size:
    db "100", 0

key_light_square:
    db "light_square", 0
default_light_square:
    db "0xDDBB88", 0

key_dark_square:
    db "dark_square", 0
default_dark_square:
    db "0xA67240", 0

key_highlight:
    db "highlight", 0
default_highlight:
    db "0x55AA55", 0

key_unicode_pieces:
    db "unicode_pieces", 0
default_unicode_pieces:
    db "0", 0

key_debug:
    db "debug", 0
default_debug:
    db "0", 0


; Male bufre
rank_char_buf:   db "0 ", 0
square_char_buf: db "? ", 0
square_str_buf:  db "??", 0
num_buf:         db 16 dup(0)

; --- LMR tabulka: redukcie pre Late Move Reduction ---
; [depth-1][index], depth 1-16, index 0-15
; Formula: redukcia ~ log(depth) * log(index); nulove redukcie pre male values
global lmr_table
lmr_table:
    ; depth 1: vsetky 0
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ; depth 2
    db 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    ; depth 3
    db 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
    ; depth 4
    db 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3
    ; depth 5
    db 0, 0, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 6
    db 0, 0, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 7
    db 0, 0, 1, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 8
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 9
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 10
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 11
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 12
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 13
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 14
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 15
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
    ; depth 16
    db 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3

; --- Benchmark FEN pozicie ---
bench_fens:
    dq .fen1, .fen2, .fen3, .fen4, .fen5, .fen6
bench_fens_count equ ($ - bench_fens) / 8

.fen1: db "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 0
.fen2: db "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -", 0
.fen3: db "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -", 0
.fen4: db "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 0
.fen5: db "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 0
.fen6: db "r4rk1/8/8/8/8/8/8/R3K2R w KQ - 0 1", 0

; --- BSS ---
section .bss

global board, side, castle, enpassant, halfmove, fullmove, board_flip
global move_buf, move_buf_len, move_list, move_count, uci_requested
global moved_piece, captured_piece
global position_hash, perft_depth, config_buf, engine_side
global lang_buf

global book_ptrs, book_sizes, book_count, search_depth

global gfx_mode, gfx_initialized, fb_ptr, fb_size, fb_width, fb_height
global fb_bpp, fb_stride, fb_bytes, square_size, board_offset_x, board_offset_y
global light_col, dark_col, highlight_col, bg_col, mouse_device, debug
global mouse_fd, mouse_x, mouse_y, mouse_btn_left, gfx_highlight_sq
global gfx_fb_fd
global gfx_active_backend

position_hash:  resq 1

; Historia hashov pre detekciu opakovanej pozicie
global hash_history, hash_count
hash_history:   resq 256
hash_count:     resq 1

board:          resb 64
side:           resb 1
castle:         resb 1
enpassant:      resb 1
halfmove:       resb 1
fullmove:       resw 1
board_flip:     resb 1

; 0 = engine hra biely, 1 = cierny, 2 = oboch, 3 = ziaden
engine_side:    resb 1

global uci_stop_flag, uci_ponder, uci_own_book, uci_hash_size, uci_move_overhead, uci_syzygy_probe_depth, uci_threads
uci_stop_flag:  resb 1
uci_ponder:     resb 1
uci_own_book:   resb 1
uci_hash_size:  resd 1
uci_move_overhead: resd 1    ; milliseconds overhead per move (default 100 ms)
uci_syzygy_probe_depth: resd 1 ; minimalna hlbka pre TB probe (0 = vypnute)
uci_threads:    resd 1       ; P2 scaffold: pocet threadov pre buduci Lazy SMP (1..8)
global smp_shared, smp_child_count
smp_shared:      resq 1      ; pointer na MAP_SHARED stranku: +0 = stop flag
smp_child_count: resd 1      ; pocet bezucich helper procesov
global book_mode, book_search_depth, eval_mode
book_mode:      resb 1       ; 0 = instant prvy knizny tah, 1 = vyber searchom
book_search_depth: resb 1    ; hlbka ratingu kniznych tahov (default 4)
eval_mode:      resb 1       ; 0 = classic eval, 1 = NNUE (linearny PST model)
global book_rating_flag
book_rating_flag: resb 1       ; 1 = prebieha book rating (check_time nepoluje stdin)
global lang_is_en
lang_is_en:     resb 1

global unicode_pieces
unicode_pieces: resb 1       ; 0 = ASCII, 1 = unicode polobloky 8px, 2 = 16px

; cmdline snapshot z _start (argc a ukazatel na argv[0]) pre key=value override
cmdline_argc:   resq 1
cmdline_argv:   resq 1

global tt_base, tt_bytes, tt_mask
tt_base:        resq 1
tt_bytes:       resq 1
tt_mask:        resq 1

; Limity pre aktualny search (UCI time / depth)
global search_limits, nodes_searched, search_last_score
search_limits:
    .mode:       resb 1       ; 0=fixed depth, 1=movetime, 2=wtime/btime, 3=infinite, 4=ponder
    .depth:      resb 1
    .movestogo:  resb 1
    .pad:        resb 5
    .movetime:   resq 1
    .wtime:      resq 1
    .btime:      resq 1
    .winc:       resq 1
    .binc:       resq 1
    .start_time: resq 1       ; ms od epochy (clock_gettime)
    .soft_limit: resq 1       ; ms
    .hard_limit: resq 1       ; ms

nodes_searched: resq 1
search_last_score: resd 1

global singular_excl
singular_excl:  resd 1      ; excluded move pre singular extensions (0 = ziaden)

global lang_txt_menu_title, lang_txt_menu_select, lang_txt_menu_mode_1, lang_txt_menu_mode_2, lang_txt_menu_mode_3, lang_txt_menu_mode_4, lang_txt_menu_mode_5
global lang_txt_menu_prompt, lang_txt_menu_invalid_1_5, lang_txt_menu_unavailable
global lang_txt_strength_title, lang_txt_strength_opt_1, lang_txt_strength_opt_2, lang_txt_strength_opt_3
global lang_txt_strength_opt_4, lang_txt_strength_opt_5, lang_txt_strength_opt_6
global lang_txt_strength_prompt, lang_txt_strength_invalid
global lang_txt_color_title, lang_txt_color_opt_white, lang_txt_color_opt_black, lang_txt_color_opt_random, lang_txt_color_prompt
global lang_txt_prompt_move, lang_txt_prompt_invalid_input
global lang_txt_status_white, lang_txt_status_black
global lang_txt_mode_engine_white, lang_txt_mode_engine_black, lang_txt_mode_both, lang_txt_mode_none
global lang_txt_panel_white_took, lang_txt_panel_black_took, lang_txt_panel_moves, lang_txt_panel_book, lang_txt_panel_pv
global lang_txt_panel_help_move, lang_txt_panel_help_flip, lang_txt_panel_help_help, lang_txt_panel_help_summary

lang_txt_menu_title:         resb 64
lang_txt_menu_select:        resb 128
lang_txt_menu_mode_1:        resb 128
lang_txt_menu_mode_2:        resb 128
lang_txt_menu_mode_3:        resb 128
lang_txt_menu_mode_4:        resb 128
lang_txt_menu_mode_5:        resb 128
lang_txt_menu_prompt:        resb 128
lang_txt_menu_invalid_1_5:   resb 128
lang_txt_menu_unavailable:   resb 128

lang_txt_strength_title:     resb 128
lang_txt_strength_opt_1:     resb 128
lang_txt_strength_opt_2:     resb 128
lang_txt_strength_opt_3:     resb 128
lang_txt_strength_opt_4:     resb 128
lang_txt_strength_opt_5:     resb 128
lang_txt_strength_opt_6:     resb 128
lang_txt_strength_prompt:    resb 128
lang_txt_strength_invalid:   resb 128

lang_txt_color_title:        resb 128
lang_txt_color_opt_white:    resb 128
lang_txt_color_opt_black:    resb 128
lang_txt_color_opt_random:   resb 128
lang_txt_color_prompt:       resb 128

lang_txt_prompt_move:        resb 192
lang_txt_prompt_invalid_input: resb 192

lang_txt_status_white:       resb 96
lang_txt_status_black:       resb 96
lang_txt_mode_engine_white:  resb 128
lang_txt_mode_engine_black:  resb 128
lang_txt_mode_both:          resb 96
lang_txt_mode_none:          resb 96

lang_txt_panel_white_took:   resb 96
lang_txt_panel_black_took:   resb 96
lang_txt_panel_moves:        resb 96
lang_txt_panel_book:         resb 96
lang_txt_panel_pv:           resb 96
lang_txt_panel_help_move:    resb 96
lang_txt_panel_help_flip:    resb 96
lang_txt_panel_help_help:    resb 96
lang_txt_panel_help_summary: resb 96

moved_piece:    resb 1
captured_piece: resb 1

move_buf:       resb 4096
move_buf_len:   resq 1
uci_requested:  resb 1
perft_depth:    resb 1
config_buf:     resb 4096
lang_buf:       resb 4096

move_list:      resw 256
move_count:     resw 1

move_history:       resw 512
move_history_len:   resq 1

captured_by_white:      resb 32
captured_by_white_len:  resq 1
captured_by_black:      resb 32
captured_by_black_len:  resq 1

book_moves:     resw 64
book_moves_len: resq 1
pv_moves:       resw 40
pv_moves_len:   resq 1

; PV table ulozena pocas searchu: pv_table[ply][0..len-1], pv_len[ply]
pv_table:       resw 64*64
pv_len:         resq 64

; Root PV storage (nezavisle od pv_table, lebo root negamax bezi na ply 0
; a nuloval by si pv_len[0] pri kazdom root tahu).
root_pv_table:  resw 64
root_pv_len:    resq 1

; Podpora viacerych opening book suborov
book_ptrs:      resq 4
book_sizes:     resq 4
book_count:     resq 1

search_depth:   resb 1

; Graficke premenne
gfx_mode:        resb 1
gfx_initialized: resb 1
fb_ptr:          resq 1
fb_size:         resq 1
fb_width:        resd 1
fb_height:       resd 1
fb_bpp:          resd 1
fb_stride:       resd 1
fb_bytes:        resd 1
square_size:     resd 1
board_offset_x:  resd 1
board_offset_y:  resd 1
light_col:       resd 1
dark_col:        resd 1
highlight_col:   resd 1
bg_col:          resd 1
mouse_device:    resb 64
mouse_fd:        resq 1
mouse_x:         resd 1
mouse_y:         resd 1
mouse_btn_left:  resb 1
gfx_highlight_sq: resb 1
debug:           resb 1
gfx_fb_fd:       resd 1
gfx_active_backend: resb 1