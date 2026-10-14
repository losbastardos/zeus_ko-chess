; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; uci.asm - zakladna podpora UCI protokolu
; ============================================================

%include "chess.inc"

%ifndef ENABLE_PL_INVARIANT
%define ENABLE_PL_INVARIANT 0
%endif

DEFAULT REL

section .data

global uci_id_name, uci_id_author, uci_ok, uci_ready, uci_bestmove, uci_unknown
global uci_opt_hash, uci_opt_ownbook, uci_opt_ponder, uci_opt_syzygy, uci_opt_syzygy_depth, uci_opt_overhead, uci_opt_evalmode, uci_opt_threads

%defstr BUILD_DATE_STR BUILD_DATE

uci_id_name:
    db "id name Zeus_KO ", BUILD_DATE_STR, 10, 0
uci_id_name_len equ $ - uci_id_name - 1

uci_id_author:
    db "id author Marek Suchy", 10, 0
uci_id_author_len equ $ - uci_id_author - 1

uci_ok:
    db "uciok", 10, 0
uci_ok_len equ $ - uci_ok - 1

uci_opt_hash:    db "option name Hash type spin default 64 min 16 max 1024", 10, 0
uci_opt_ownbook: db "option name OwnBook type check default true", 10, 0
uci_opt_ponder:  db "option name Ponder type check default false", 10, 0
uci_opt_syzygy:  db "option name SyzygyPath type string default <empty>", 10, 0
uci_opt_syzygy_depth: db "option name SyzygyProbeDepth type spin default 1 min 0 max 64", 10, 0
uci_opt_overhead: db "option name MoveOverhead type spin default 100 min 0 max 10000", 10, 0
uci_opt_evalmode: db "option name EvalMode type spin default 0 min 0 max 2", 10, 0
uci_opt_threads: db "option name Threads type spin default 1 min 1 max 8", 10, 0

uci_ready:
    db "readyok", 10, 0
uci_ready_len equ $ - uci_ready - 1

uci_bestmove:
    db "bestmove ", 0
uci_bestmove_len equ $ - uci_bestmove - 1

uci_unknown:
    db "info string neznamy prikaz", 10, 0
uci_unknown_len equ $ - uci_unknown - 1

uci_tbtest_prefix: db "info string tbtest pieces=", 0
uci_eco_prefix: db "info string ", 0
uci_tbtest_wdl:    db " wdl=", 0
uci_tbtest_dtz:    db " dtz=", 0
uci_tbtest_map:    db " map_bytes=", 0
uci_tbtest_path:   db " path=", 0
uci_tbtest_wdl_payload: db " wdl_payload_byte=", 0
uci_tbtest_dtz_payload: db " dtz_payload_byte=", 0
uci_tbtest_wdl_off: db " wdl_payload_off=", 0
uci_tbtest_dtz_off: db " dtz_payload_off=", 0
uci_tbtest_wdl_flags: db " wdl_flags=", 0
uci_tbtest_dtz_flags: db " dtz_flags=", 0
uci_tbtest_wdl_hdr_off: db " wdl_pairs_hdr_off=", 0
uci_tbtest_dtz_hdr_off: db " dtz_pairs_hdr_off=", 0
uci_tbtest_wdl_blocks: db " wdl_pairs_blocks=", 0
uci_tbtest_dtz_blocks: db " dtz_pairs_blocks=", 0
uci_tbtest_wdl_syms: db " wdl_pairs_syms=", 0
uci_tbtest_dtz_syms: db " dtz_pairs_syms=", 0
uci_tbtest_wdl_blocksize: db " wdl_pairs_blocksize=", 0
uci_tbtest_dtz_blocksize: db " dtz_pairs_blocksize=", 0
uci_tbtest_wdl_idxbits: db " wdl_pairs_idxbits=", 0
uci_tbtest_dtz_idxbits: db " dtz_pairs_idxbits=", 0
uci_tbtest_wdl_const: db " wdl_pairs_const=", 0
uci_tbtest_dtz_const: db " dtz_pairs_const=", 0
uci_tbtest_wdl_order_byte: db " wdl_order_byte=", 0
uci_tbtest_dtz_order_byte: db " dtz_order_byte=", 0
uci_tbtest_wdl_wk: db " wdl_wk=", 0
uci_tbtest_wdl_bk: db " wdl_bk=", 0
uci_tbtest_wdl_extra: db " wdl_extra=", 0
uci_tbtest_wdl_order: db " wdl_order=", 0
uci_tbtest_wdl_idx: db " wdl_idx=", 0
uci_tbtest_wdl_tbsize: db " wdl_tb_size=", 0
uci_tbtest_wdl_nf_code: db " wdl_nf_code=", 0
uci_tbtest_wdl_p4_tbsize: db " wdl_p4_tb_size=", 0
uci_tbtest_dtz_wk: db " dtz_wk=", 0
uci_tbtest_dtz_bk: db " dtz_bk=", 0
uci_tbtest_dtz_extra: db " dtz_extra=", 0
uci_tbtest_dtz_target: db " dtz_target=", 0
uci_tbtest_dtz_order: db " dtz_order=", 0
uci_tbtest_dtz_idx: db " dtz_idx=", 0
uci_tbtest_dtz_raw_symbol: db " dtz_raw_symbol=", 0
uci_tbtest_dtz_helper_ret: db " dtz_helper_ret=", 0
uci_tbtest_dtz_helper_ok: db " dtz_helper_ok=", 0
uci_tbtest_dtz_nf_code: db " dtz_nf_code=", 0
uci_tbtest_dtz_bside: db " dtz_bside=", 0
uci_tbtest_dtz_flags1: db " dtz_flags1=", 0
uci_tbtest_dtz_minlen: db " dtz_min_len=", 0
uci_tbtest_dtz_tbsize: db " dtz_tb_size=", 0
uci_tbtest_dtz_ptr_wdl_i: db " dtz_ptr_wdl_i=", 0
uci_tbtest_dtz_ptr_wdl_s: db " dtz_ptr_wdl_s=", 0
uci_tbtest_dtz_ptr_wdl_d: db " dtz_ptr_wdl_d=", 0
uci_tbtest_dtz_ptr_dtz_i: db " dtz_ptr_dtz_i=", 0
uci_tbtest_dtz_ptr_dtz_s: db " dtz_ptr_dtz_s=", 0
uci_tbtest_dtz_ptr_dtz_d: db " dtz_ptr_dtz_d=", 0
uci_tbtest_dec_mainidx: db " dec_mainidx=", 0
uci_tbtest_dec_litidx: db " dec_litidx=", 0
uci_tbtest_dec_block: db " dec_block=", 0
uci_tbtest_dec_bitcnt: db " dec_bitcnt=", 0
uci_tbtest_dec_code_hex: db " dec_code_hex=", 0
uci_tbtest_dec_root_sym: db " dec_root_sym=", 0
uci_tbtest_dec_leaf_sym: db " dec_leaf_sym=", 0
uci_tbtest_dec_stage: db " dec_stage=", 0
uci_tbtest_dec_step: db "info string dec_step ", 0
uci_tbtest_dec_step_sym: db " sym=", 0
uci_tbtest_dec_step_s1: db " s1=", 0
uci_tbtest_dec_step_s2: db " s2=", 0
uci_tbtest_dec_step_lit: db " lit=", 0
uci_tbtest_dec_step_pick: db " pick=", 0
uci_bbtest_prefix: db "info string bbtest mismatches=", 0

uci_log_name:      db "uci_debug.log", 0
uci_log_start:     db "=== Zeus_KO ", BUILD_DATE_STR, " start ===", 10
uci_log_start_len  equ $ - uci_log_start
uci_log_fail:      db "info string uci_debug.log: otvorenie zlyhalo (chyba prava zapisu?)", 10
uci_log_fail_len   equ $ - uci_log_fail
uci_log_prefix_in: db ">> "
uci_log_bm_prefix: db "<< bestmove "
uci_log_bm_prefix_len equ $ - uci_log_bm_prefix
uci_log_bm_null:   db "<< bestmove 0000", 10
uci_log_bm_null_len equ $ - uci_log_bm_null
uci_log_src_prefix: db "<< source "
uci_log_src_prefix_len equ $ - uci_log_src_prefix
uci_src_book_str:  db "book"
uci_src_book_len   equ $ - uci_src_book_str
uci_src_search_str: db "search"
uci_src_search_len  equ $ - uci_src_search_str
uci_info_src_book:  db "info string move_source=book", 10
uci_info_src_book_len equ $ - uci_info_src_book
uci_info_src_search: db "info string move_source=search", 10
uci_info_src_search_len equ $ - uci_info_src_search
uci_info_root_top:  db "info string root_top ", 0
uci_info_root_sep:  db "/", 0
uci_info_root_sp:   db " ", 0
uci_info_allprune:  db "info string all_prune=", 0
uci_info_eval_white: db "info string static_eval_white=", 0
uci_info_eval_stm:   db " static_eval_stm=", 0
uci_info_evaldiff_list: db "info string evaldiff list", 0
uci_info_evaldiff_scan: db "info string evaldiff scan", 0
uci_info_evaldiff_first: db "info string evaldiff first_diff=", 0
uci_info_evaldiff_none: db "none", 0
uci_info_evaldiff_score: db " score=", 0
uci_info_evaldiff_mg: db " mg=", 0
uci_info_evaldiff_eg: db " eg=", 0
uci_info_evaldiff_phase: db " phase=", 0
uci_info_evaldiff_wk: db " wk=", 0
uci_info_evaldiff_bk: db " bk=", 0
uci_info_evaldiff_tropw: db " trop_w=", 0
uci_info_evaldiff_tropb: db " trop_b=", 0
uci_info_evaldiff_listv: db " list=", 0
uci_info_evaldiff_scanv: db " scan=", 0
uci_info_evaldiff_name_score: db "score", 0
uci_info_evaldiff_name_mg: db "mg", 0
uci_info_evaldiff_name_eg: db "eg", 0
uci_info_evaldiff_name_phase: db "phase", 0
uci_info_evaldiff_name_wk: db "wk", 0
uci_info_evaldiff_name_bk: db "bk", 0
uci_info_evaldiff_name_tropw: db "trop_w", 0
uci_info_evaldiff_name_tropb: db "trop_b", 0
%if ENABLE_PL_INVARIANT = 1
uci_info_evaldiff_seen_base: db "info string evaldiff seen_base lists=", 0
uci_info_evaldiff_seen_counts: db "info string evaldiff seen_counts", 0
uci_info_evaldiff_seen_first: db "info string evaldiff seen_first", 0
uci_info_evaldiff_direct_counts: db "info string evaldiff direct_counts", 0
uci_info_evaldiff_direct_first: db "info string evaldiff direct_first", 0
uci_info_evaldiff_counts_base: db " counts=", 0
uci_info_evaldiff_idx_prefix: db " i", 0
uci_info_evaldiff_eq: db "=", 0
uci_info_evaldiff_slash: db "/", 0
uci_info_evaldiff_sp: db " ", 0
%endif
uci_info_hashtest_ok: db "info string hashtest mismatches=0 plies=", 0
uci_info_hashtest_bad: db "info string hashtest mismatch phase=", 0
uci_info_hashtest_ply: db " ply=", 0
uci_info_hashtest_flag: db " flag=", 0
uci_info_hashtest_move: db " move=", 0
uci_info_hashtest_h_expected: db " h_expected=", 0
uci_info_hashtest_h_actual: db " h_actual=", 0
uci_info_hashtest_phase_make: db "make", 0
uci_info_hashtest_phase_unmake_delta: db "unmake_delta", 0
uci_info_hashtest_phase_unmake_restore: db "unmake_restore", 0
uci_info_nnuewalk_ok: db "info string nnuewalk mismatches=0 plies=", 0
uci_info_nnuewalk_bad: db "info string nnuewalk mismatch phase=", 0
uci_info_nnuewalk_ply: db " ply=", 0
uci_info_nnuewalk_move: db " move=", 0
uci_info_nnuewalk_type: db " type=", 0
uci_info_nnuewalk_persp: db " persp=", 0
uci_info_nnuewalk_eval_inc: db " eval_inc=", 0
uci_info_nnuewalk_eval_ref: db " eval_ref=", 0
uci_info_nnuewalk_fen: db " fen=", 0
uci_info_nnuewalk_no_nnue: db "info string nnuewalk unavailable nnue2_ready=0", 0
uci_info_nnuewalk_phase_make: db "make", 0
uci_info_nnuewalk_phase_unmake: db "unmake", 0
uci_info_nnuewalk_type_quiet: db "quiet", 0
uci_info_nnuewalk_type_capture: db "capture", 0
uci_info_nnuewalk_type_castle: db "castle", 0
uci_info_nnuewalk_type_ep: db "ep", 0
uci_info_nnuewalk_type_promo: db "promo", 0
uci_info_nnuewalk_persp_stm: db "stm", 0
uci_info_nnuewalk_persp_opp: db "opp", 0
uci_info_rootdiag_prefix: db "info string root_diag move=", 0
uci_info_rootdiag_score:  db " score=", 0
uci_info_rootdiag_alpha:  db " alpha=", 0
uci_info_rootdiag_beta:   db " beta=", 0
uci_info_rootdiag_flag:   db " flag=", 0
uci_info_rootdiag_nodes:  db " nodes=", 0
uci_info_rootdiag_pv:     db " pv=", 0
uci_info_rootdiag_flag_ex: db "exact", 0
uci_info_rootdiag_flag_fl: db "fail-low", 0
uci_info_rootdiag_flag_fh: db "fail-high", 0
uci_info_evalstate_prefix: db "info string evalstate stm=", 0
uci_info_evalstate_valid:  db " acc_valid=", 0
uci_info_evalstate_match:  db " acc_match=", 0
uci_info_evalstate_inc:    db " nnue_inc=", 0
uci_info_evalstate_ref:    db " nnue_ref=", 0
uci_str_0000:      db "0000"
uci_log_bad_bm:    db "!! WARNING: bestmove nie je legalny tah - fallback na prvy legalny", 10
uci_log_bad_bm_len equ $ - uci_log_bad_bm

section .data
uci_log_fd: dq -2                      ; -2 = neotvorene, -1 = zlyhalo (bez retry)

section .bss
uci_next_idx: resq 1      ; index dalsieho tokenu (generate_all_moves nicí r12)
fen_buf:      resb 128    ; buffer pre FEN reťazec
uci_timespec: resq 2
pv_char_buf:  resb 1
uci_log_move_buf: resb 8 ; "e2e4" / "e7e8q" pre log
input_pend:     resb 512  ; nevybavený vstup z pollu počas searchu (oddelený od move_buf!)
input_pend_len: resq 1
uci_quit_flag:  resb 1    ; 'quit' prišlo počas searchu -> exit hneď po bestmove
uci_pgn_ply:    resq 1    ; počet ťahov zaznamenaných do PGN v aktuálnej partii
uci_pgn_idx:    resq 1    ; index ťahu v práve spracúvanom 'position ... moves'
input_pollfd:   resd 2    ; pollfd: dd fd, dw events, dw revents
uci_iter_start: resq 1    ; mode 2: start aktuálnej ID iterácie (ms)
uci_iter_dur:   resq 1    ; mode 2: trvanie poslednej dokončenej iterácie (ms)
uci_move_source: resb 1   ; 0=search, 1=book
uci_last_iter_move: resd 1 ; posledny tah vrateny search_best_move v ID smycke
uci_eval_white_tmp: resd 1
uci_eval_stm_tmp:   resd 1
uci_evaldiff_saved_dirty: resb 1
uci_evaldiff_pad: resb 3
uci_evaldiff_list_score: resd 1
uci_evaldiff_scan_score: resd 1
uci_evaldiff_list_mg: resd 1
uci_evaldiff_scan_mg: resd 1
uci_evaldiff_list_eg: resd 1
uci_evaldiff_scan_eg: resd 1
uci_evaldiff_list_phase: resd 1
uci_evaldiff_scan_phase: resd 1
uci_evaldiff_list_wk: resd 1
uci_evaldiff_scan_wk: resd 1
uci_evaldiff_list_bk: resd 1
uci_evaldiff_scan_bk: resd 1
uci_evaldiff_list_tropw: resd 1
uci_evaldiff_scan_tropw: resd 1
uci_evaldiff_list_tropb: resd 1
uci_evaldiff_scan_tropb: resd 1
%if ENABLE_PL_INVARIANT = 1
uci_evaldiff_lists_base_lo: resd 1
uci_evaldiff_lists_base_hi: resd 1
uci_evaldiff_counts_base_lo: resd 1
uci_evaldiff_counts_base_hi: resd 1
%endif
uci_hashtest_plies:      resd 1
uci_hashtest_phase:      resd 1
uci_hashtest_flag:       resd 1
uci_hashtest_move:       resw 1
uci_hashtest_h_expected: resq 1
uci_hashtest_h_actual:   resq 1
uci_nnuewalk_plies:        resd 1
uci_nnuewalk_phase:        resd 1
uci_nnuewalk_persp:        resd 1
uci_nnuewalk_move:         resw 1
uci_nnuewalk_type:         resd 1
uci_nnuewalk_total:        resd 1
uci_nnuewalk_eval_inc_stm: resd 1
uci_nnuewalk_eval_inc_opp: resd 1
uci_nnuewalk_eval_ref_stm: resd 1
uci_nnuewalk_eval_ref_opp: resd 1
uci_nnuewalk_moves:        resw 1024
uci_nnuewalk_types:        resb 1024
uci_rootdiag_enabled:      resb 1

INPUT_PEND_SIZE equ 512

section .text

global uci_loop, write_cstr, search_poll_input, uci_now_ms

extern init_board, init_hash_history, record_hash, clear_history
extern pgn_san_begin, pgn_write_move, pgn_new_game, pgn_quit
extern generate_all_moves, find_move, apply_move, update_position_state, compute_hash
extern perft
extern search_best_move, book_lookup, print_move, square_to_str, print_number
extern tt_init
extern parse_fen_string, parse_int, config_get
extern board, side, move_buf, move_buf_len, move_list, move_count, search_depth
extern castle, enpassant, halfmove, fullmove
extern position_hash, square_str_buf
extern evaluate
extern eval_dbg_mg, eval_dbg_eg, eval_dbg_phase, eval_dbg_wk, eval_dbg_bk, eval_dbg_trop_w, eval_dbg_trop_b
extern eval_dbg_lp_lists_base, eval_dbg_lp_counts_base, eval_dbg_lp_counts, eval_dbg_lp_first
extern eval_mode
extern nnue_load
extern nnue2_load
extern nnue2_eval, nnue2_refresh
extern nnue2_fwd
extern nnue2_ready
extern nnue_acc_valid
extern nnue_acc_hash
extern key_nnue_file
extern default_nnue_file
extern uci_stop_flag, uci_ponder, uci_own_book, uci_hash_size, uci_move_overhead, uci_syzygy_probe_depth, uci_threads
extern smp_init, smp_clear_stop, smp_spawn_helpers, smp_stop_and_reap, smp_signal_stop
extern smp_shared
extern search_limits, nodes_searched, search_last_score
extern asp_alpha, asp_beta, asp_delta, asp_use, asp_retry
extern root_trace_count, root_trace_moves, root_trace_scores
extern root_diag_count, root_diag_moves, root_diag_scores, root_diag_alpha, root_diag_beta
extern root_diag_flag, root_diag_nodes, root_diag_pv0
extern trace_white_enable
extern prof_allprune
extern make_move, unmake_move, tt_probe
extern pl_rebuild_from_board, pl_dirty, pl_lists, pl_counts
extern captured_piece
extern filter_legal_moves
extern pv_moves, pv_moves_len
extern msg_newline
extern tb_init, tb_path, tb_path_len, tb_probe_wdl, tb_probe_dtz, tb_piece_count, tb_map_size, tb_file_path, tb_tb_size
extern pos_validate, generate_all_moves, print_move_list
extern book_pick_move, book_mode, book_search_depth
extern tb_wdl_payload_probe_byte, tb_dtz_payload_probe_byte
extern tb_wdl_payload_probe_off, tb_dtz_payload_probe_off
extern tb_wdl_header_flags, tb_dtz_header_flags
extern tb_wdl_pairs_header_off, tb_dtz_pairs_header_off
extern tb_wdl_pairs_num_blocks, tb_dtz_pairs_num_blocks
extern tb_wdl_pairs_num_syms, tb_dtz_pairs_num_syms
extern tb_wdl_pairs_blocksize, tb_dtz_pairs_blocksize
extern tb_wdl_pairs_idxbits, tb_dtz_pairs_idxbits
extern tb_wdl_pairs_is_const, tb_dtz_pairs_is_const
extern tb_wdl_debug_wk, tb_wdl_debug_bk, tb_wdl_debug_extra
extern tb_wdl_debug_order, tb_wdl_debug_idx, tb_wdl_debug_order_byte, tb_wdl_debug_nf_code, tb_wdl_debug_tb_size
extern tb_dtz_debug_wk, tb_dtz_debug_bk, tb_dtz_debug_extra
extern tb_dtz_debug_target_code
extern tb_dtz_debug_order, tb_dtz_debug_order_byte
extern tb_dtz_debug_idx, tb_dtz_debug_raw_symbol
extern tb_dtz_debug_helper_ret, tb_dtz_debug_helper_ok
extern tb_dtz_debug_nf_code, tb_dtz_debug_bside_used, tb_dtz_debug_flags1
extern tb_dtz_debug_tb_size, tb_dtz_debug_min_len
extern tb_dtz_debug_ptr_wdl_index, tb_dtz_debug_ptr_wdl_size, tb_dtz_debug_ptr_wdl_data
extern tb_dtz_debug_ptr_dtz_index, tb_dtz_debug_ptr_dtz_size, tb_dtz_debug_ptr_dtz_data
extern tb_dec_trace_mainidx, tb_dec_trace_litidx, tb_dec_trace_block
extern tb_dec_trace_bitcnt, tb_dec_trace_root_sym, tb_dec_trace_leaf_sym
extern tb_dec_trace_code_hex
extern tb_dec_trace_nsteps, tb_dec_trace_steps
extern tb_dec_stage_tmp
extern suite_cmd_uci
extern eco_test_print

; ============================================================
; write_str - vypise C-string na stdout
; Vstup: rdi = string, rdx = len
; ============================================================
