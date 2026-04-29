# =============================================================================
#  LSD Simulation Makefile  (Questasim / Questa One Sim)  -  UVM-FREE
# -----------------------------------------------------------------------------
#  Phase 3 design (no UVM, no auto-generated bloat farms):
#  - tb_top is plain SystemVerilog and exposes the DUT only as (clk, rst_n).
#  - lsd_top instantiates 5 functional islands (cnn / crypto / gfx / calu /
#    eccd) and 8 heavy-compute islands.  Each island is atomic — the
#    partitioner can place it but cannot split it — and external signals
#    are limited to clk/rst_n, keeping ParallelSim Field-of-Use clean.
#  - Per-cycle work comes from lsd_heavy_compute (memory + 256-bit MAC),
#    which qopt cannot strength-reduce.  The previous bloat-farm gen tools
#    (8 Python scripts × thousands of unique modules) have been retired.
#
#  Workload targets (functional)
#    smokesim          quick sanity (5 us, light traffic)
#    balanced          equal load across all 5 subsystems (50 us)
#    streaming         streams maxed, cmds light                 (50 us)
#    command_storm     cmd ports maxed, streams light            (20 us)
#    crypto_heavy      crypto dominates (Amdahl bound test)      (50 us)
#    cnn_heavy         cnn dominates                             (50 us)
#    eccd_only         all other subsystems disabled             (10 us)
#    stress            everything maxed, long run (1 ms)         — psim baseline
#
#  ParallelSim flow (qsim only)
#    qual              run profiler+flps qualifier (defaults to stress)
#    qfbk              optional feedback run (defaults to stress)
#    psim FLPS=N       parallel run with N partitions (defaults to stress)
#    uni               single-core baseline (defaults to stress)
#    Override workload: make qual WORKLOAD=balanced (or any target name above)
#
#  Misc
#    clean             remove build artifacts
#    info              print current knob values
#
#  Knobs (override at CLI, e.g.  make stress ENGINE=qsim FLPS=3)
#    ENGINE       vsim | qsim | qrun           default: vsim
#    DEBUG        wlf | vis | off              default: vis
#                   wlf : vsim-only +acc=npr + .wlf
#                   vis : Visualizer (qwavedb + design.bin)
#                   off : NO wave dump — used automatically by qual/qfbk/
#                         psim/uni for measurement (wave logging was 60%
#                         of wall time on stress and capped psim speedup)
#    RUN          "-all" | "1 us" | …          default: -all (sim ends on $finish)
#    SEED         <int>                        default: 1
#    HEARTBEAT    ns between progress prints   default: 10000
#    WORKLOAD     test profile name (see above) default: stress (used by qual/etc.)
#    WORKLOAD_ARGS direct plusarg list          default: derived from WORKLOAD
#    FLPS         ParallelSim partitions       default: (unset; required for psim)
#    FBK_FDB      qsim.fdb for feedback flow   default: newest fprofile/*.fdb
#    QOPT_EXTRA   appended to QOPT_FLAGS       default: empty
#    QSIM_EXTRA   appended to QSIM_FLAGS       default: empty
#    QSIM_LOG     qsim transcript filename     default: qsim.log
# =============================================================================

# -----------------------------------------------------------------------------
# Knobs — overridable on the command line (see header for descriptions)
# -----------------------------------------------------------------------------
ENGINE      ?= vsim
RUN         ?= -all
DEBUG       ?= vis
SEED        ?= 1
HEARTBEAT   ?= 10000

# Workload selector for qual / qfbk / psim / uni.  WORKLOAD_ARGS, if set
# directly, takes precedence over the named WORKLOAD profile.
WORKLOAD       ?= stress
WORKLOAD_ARGS  ?=

# ParallelSim (qsim only) — see "ParallelSim flow" in the header.
FLPS        ?=
FBK_FDB     ?= $(shell ls -t fprofile/*.fdb 2>/dev/null | head -1)
QOPT_EXTRA  ?=
QSIM_EXTRA  ?=
QSIM_LOG    ?= qsim.log

# Only vsim supports the classic WLF debug flow; qsim/qrun reject it.
ifneq ($(ENGINE),vsim)
    ifeq ($(DEBUG),wlf)
        $(warning [Makefile] DEBUG=wlf is not supported for ENGINE=$(ENGINE); overriding to vis)
        override DEBUG = vis
    endif
endif

# DEBUG default for measurement targets (qual / qfbk / psim / uni).
#   - If the user passed DEBUG=... on the command line, respect it.
#   - Otherwise, force `off` so wave dumping doesn't dominate wall time.
#     (Wave logging was 60% of wall in earlier stress runs and is master-
#      serialised, so it caps any ParallelSim speedup at < 2x.)
ifeq ($(origin DEBUG),command line)
    MEASURE_DEBUG := $(DEBUG)
else
    MEASURE_DEBUG := off
endif

# -----------------------------------------------------------------------------
# Phase 3 RTL layout
#
#   Five functional subsystem islands  (rtl/top/lsd_subsys_islands.sv)
#     - lsd_cnn_island, lsd_crypto_island, lsd_gfx_island,
#       lsd_calu_island, lsd_eccd_island
#     - Each owns an internal lsd_self_traffic + the matching DUT block.
#
#   Eight heavy-compute islands         (rtl/top/lsd_compute_islands.sv)
#     - lsd_compute0_island .. lsd_compute7_island, each instantiating
#       lsd_heavy_compute (rtl/common/lsd_heavy_compute.sv) with a unique
#       SEED.  These replace the previous file-multiplying bloat farms,
#       which qopt -O5 reduced to ~0% per-cycle work.  The new compute
#       engine does real memory + 256-bit multiplication every cycle and
#       qopt cannot strength-reduce it.
#
#   13 islands total + tb_top live inside the partitioner.  Every island
#   exposes only (clk, rst_n) so the partitioner sees them as atomic.
# -----------------------------------------------------------------------------

# --- File lists and libraries
RTL_FL      = rtl_filelist.f
TB_FL       = tb_filelist.f
WORKLIB     = work

# --- Compile flags  (no UVM library, no UVM defines)
VLOG_FLAGS    = -sv -mfcu -timescale=1ns/1ps \
                -suppress 2583 -suppress 13314 -suppress 13288
VLOG_TB_FLAGS = $(VLOG_FLAGS)

# --- Debug-mode-specific vopt / vsim flags
#
#  DEBUG=vis  : qwavedb + design.bin   (Visualizer-friendly, default for
#               functional runs)
#  DEBUG=wlf  : +acc=npr + .wlf        (vsim-only legacy waveform)
#  DEBUG=off  : NO wave dump, NO -debug, NO +designfile.  Use this for
#               *measurement* runs (qual / qfbk / psim / uni) — wave
#               dumping is master-serialised and was eating ~60% of wall
#               time on stress profiles, masking any ParallelSim gain.
#
# The ParallelSim flow targets below set DEBUG=off automatically; override
# with DEBUG=vis on the command line if you also want a qwavedb during a
# measurement run.
ifeq ($(DEBUG),wlf)
    VOPT_DBG_FLAGS = +acc=npr
    VSIM_DBG_FLAGS = -wlf vsim.wlf
    QOPT_DBG_FLAGS = $(error DEBUG=wlf is not supported for ENGINE=qsim)
    QSIM_DBG_FLAGS = $(error DEBUG=wlf is not supported for ENGINE=qsim)
else ifeq ($(DEBUG),vis)
    # Visualizer: vopt emits design.bin; vsim records qwavedb.
    # NOTE: +acc is NOT permitted alongside -debug +designfile.
    VOPT_DBG_FLAGS = -debug +designfile
    VSIM_DBG_FLAGS = -qwavedb=+signal
    QOPT_DBG_FLAGS = -debug +designfile
    QSIM_DBG_FLAGS = -qwavedb=+signal
else ifeq ($(DEBUG),off)
    VOPT_DBG_FLAGS =
    VSIM_DBG_FLAGS =
    QOPT_DBG_FLAGS =
    QSIM_DBG_FLAGS =
else
    $(error Unknown DEBUG=$(DEBUG) - valid: wlf | vis | off)
endif

# -----------------------------------------------------------------------------
# Workload profiles — plusargs read once at time 0 by lsd_self_traffic.
#
# Per-instance plusarg names (INST_TAG ∈ cnn / crypto / gfx / calu / eccd):
#   +<TAG>_cmd_period=<int>   cycles between cmd issuances (>=1)
#   +<TAG>_str_period=<int>   cycles between stream beats  (>=1)
#   +<TAG>_disable=<0|1>      mute this island entirely
#
# Top-level run length:
#   +run_ns=<int>             tb_top calls $finish after this many ns
# -----------------------------------------------------------------------------

# Quick sanity — light traffic, short run.
SMOKE_ARGS = \
    +run_ns=5000 \
    +cnn_cmd_period=8    +cnn_str_period=4 \
    +crypto_cmd_period=8 +crypto_str_period=4 \
    +gfx_cmd_period=8    +gfx_str_period=4 \
    +calu_cmd_period=8   +calu_str_period=4 \
    +eccd_cmd_period=8   +eccd_str_period=4

# Equal load across all 5 subsystems — the geometry ParallelSim *should* like.
BALANCED_ARGS = \
    +run_ns=50000 \
    +cnn_cmd_period=4    +cnn_str_period=1 \
    +crypto_cmd_period=4 +crypto_str_period=1 \
    +gfx_cmd_period=4    +gfx_str_period=1 \
    +calu_cmd_period=4   +calu_str_period=1 \
    +eccd_cmd_period=4   +eccd_str_period=1

# Streams maxed, cmd ports quiet — exercise data-paths.
STREAMING_ARGS = \
    +run_ns=50000 \
    +cnn_cmd_period=16    +cnn_str_period=1 \
    +crypto_cmd_period=16 +crypto_str_period=1 \
    +gfx_cmd_period=16    +gfx_str_period=1 \
    +calu_cmd_period=16   +calu_str_period=1 \
    +eccd_cmd_period=16   +eccd_str_period=1

# Cmd ports maxed, streams quiet — exercise control-paths.
COMMAND_STORM_ARGS = \
    +run_ns=20000 \
    +cnn_cmd_period=1    +cnn_str_period=16 \
    +crypto_cmd_period=1 +crypto_str_period=16 \
    +gfx_cmd_period=1    +gfx_str_period=16 \
    +calu_cmd_period=1   +calu_str_period=16 \
    +eccd_cmd_period=1   +eccd_str_period=16

# One block dominates — Amdahl bound (psim should win less here).
CRYPTO_HEAVY_ARGS = \
    +run_ns=50000 \
    +cnn_cmd_period=32    +cnn_str_period=8 \
    +crypto_cmd_period=1  +crypto_str_period=1 \
    +gfx_cmd_period=32    +gfx_str_period=8 \
    +calu_cmd_period=32   +calu_str_period=8 \
    +eccd_cmd_period=32   +eccd_str_period=8

CNN_HEAVY_ARGS = \
    +run_ns=50000 \
    +cnn_cmd_period=1     +cnn_str_period=1 \
    +crypto_cmd_period=32 +crypto_str_period=8 \
    +gfx_cmd_period=32    +gfx_str_period=8 \
    +calu_cmd_period=32   +calu_str_period=8 \
    +eccd_cmd_period=32   +eccd_str_period=8

# Single-island run — others muted.  Useful for partition-isolation experiments.
ECCD_ONLY_ARGS = \
    +run_ns=10000 \
    +cnn_disable=1 +crypto_disable=1 +gfx_disable=1 +calu_disable=1 \
    +eccd_cmd_period=2 +eccd_str_period=1

# Long, full-bore run — qual / psim measurement baseline.
# 1 ms HDL is chosen so per-process startup overhead (~2 s) is a small
# fraction of total wall: with 4-core ParallelSim each partition sees
# ~5-10 s of actual sim work, large enough for FLPS=3 to amortise its
# fork/IPC cost and demonstrate measurable speedup.
STRESS_ARGS = \
    +run_ns=1000000 \
    +cnn_cmd_period=2    +cnn_str_period=1 \
    +crypto_cmd_period=2 +crypto_str_period=1 \
    +gfx_cmd_period=2    +gfx_str_period=1 \
    +calu_cmd_period=2   +calu_str_period=1 \
    +eccd_cmd_period=2   +eccd_str_period=1

# Resolve WORKLOAD → plusarg list for measurement targets.  WORKLOAD_ARGS
# (if user-set directly) wins.
ifeq ($(strip $(WORKLOAD_ARGS)),)
  ifeq ($(WORKLOAD),smoke)
    WORKLOAD_ARGS := $(SMOKE_ARGS)
  else ifeq ($(WORKLOAD),balanced)
    WORKLOAD_ARGS := $(BALANCED_ARGS)
  else ifeq ($(WORKLOAD),streaming)
    WORKLOAD_ARGS := $(STREAMING_ARGS)
  else ifeq ($(WORKLOAD),command_storm)
    WORKLOAD_ARGS := $(COMMAND_STORM_ARGS)
  else ifeq ($(WORKLOAD),crypto_heavy)
    WORKLOAD_ARGS := $(CRYPTO_HEAVY_ARGS)
  else ifeq ($(WORKLOAD),cnn_heavy)
    WORKLOAD_ARGS := $(CNN_HEAVY_ARGS)
  else ifeq ($(WORKLOAD),eccd_only)
    WORKLOAD_ARGS := $(ECCD_ONLY_ARGS)
  else ifeq ($(WORKLOAD),stress)
    WORKLOAD_ARGS := $(STRESS_ARGS)
  else
    $(error Unknown WORKLOAD=$(WORKLOAD) - valid: smoke balanced streaming command_storm crypto_heavy cnn_heavy eccd_only stress)
  endif
endif

# Plusargs supplied to a single run.  Per-target recipes set TEST_PLUSARGS.
TEST_PLUSARGS ?=

# --- Aggregated per-tool flags
VOPT_FLAGS  = $(VOPT_DBG_FLAGS)
QOPT_FLAGS  = $(QOPT_DBG_FLAGS) $(QOPT_EXTRA)

VSIM_FLAGS  = -batch -l vsim.log -do "run $(RUN); quit" \
              -sv_seed $(SEED) +heartbeat=$(HEARTBEAT) $(TEST_PLUSARGS) \
              $(VSIM_DBG_FLAGS)

QSIM_FLAGS  = -batch -l $(QSIM_LOG) -do "run $(RUN); quit" \
              -sv_seed $(SEED) +heartbeat=$(HEARTBEAT) $(TEST_PLUSARGS) \
              $(QSIM_DBG_FLAGS) $(QSIM_EXTRA)

# qrun: 1-step flow (vlog + vopt + vsim), Visualizer-native.
QRUN_FLAGS  = -sv -mfcu -timescale=1ns/1ps \
              -suppress 2583 -suppress 13314 -suppress 13288 \
              -debug +designfile -qwavedb=+signal \
              -batch -l qrun.log -do "run $(RUN); quit" \
              -sv_seed $(SEED) +heartbeat=$(HEARTBEAT) $(TEST_PLUSARGS) \
              -f $(RTL_FL) -f $(TB_FL) -top tb_top

# =============================================================================
.PHONY: all sim smokesim balanced streaming command_storm crypto_heavy cnn_heavy \
        eccd_only stress qual qfbk psim uni qual_gui clean \
        workdir compile optimize run run_vsim run_qsim run_qrun info

all: smokesim

workdir:
	@if [ ! -d $(WORKLIB) ]; then vlib $(WORKLIB); vmap $(WORKLIB) $(WORKLIB); fi

# --- Compile (vlog) — shared by the vsim and qsim engines.
#     Phase 3 dropped the auto-generated bloat farms.  All RTL is now
#     hand-written / stable, so there is no `gen` step.
compile: workdir
	vlog $(VLOG_FLAGS)    -f $(RTL_FL) -l vlog.log
	vlog $(VLOG_TB_FLAGS) -f $(TB_FL)  -l vlog_tb.log

# --- Optimize (vopt / qopt) — no-op for qrun (qrun does it internally)
optimize: compile
ifeq ($(ENGINE),vsim)
	vopt $(VOPT_FLAGS) tb_top -o tb_top_opt -l vopt.log
else ifeq ($(ENGINE),qsim)
	qopt $(QOPT_FLAGS) tb_top -o tb_top_opt -l qopt.log
endif

# --- Run — dispatches to the selected engine.
run:
ifeq ($(ENGINE),vsim)
	$(MAKE) run_vsim
else ifeq ($(ENGINE),qsim)
	$(MAKE) run_qsim
else ifeq ($(ENGINE),qrun)
	$(MAKE) run_qrun
else
	$(error Unknown ENGINE=$(ENGINE) - valid: vsim | qsim | qrun)
endif

run_vsim: optimize
	vsim $(VSIM_FLAGS) tb_top_opt

run_qsim: optimize
	qsim $(QSIM_FLAGS) tb_top_opt

run_qrun:
	qrun $(QRUN_FLAGS)

# -----------------------------------------------------------------------------
# Per-workload functional targets — each picks a different traffic profile.
# Re-uses one compile via TEST_PLUSARGS; no recompile per profile.
# -----------------------------------------------------------------------------
sim:           stress

smokesim:
	$(MAKE) run TEST_PLUSARGS="$(SMOKE_ARGS)" \
	    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

balanced:
	$(MAKE) run TEST_PLUSARGS="$(BALANCED_ARGS)" \
	    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

streaming:
	$(MAKE) run TEST_PLUSARGS="$(STREAMING_ARGS)" \
	    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

command_storm:
	$(MAKE) run TEST_PLUSARGS="$(COMMAND_STORM_ARGS)" \
	    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

crypto_heavy:
	$(MAKE) run TEST_PLUSARGS="$(CRYPTO_HEAVY_ARGS)" \
	    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

cnn_heavy:
	$(MAKE) run TEST_PLUSARGS="$(CNN_HEAVY_ARGS)" \
	    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

eccd_only:
	$(MAKE) run TEST_PLUSARGS="$(ECCD_ONLY_ARGS)" \
	    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

stress:
	$(MAKE) run TEST_PLUSARGS="$(STRESS_ARGS)" \
	    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

# -----------------------------------------------------------------------------
# ParallelSim measurement flow (qsim only)
#   The default workload is `stress`; override with WORKLOAD=<name> or
#   WORKLOAD_ARGS="+...".
# -----------------------------------------------------------------------------
qual:
	$(MAKE) run TEST_PLUSARGS="$(WORKLOAD_ARGS)" \
	    ENGINE=qsim DEBUG=$(MEASURE_DEBUG) RUN="$(RUN)" \
	    QOPT_EXTRA="-fprofile+flps" QSIM_EXTRA="-fprofile+flps" \
	    QSIM_LOG=qsim_qual.log

qfbk:
	@if [ -z "$(FBK_FDB)" ]; then \
	    echo "[Makefile] FBK_FDB empty and no fprofile/*.fdb found - run 'make qual' first"; \
	    exit 1; \
	fi
	$(MAKE) run TEST_PLUSARGS="$(WORKLOAD_ARGS)" \
	    ENGINE=qsim DEBUG=$(MEASURE_DEBUG) RUN="$(RUN)" \
	    QOPT_EXTRA="-fprofile+flps -flpsfprof=$(FBK_FDB)" \
	    QSIM_EXTRA="-fprofile+flps" \
	    QSIM_LOG=qsim_qfbk.log

psim:
	@if [ -z "$(FLPS)" ]; then \
	    echo "[Makefile] FLPS is required (e.g. make psim FLPS=3) - run 'make qual' to find N"; \
	    exit 1; \
	fi
	$(MAKE) run TEST_PLUSARGS="$(WORKLOAD_ARGS)" \
	    ENGINE=qsim DEBUG=$(MEASURE_DEBUG) RUN="$(RUN)" \
	    QOPT_EXTRA="-flps=$(FLPS)$(if $(FBK_FDB), -flpsfprof=$(FBK_FDB))" \
	    QSIM_EXTRA="-flps" \
	    QSIM_LOG=qsimparallelsim.log

uni:
	$(MAKE) run TEST_PLUSARGS="$(WORKLOAD_ARGS)" \
	    ENGINE=qsim DEBUG=$(MEASURE_DEBUG) RUN="$(RUN)" \
	    QSIM_LOG=qsimuni.log

qual_gui:
	qsim -fprofile+flps &

clean:
	rm -rf $(WORKLIB) transcript vsim.wlf tb.vcd design.bin \
	       *.db *.log modelsim.ini .vscode \
	       tb_top_opt covhtmlreport qrun.out *.xml \
		   fprofile *.part 
	@echo "Clean complete"

# Single-quoted echoes keep flag strings literal. $(VSIM_FLAGS) contains
# `-do "run $(RUN); quit"`, whose embedded " and ; would otherwise break
# out of a double-quoted echo and fail at the shell.
info:
	@echo 'ENGINE        = $(ENGINE)'
	@echo 'DEBUG         = $(DEBUG)'
	@echo 'MEASURE_DEBUG = $(MEASURE_DEBUG)   (used by qual/qfbk/psim/uni)'
	@echo 'SEED          = $(SEED)'
	@echo 'HEARTBEAT     = $(HEARTBEAT) ns'
	@echo 'RUN           = $(RUN)'
	@echo 'WORKLOAD      = $(WORKLOAD)'
	@echo 'WORKLOAD_ARGS = $(WORKLOAD_ARGS)'
	@echo 'TEST_PLUSARGS = $(TEST_PLUSARGS)'
	@echo 'FLPS          = $(FLPS)'
	@echo 'FBK_FDB       = $(FBK_FDB)'
	@echo 'QOPT_EXTRA    = $(QOPT_EXTRA)'
	@echo 'QSIM_EXTRA    = $(QSIM_EXTRA)'
	@echo 'QSIM_LOG      = $(QSIM_LOG)'
	@echo 'VOPT flags    = $(VOPT_FLAGS)'
	@echo 'VSIM flags    = $(VSIM_FLAGS)'
	@echo 'QOPT flags    = $(QOPT_FLAGS)'
	@echo 'QSIM flags    = $(QSIM_FLAGS)'
	@echo 'QRUN flags    = $(QRUN_FLAGS)'
