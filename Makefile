# ============================================================
# Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
# Vsetky prava vyhradene / All rights reserved.
# ============================================================

# Makefile pre sachovy engine (NASM x86-64 Linux)

TARGET      = chess
TARGET_STATIC = chess-static
SRCDIR      = src
OBJDIR      = obj

SRCS        = main.asm board.asm move.asm position.asm movegen.asm legal.asm io.asm data.asm eval.asm search.asm see.asm hash.asm tt.asm book.asm eco.asm tb.asm nnue.asm uci.asm smp.asm panel.asm fen.asm pgn.asm suite.asm gfx/config.asm gfx/gfx.asm gfx/mouse.asm gfx/sdl.asm

SRCS_STATIC = $(filter-out gfx/sdl.asm,$(SRCS)) gfx/sdl_stub.asm

HAVE_SDL    ?= $(shell if command -v sdl2-config >/dev/null 2>&1; then echo 1; elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists sdl2; then echo 1; else echo 0; fi)

ifeq ($(HAVE_SDL),1)
SRCS_DYNAMIC = $(SRCS)
SDL_LIBS    ?= $(shell if command -v sdl2-config >/dev/null 2>&1; then sdl2-config --libs; else pkg-config --libs sdl2; fi)
else
SRCS_DYNAMIC = $(SRCS_STATIC)
SDL_LIBS    ?=
endif

OBJS        = $(SRCS_DYNAMIC:%.asm=$(OBJDIR)/%.o)
OBJS_STATIC = $(SRCS_STATIC:%.asm=$(OBJDIR)/%.o)

CC          ?= gcc
# Standardny interpreter ak existuje (FHS systemy), inac cesta od gcc (NixOS).
DYN_LINKER  ?= $(shell [ -e /lib64/ld-linux-x86-64.so.2 ] && echo /lib64/ld-linux-x86-64.so.2 || $(CC) -print-file-name=ld-linux-x86-64.so.2)
LDFLAGS_BIN ?= -Wl,--dynamic-linker=$(DYN_LINKER)

NASMFLAGS   = -f elf64 -I $(SRCDIR)/ -DBUILD_DATE=$(BUILD_DATE)
BUILD_DATE := $(shell date +%Y%m%d)
EXTRA_DEFINES ?=
COMMANDS_DEBUG_LOG ?= commands_debug.log
COMMANDS_DEBUG ?= $(shell awk -F= 'tolower($$1) ~ /^[[:space:]]*debug[[:space:]]*$$/ {v=tolower($$2); gsub(/[[:space:]]/,"",v); print (v ~ /^(1|true|yes|on)$$/ ? 1 : 0); found=1; exit} END {if (!found) print 0}' chess.ini 2>/dev/null)
LOG_RUN = COMMANDS_DEBUG=$(COMMANDS_DEBUG) COMMANDS_DEBUG_LOG=$(COMMANDS_DEBUG_LOG) bash tests/tuning/command_debug_run.sh

.PHONY: all clean run test bench bench-report strength-gate roadmap-p0 roadmap-p0-record roadmap-p0-final texel-dataset texel-label texel-fit texel-split texel-pipeline texel-trial texel-batch pawn-hash-study bitboard-tables tb-smoke tb-smoke-matrix tb-verify-3piece syzygy-oracle tb-oracle-compare suite-depth-scan suite-repeat search-ablation-scan lmr-param-sweep commands-log-tail ab-compare ab-compare-report ab-history nightly-pipeline sprt-ab arasan-matchup thread-matrix-ab sprt-threads-matrix rtbz-variants syzygy-tools syzygy-3piece review-pack review-pack-nogate review-findings variant-static variant-rfp0 variant-lmr0 variant-lmp0 variant-null0

all: $(TARGET) $(TARGET_STATIC)

$(TARGET): $(OBJS)
	$(CC) -no-pie -nostartfiles $(OBJS) -o $(TARGET) $(LDFLAGS_BIN) $(SDL_LIBS)

# Staticky text-only build (bez SDL2 ani libc - engine je cisty syscall) -
# spustitelny aj v sandboxoch (GUI engine manager, snap/flatpak), kde chyba
# dynamicky linker/libSDL2. Raw ld namiesto "gcc -static": v nix-shell
# nie je staticka libc a engine ju nepotrebuje.
$(TARGET_STATIC): $(OBJS_STATIC)
	$(LD) -o $(TARGET_STATIC) $(OBJS_STATIC)

$(OBJDIR)/%.o: $(SRCDIR)/%.asm $(SRCDIR)/chess.inc $(SRCDIR)/eval_tune.inc $(SRCDIR)/pst_tune.inc
	@mkdir -p $(dir $@)
	nasm $(NASMFLAGS) $(EXTRA_DEFINES) $< -o $@

# tb.asm includuje dalsie zdrojaky - bez tychto deps sa obj
# po zmene includovanych suborov neprebuildne (stale binary bug).
$(OBJDIR)/tb.o: $(SRCDIR)/tb/core_io.asm $(SRCDIR)/tb/pairs_decode.asm $(SRCDIR)/tb/probe_api.asm \
	$(SRCDIR)/tb/pairs/helpers.asm $(SRCDIR)/tb/pairs/index_encode.asm \
	$(SRCDIR)/tb/pairs/symbol_decode.asm $(SRCDIR)/tb/pairs/wdl_try.asm \
		$(SRCDIR)/tb/pairs/pawnidx.inc \
	$(SRCDIR)/tb/probe/path_helpers.asm $(SRCDIR)/tb/probe/init_load.asm \
	$(SRCDIR)/tb/probe/wdl_probe.asm $(SRCDIR)/tb/probe/dtz_probe.asm $(SRCDIR)/tb/probe/piece_count.asm

# position.asm includuje generovane magics.inc a lookup tabulky
$(OBJDIR)/position.o: $(SRCDIR)/magics.inc $(SRCDIR)/bitboard_tables.inc

clean:
	rm -rf $(OBJDIR) $(TARGET) $(TARGET_STATIC)

run: $(TARGET)
	./$(TARGET)

test: $(TARGET)
	$(LOG_RUN) "bash tests/regression.sh"

strength-gate: $(TARGET_STATIC)
	$(LOG_RUN) "bash utils/strength_gate.sh ./$(TARGET_STATIC)"

bench: $(TARGET_STATIC)
	python3 tools/bench.py --engine ./$(TARGET_STATIC) --depth 10

bench-report: $(TARGET_STATIC)
	bash utils/bench_report.sh ./$(TARGET_STATIC) $(or $(RUNS),3)

roadmap-p0: $(TARGET_STATIC)
	$(LOG_RUN) "bash utils/strength_gate.sh \"$(or $(CANDIDATE),./$(TARGET_STATIC))\""
	$(LOG_RUN) "RUN_TAG=$${RUN_TAG:-p0_$$(date +%Y%m%d_%H%M%S)}; OPENINGS_FILE=$${OPENINGS_FILE:-utils/LumbrasGigaBase_OTB_0001-1899.pgn}; OPENINGS_FORMAT=$${OPENINGS_FORMAT:-pgn}; OPENINGS_ORDER=$${OPENINGS_ORDER:-sequential}; OPENINGS_PLIES=$${OPENINGS_PLIES:-8}; SRAND=$${SRAND:-20260916}; GAMES=$${GAMES:-200}; CONCURRENCY=$${CONCURRENCY:-2}; TC=$${TC:-10+0.1}; HASH_MB=$${HASH_MB:-64}; SPRT=$${SPRT:-elo0=0 elo1=8 alpha=0.05 beta=0.05}; EXECUTE=$${EXECUTE:-0}; PGNOUT=$${PGNOUT:-tests/reports/sprt_$${RUN_TAG}.pgn}; bash utils/sprt_ab_run.sh \"$(or $(CANDIDATE),./$(TARGET_STATIC))\" \"$(or $(BASELINE),./$(TARGET_STATIC))\""

roadmap-p0-record: $(TARGET_STATIC)
	$(LOG_RUN) "bash utils/strength_gate.sh --record-baseline \"$(or $(CANDIDATE),./$(TARGET_STATIC))\""
	$(LOG_RUN) "RUN_TAG=$${RUN_TAG:-p0_$$(date +%Y%m%d_%H%M%S)}; OPENINGS_FILE=$${OPENINGS_FILE:-utils/LumbrasGigaBase_OTB_0001-1899.pgn}; OPENINGS_FORMAT=$${OPENINGS_FORMAT:-pgn}; OPENINGS_ORDER=$${OPENINGS_ORDER:-sequential}; OPENINGS_PLIES=$${OPENINGS_PLIES:-8}; SRAND=$${SRAND:-20260916}; GAMES=$${GAMES:-200}; CONCURRENCY=$${CONCURRENCY:-2}; TC=$${TC:-10+0.1}; HASH_MB=$${HASH_MB:-64}; SPRT=$${SPRT:-elo0=0 elo1=8 alpha=0.05 beta=0.05}; EXECUTE=$${EXECUTE:-0}; PGNOUT=$${PGNOUT:-tests/reports/sprt_$${RUN_TAG}.pgn}; bash utils/sprt_ab_run.sh \"$(or $(CANDIDATE),./$(TARGET_STATIC))\" \"$(or $(BASELINE),./$(TARGET_STATIC))\""

roadmap-p0-final: $(TARGET_STATIC)
	$(MAKE) roadmap-p0 CANDIDATE="$(or $(CANDIDATE),./$(TARGET_STATIC))" BASELINE="$(or $(BASELINE),./$(TARGET_STATIC))"
	$(MAKE) suite-repeat ENGINE="$(or $(CANDIDATE),./$(TARGET_STATIC))" SUITE="$(or $(SUITE),tests/suites/external/arasan2026.epd)" DEPTH="$(or $(DEPTH),6)" RUNS="$(or $(RUNS),3)" TIMEOUT="$(or $(TIMEOUT),900s)" REPORT="$(or $(REPORT),tests/reports/p0_suite_repeat.txt)"
	$(MAKE) tb-smoke-matrix ENGINE="$(or $(CANDIDATE),./$(TARGET_STATIC))" SYZ_PATH="$(or $(SYZ_PATH),tb)" TIMEOUT="$(or $(TB_TIMEOUT),30)" REPORT="$(or $(TB_REPORT),tests/reports/tb_smoke_matrix.txt)"
	$(MAKE) tb-verify-3piece TIMEOUT="$(or $(TB_VERIFY_TIMEOUT),60)" TB_DIR="$(or $(SYZ_PATH),tb)"

texel-dataset:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/texel_prepare.py $(or $(PGN_INPUTS),tests/suites/bf.pgn tests/suites/external/WorldChamp2024.pgn) --out $(or $(OUT),tests/reports/texel_dataset.csv) --skip-plies $(or $(SKIP_PLIES),12) --sample-every $(or $(SAMPLE_EVERY),2) --max-positions $(or $(MAX_POSITIONS),50000)

texel-label: $(TARGET_STATIC)
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/texel_label_eval.py --engine $(or $(ENGINE),./$(TARGET_STATIC)) --input $(or $(IN),tests/reports/texel_dataset.csv) --out $(or $(OUT),tests/reports/texel_labeled.csv) --go "$(or $(GO),depth 1)" --max-rows $(or $(MAX_ROWS),0)

texel-fit:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/texel_fit.py --input $(or $(IN),tests/reports/texel_labeled.csv) --report $(or $(REPORT),tests/reports/texel_fit.txt) --min-scale $(or $(MIN_SCALE),40) --max-scale $(or $(MAX_SCALE),1200) --steps $(or $(STEPS),600) --clip-abs-cp $(or $(CLIP_ABS_CP),2000)

texel-split:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/texel_split_stats.py --input $(or $(IN),tests/reports/texel_dataset.csv) --train-out $(or $(TRAIN_OUT),tests/reports/texel_train.csv) --valid-out $(or $(VALID_OUT),tests/reports/texel_valid.csv) --stats-out $(or $(STATS_OUT),tests/reports/texel_stats.txt) --train-ratio $(or $(TRAIN_RATIO),0.9) --seed $(or $(SEED),20260916) --ply-bucket $(or $(PLY_BUCKET),10)

texel-pipeline: $(TARGET_STATIC)
	$(MAKE) texel-dataset OUT=$(or $(DATASET_OUT),tests/reports/texel_dataset.csv) MAX_POSITIONS=$(or $(MAX_POSITIONS),50000) SKIP_PLIES=$(or $(SKIP_PLIES),12) SAMPLE_EVERY=$(or $(SAMPLE_EVERY),2) PGN_INPUTS="$(or $(PGN_INPUTS),tests/suites/bf.pgn tests/suites/external/WorldChamp2024.pgn)"
	$(MAKE) texel-label ENGINE=$(or $(ENGINE),./$(TARGET_STATIC)) IN=$(or $(DATASET_OUT),tests/reports/texel_dataset.csv) OUT=$(or $(LABELED_OUT),tests/reports/texel_labeled.csv) GO="$(or $(GO),depth 1)" MAX_ROWS=$(or $(MAX_ROWS),0)
	$(MAKE) texel-split IN=$(or $(LABELED_OUT),tests/reports/texel_labeled.csv) TRAIN_OUT=$(or $(TRAIN_OUT),tests/reports/texel_train.csv) VALID_OUT=$(or $(VALID_OUT),tests/reports/texel_valid.csv) STATS_OUT=$(or $(STATS_OUT),tests/reports/texel_stats.txt) TRAIN_RATIO=$(or $(TRAIN_RATIO),0.9) SEED=$(or $(SEED),20260916) PLY_BUCKET=$(or $(PLY_BUCKET),10)
	$(MAKE) texel-fit IN=$(or $(TRAIN_OUT),tests/reports/texel_train.csv) REPORT=$(or $(FIT_REPORT),tests/reports/texel_fit.txt) MIN_SCALE=$(or $(MIN_SCALE),40) MAX_SCALE=$(or $(MAX_SCALE),1200) STEPS=$(or $(STEPS),600) CLIP_ABS_CP=$(or $(CLIP_ABS_CP),2000)

texel-trial:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/texel_trial.py --overrides $(or $(OVERRIDES),tests/tuning/overrides_smoke.env) --eval-tune $(or $(EVAL_TUNE),src/eval_tune.inc) --build-cmd "$(or $(BUILD_CMD),make chess-static)" --gate-cmd "$(or $(GATE_CMD),make roadmap-p0 CANDIDATE=./chess-static BASELINE=./chess-static)" --run-gate $(or $(RUN_GATE),0) --keep-changes $(or $(KEEP_CHANGES),0)

texel-batch:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/texel_batch_trials.py --profiles "$(or $(PROFILES),tests/tuning/overrides/*.env)" --report "$(or $(REPORT),tests/reports/texel_batch_trials.txt)" --csv "$(or $(CSV),)" --run-gate $(or $(RUN_GATE),1) --gate-cmd "$(or $(GATE_CMD),make roadmap-p0 CANDIDATE=./chess-static BASELINE=./chess-static)" --build-cmd "$(or $(BUILD_CMD),make chess-static)" --keep-changes $(or $(KEEP_CHANGES),0) --strict $(or $(STRICT),0)

pawn-hash-study:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/pawn_hash_feasibility.py --input "$(or $(INPUT),tests/suites/external/arasan2026.epd)" --report "$(or $(REPORT),tests/reports/pawn_hash_feasibility.txt)" --top $(or $(TOP),10) --signature $(or $(SIGNATURE),exact)

bitboard-tables:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/generate_bitboard_tables.py --output "$(or $(OUTPUT),src/bitboard_tables.inc)"

tb-smoke: $(TARGET_STATIC)
	$(LOG_RUN) "timeout $(or $(TIMEOUT),30s) sh -c 'printf \"uci\\nsetoption name SyzygyPath value $(or $(SYZ_PATH),tb)\\nposition $(or $(POSITION),startpos)\\ntbtest\\nquit\\n\" | ./$(TARGET_STATIC) --uci' | rg \"tbtest\""

tb-smoke-matrix: $(TARGET_STATIC)
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/tb_smoke_matrix.py --engine "$(or $(ENGINE),./$(TARGET_STATIC))" --syzygy-path "$(or $(SYZ_PATH),tb)" --timeout $(or $(TIMEOUT),30) --report "$(or $(REPORT),tests/reports/tb_smoke_matrix.txt)"

tb-verify-3piece: syzygy-tools
	$(LOG_RUN) "TB_VERIFY_TIMEOUT=$(or $(TIMEOUT),60) bash utils/tb_verify_3piece.sh $(or $(TB_DIR),tb) $(or $(VERIFIER),tb/syzygy-tb/src/rtbver_local) $(or $(PAWN_VERIFIER),tb/syzygy-tb/src/rtbverp_local)"

syzygy-oracle:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" utils/syzygy_oracle.py --syzygy-path "$(or $(SYZ_PATH),tb)" --fen "$(or $(FEN),8/8/8/8/8/8/4K3/k6Q w - - 0 1)"

tb-oracle-compare: $(TARGET_STATIC)
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/tb_oracle_compare.py --engine "$(or $(ENGINE),./$(TARGET_STATIC))" --syzygy-path "$(or $(SYZ_PATH),tb)" --python "$$PYBIN" --timeout $(or $(TIMEOUT),20) $(if $(CASES),--cases-file "$(CASES)")

suite-depth-scan: $(TARGET_STATIC)
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/suite_depth_scan.py --engine "$(or $(ENGINE),./$(TARGET_STATIC))" --suite "$(or $(SUITE),tests/suites/external/arasan2026.epd)" --depths "$(or $(DEPTHS),4,5,6,7,8)" --timeout "$(or $(TIMEOUT),1200s)" --report "$(or $(REPORT),tests/reports/suite_depth_scan.txt)"

suite-repeat: $(TARGET_STATIC)
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/suite_repeat.py --engine "$(or $(ENGINE),./$(TARGET_STATIC))" --suite "$(or $(SUITE),tests/suites/external/arasan2026.epd)" --depth $(or $(DEPTH),6) --runs $(or $(RUNS),5) --timeout "$(or $(TIMEOUT),900s)" --report "$(or $(REPORT),tests/reports/suite_repeat.txt)"

search-ablation-scan:
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	$(LOG_RUN) "$$PYBIN" tests/tuning/search_ablation_scan.py --suite "$(or $(SUITE),tests/suites/external/arasan2026.epd)" --depths "$(or $(DEPTHS),6,8)" --heuristics "$(or $(HEURISTICS),LMR,NULL,LMP,RFP)" --timeout "$(or $(TIMEOUT),900s)" --report "$(or $(REPORT),tests/reports/search_ablation_scan.txt)"

lmr-lmp-rfp-scan: $(TARGET_STATIC)
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	if [[ -n "$(MOVETIME)" ]]; then \
	  $(LOG_RUN) "$$PYBIN" tests/tuning/lmr_lmp_rfp_scan.py --suite "$(or $(SUITE),tests/suites/external/arasan2026.epd)" --movetime "$(MOVETIME)" --timeout "$(or $(TIMEOUT),1800s)" --report "$(or $(REPORT),tests/reports/lmr_lmp_rfp_scan.txt)" --csv "$(or $(CSV),tests/reports/lmr_lmp_rfp_scan.csv)"; \
	else \
	  $(LOG_RUN) "$$PYBIN" tests/tuning/lmr_lmp_rfp_scan.py --suite "$(or $(SUITE),tests/suites/external/arasan2026.epd)" --depths "$(or $(DEPTHS),6,8)" --timeout "$(or $(TIMEOUT),900s)" --report "$(or $(REPORT),tests/reports/lmr_lmp_rfp_scan.txt)" --csv "$(or $(CSV),tests/reports/lmr_lmp_rfp_scan.csv)"; \
	fi

lmr-param-sweep: $(TARGET_STATIC)
	@PYBIN="$(or $(TUNE_PYTHON),python3)"; \
	if [[ -x tests/tuning/.venv/bin/python && "$$PYBIN" == "python3" ]]; then PYBIN="tests/tuning/.venv/bin/python"; fi; \
	LMR_IDX_ARG=""; if [[ -n "$(LMR_INDEX_MIN)" ]]; then LMR_IDX_ARG="--lmr-index-min \"$(LMR_INDEX_MIN)\""; fi; \
	LMR_DEP_ARG=""; if [[ -n "$(LMR_DEPTH_MIN)" ]]; then LMR_DEP_ARG="--lmr-depth-min \"$(LMR_DEPTH_MIN)\""; fi; \
	LMR_BASE_ARG=""; if [[ -n "$(LMR_BASE_REDUCTION)" ]]; then LMR_BASE_ARG="--lmr-base-reduction \"$(LMR_BASE_REDUCTION)\""; fi; \
	LMR_NIMP_ARG=""; if [[ -n "$(LMR_EXTRA_NON_IMPROVING)" ]]; then LMR_NIMP_ARG="--lmr-extra-non-improving \"$(LMR_EXTRA_NON_IMPROVING)\""; fi; \
	if [[ -n "$(MOVETIME)" ]]; then \
	  $(LOG_RUN) "$$PYBIN" tests/tuning/lmr_lmp_rfp_scan.py --lmr-param-sweep --suite "$(or $(SUITE),tests/suites/external/arasan2026.epd)" --movetime "$(MOVETIME)" --timeout "$(or $(TIMEOUT),1800s)" $$LMR_IDX_ARG $$LMR_DEP_ARG $$LMR_BASE_ARG $$LMR_NIMP_ARG --lmp "$(or $(LMP),1)" --rfp "$(or $(RFP),1)" --report "$(or $(REPORT),tests/reports/lmr_param_sweep.txt)" --csv "$(or $(CSV),tests/reports/lmr_param_sweep.csv)"; \
	else \
	  $(LOG_RUN) "$$PYBIN" tests/tuning/lmr_lmp_rfp_scan.py --lmr-param-sweep --suite "$(or $(SUITE),tests/suites/external/arasan2026.epd)" --depths "$(or $(DEPTHS),6,8)" --timeout "$(or $(TIMEOUT),900s)" $$LMR_IDX_ARG $$LMR_DEP_ARG $$LMR_BASE_ARG $$LMR_NIMP_ARG --lmp "$(or $(LMP),1)" --rfp "$(or $(RFP),1)" --report "$(or $(REPORT),tests/reports/lmr_param_sweep.txt)" --csv "$(or $(CSV),tests/reports/lmr_param_sweep.csv)"; \
	fi

commands-log-tail:
	@if [[ ! -f "$(COMMANDS_DEBUG_LOG)" ]]; then echo "log file not found: $(COMMANDS_DEBUG_LOG)"; exit 1; fi
	tail -n $(or $(N),50) "$(COMMANDS_DEBUG_LOG)"

ab-compare:
	@if [ -z "$(CANDIDATE)" ]; then echo "Usage: make ab-compare CANDIDATE=./candidate [BASELINE=./chess-static]"; exit 2; fi
	$(LOG_RUN) "CAND_THREADS=$(or $(CAND_THREADS),1) BASE_THREADS=$(or $(BASE_THREADS),1) bash utils/ab_compare.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""

ab-compare-report:
	@if [ -z "$(CANDIDATE)" ]; then echo "Usage: make ab-compare-report CANDIDATE=./candidate [BASELINE=./chess-static]"; exit 2; fi
	$(LOG_RUN) "CAND_THREADS=$(or $(CAND_THREADS),1) BASE_THREADS=$(or $(BASE_THREADS),1) REPORT_TSV=tests/reports/ab_history.tsv REPORT_MD=tests/reports/ab_latest.md bash utils/ab_compare.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""

ab-history:
	$(LOG_RUN) "bash utils/ab_history_tail.sh tests/reports/ab_history.tsv $(or $(N),10)"

# Build statickej kandidatnej binarky s vlastnymi NASM definiciami.
# Priklad: make variant-static OUT=chess-static-rfp0 DEFINES='-DENABLE_RFP=0'
variant-static:
	@if [ -z "$(OUT)" ]; then echo "Usage: make variant-static OUT=./candidate DEFINES='-DENABLE_RFP=0' [OBJDIR_VARIANT=obj/candidate]"; exit 2; fi
	$(MAKE) TARGET_STATIC="$(OUT)" OBJDIR="$(or $(OBJDIR_VARIANT),obj/$(OUT))" EXTRA_DEFINES="$(DEFINES)" "$(OUT)"

variant-rfp0:
	$(MAKE) variant-static OUT=chess-static-rfp0 DEFINES='-DENABLE_RFP=0'

variant-lmr0:
	$(MAKE) variant-static OUT=chess-static-lmr0 DEFINES='-DENABLE_LMR=0'

variant-lmp0:
	$(MAKE) variant-static OUT=chess-static-lmp0 DEFINES='-DENABLE_LMP=0'

variant-null0:
	$(MAKE) variant-static OUT=chess-static-null0 DEFINES='-DENABLE_NULL_PRUNE=0'

nightly-pipeline:
	@if [ -z "$(CANDIDATE)" ]; then echo "Usage: make nightly-pipeline CANDIDATE=./candidate [BASELINE=./chess-static] [ARASAN_MATCHUP=1]"; exit 2; fi
	$(LOG_RUN) "ARASAN_MATCHUP='$(or $(ARASAN_MATCHUP),0)' MATCHUP_GAMES='$(or $(MATCHUP_GAMES),100)' MATCHUP_TC='$(or $(MATCHUP_TC),10+0.1)' bash utils/nightly_pipeline.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""

# Pravidelne meranie sily: chess-static vs Arasan 26 (dlhe - default mimo nightly).
arasan-matchup: $(TARGET_STATIC)
	$(LOG_RUN) "bash utils/arasan_matchup.sh \"$(or $(GAMES),100)\" \"$(or $(TC),10+0.1)\""

sprt-ab:
	@if [ -z "$(CANDIDATE)" ]; then echo "Usage: make sprt-ab CANDIDATE=./candidate [BASELINE=./chess-static] [EXECUTE=1]"; exit 2; fi
	$(LOG_RUN) "bash utils/sprt_ab_run.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""

thread-matrix-ab:
	@if [ -z "$(CANDIDATE)" ]; then echo "Usage: make thread-matrix-ab CANDIDATE=./candidate [BASELINE=./chess-static]"; exit 2; fi
	$(LOG_RUN) "echo \"=== AB Threads 1 ===\"; CAND_THREADS=1 BASE_THREADS=1 BF_DEPTH=$(or $(BF_DEPTH),14) ARASAN_DEPTH=$(or $(ARASAN_DEPTH),6) bash utils/ab_compare.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""
	$(LOG_RUN) "echo \"=== AB Threads 2 ===\"; CAND_THREADS=2 BASE_THREADS=2 BF_DEPTH=$(or $(BF_DEPTH),14) ARASAN_DEPTH=$(or $(ARASAN_DEPTH),6) bash utils/ab_compare.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""
	$(LOG_RUN) "echo \"=== AB Threads 4 ===\"; CAND_THREADS=4 BASE_THREADS=4 BF_DEPTH=$(or $(BF_DEPTH),14) ARASAN_DEPTH=$(or $(ARASAN_DEPTH),6) bash utils/ab_compare.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""

sprt-threads-matrix:
	@if [ -z "$(CANDIDATE)" ]; then echo "Usage: make sprt-threads-matrix CANDIDATE=./candidate [BASELINE=./chess-static] [EXECUTE=1]"; exit 2; fi
	$(LOG_RUN) "echo \"=== SPRT Threads 1 ===\"; RUN_TAG=$${RUN_TAG:-threads_1_$$(date +%Y%m%d_%H%M%S)} NEW_THREADS=1 BASE_THREADS=1 EXECUTE=$(or $(EXECUTE),0) bash utils/sprt_ab_run.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""
	$(LOG_RUN) "echo \"=== SPRT Threads 2 ===\"; RUN_TAG=$${RUN_TAG:-threads_2_$$(date +%Y%m%d_%H%M%S)} NEW_THREADS=2 BASE_THREADS=2 EXECUTE=$(or $(EXECUTE),0) bash utils/sprt_ab_run.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""
	$(LOG_RUN) "echo \"=== SPRT Threads 4 ===\"; RUN_TAG=$${RUN_TAG:-threads_4_$$(date +%Y%m%d_%H%M%S)} NEW_THREADS=4 BASE_THREADS=4 EXECUTE=$(or $(EXECUTE),0) bash utils/sprt_ab_run.sh \"$(CANDIDATE)\" \"$(or $(BASELINE),./chess-static)\""

review-pack:
	bash utils/review_bundle.sh "$(or $(COMMIT),HEAD)"

review-pack-nogate:
	RUN_GATE=0 bash utils/review_bundle.sh "$(or $(COMMIT),HEAD)"

review-findings:
	@if [ ! -f tests/reports/reviewer/latest/findings.md ]; then echo "Findings nenajdene: tests/reports/reviewer/latest/findings.md (najprv: make review-pack)"; exit 1; fi
	@cat tests/reports/reviewer/latest/findings.md

rtbz-variants:
	@if [ -n "$(GENERATOR)" ]; then \
		if [ -z "$(OUTPUT_DIR)" ]; then echo "Usage: make rtbz-variants GENERATOR='...' OUTPUT_DIR=... [MAX_PIECES=5] [SIDED=single|all] [SHOW=both|canonical|alias] [BEST_OUTPUT=...] [REPORT=...] [VARIANTS=...]"; exit 2; fi; \
		python3 utils/rtbz_variants.py --max-pieces $(or $(MAX_PIECES),5) --sided $(or $(SIDED),single) --show $(or $(SHOW),both) --generator "$(GENERATOR)" --output-dir "$(OUTPUT_DIR)" $(if $(BEST_OUTPUT),--best-output "$(BEST_OUTPUT)") $(if $(REPORT),--report "$(REPORT)") $(if $(VARIANTS),--variants "$(VARIANTS)"); \
	else \
		python3 utils/rtbz_variants.py --max-pieces $(or $(MAX_PIECES),5) --sided $(or $(SIDED),single) --show $(or $(SHOW),both) $(if $(VARIANTS),--variants "$(VARIANTS)"); \
	fi

syzygy-tools:
	@echo "Building syzygy1/tb generator tools (portable flags)..."
	@if [ ! -d tb/syzygy-tb ]; then git clone --depth 1 https://github.com/syzygy1/tb tb/syzygy-tb; fi
	@cd tb/syzygy-tb/src && \
	  make clean >/dev/null 2>&1 || true; \
	  make FLAGS='-DMAGIC -DUSE_POPCNT -DTBPIECES=7 -DCOMPRESSION_THREADS=2 -DREGULAR' \
	       LDFLAGS='' \
	       CFLAGS='-O3 -pipe -D_GNU_SOURCE -Wall -std=c11' \
	       -f Makefile.regular -j$$(nproc) rtbgen rtbgenp tbcheck; \
	  make FLAGS='-DMAGIC -DUSE_POPCNT -DTBPIECES=7 -DCOMPRESSION_THREADS=2 -DREGULAR' \
	       LDFLAGS='' \
	       CFLAGS='-O3 -pipe -D_GNU_SOURCE -Wall -std=c11' \
	       -f Makefile.regular -j$$(nproc) objsr/tbver.o objsr/tbverp.o objsr/decompress.o; \
	  cc -O3 -pipe -D_GNU_SOURCE -Wall -std=c11 -o rtbver_local \
	       objsr/tbver.o objsr/decompress.o objsr/threads.o objsr/checksum.o objsr/city-c.o objsr/util.o objsr/lz4.o; \
	  cc -O3 -pipe -D_GNU_SOURCE -Wall -std=c11 -o rtbverp_local \
	       objsr/tbverp.o objsr/decompress.o objsr/threads.o objsr/checksum.o objsr/city-c.o objsr/util.o objsr/lz4.o; \
	  cd $(CURDIR) && bash utils/syzygy_alias_links.sh tb

syzygy-3piece: syzygy-tools
	@echo "Generating real 3-piece Syzygy tables into tb/*.rtbw and tb/*.rtbz ..."
	@TBGEN='cd $(CURDIR)/tb && export RTBPATH=$(CURDIR)/tb && case "{canonical}" in *P*) $(CURDIR)/tb/syzygy-tb/src/rtbgenp {canonical} ;; *) $(CURDIR)/tb/syzygy-tb/src/rtbgen {canonical} ;; esac' \
	  bash tb/generate_3piece.sh

syzygy-4piece: syzygy-tools
	@echo "Generating real 4-piece pawnless Syzygy tables into tb/*.rtbw and tb/*.rtbz ..."
	@bash tb/generate_4piece.sh