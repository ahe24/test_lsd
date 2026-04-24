# =============================================================================
#  LSD Simulation Makefile  (Questasim + Questa One Sim)
# -----------------------------------------------------------------------------
#  Targets
#    make sim                         - full workload, ENGINE=vsim (default)
#    make sim ENGINE=qsim             - full workload with qopt + qsim
#    make sim ENGINE=qrun             - modern 1-step qrun flow
#    make smokesim                    - short sanity test
#    make bmtsim                      - bare-metal / base-block test
#    make stress                      - heavy stress test
#    make gen                         - regenerate the bloat-module farm
#    make clean                       - remove build artifacts
#    make info                        - print current knob values
#
#  Run-time selection:
#    RUN="-all"        run until $finish (default)
#    RUN="1 us"        stop after 1 us of sim time
#    RUN="100 ns"      stop after 100 ns
#    e.g.  make smokesim RUN="1 us"
#
#  Debug / waveform (ALWAYS dumped):
#    DEBUG=wlf    classic WLF flow   (vopt +acc=npr  → vsim -wlf vsim.wlf)
#    DEBUG=vis    Visualizer flow    (vopt -debug +designfile → vsim -qwavedb)
#
#  Notes:
#    - DEBUG=wlf is only legal for ENGINE=vsim. qsim and qrun force Visualizer.
#    - Waveform dump is always on. There is no GUI launch from this flow;
#      open the WLF or design.bin separately (vsim -view vsim.wlf, or
#      Visualizer on design.bin) once the batch run completes.
# =============================================================================

# --- Engine and test selection (vsim, qsim, qrun)
ENGINE      ?= vsim
TEST        ?= lsd_smoke_test
SEED        ?= 1
VERB        ?= UVM_MEDIUM

# -----------------------------------------------------------------------------
# BLOAT_COUNT: number of auto-generated unique RTL modules per bloat farm
#              (eight farms exist) used to stress compile / elaboration / sim.
#
#   Eight independent families of bloat modules are generated, all sized by
#   BLOAT_COUNT, so the effective module count instantiated in the design is
#   8 x BLOAT_COUNT. Running eight structurally different families at once
#   keeps the simulator's optimizer from collapsing the workload by matching
#   any single topology or primitive:
#
#     Family 1 (tools/gen_bloat.py   -> lsd_bloat_u####   + lsd_bloat_farm):
#       Linear arithmetic chain. 32-bit LFSR+pipeline shell, sig[i]->sig[i+1].
#
#     Family 2 (tools/gen_bloat2.py  -> lsd_bloat2_u####  + lsd_bloat2_farm):
#       Parallel memory / shift-ring kernels, independent per-leaf with seed
#       rotation and XOR-reduced taps.
#
#     Family 3 (tools/gen_churn.py   -> lsd_churn_u####   + lsd_churn_farm):
#       Broadcast-fanout kernels. 4 shared signals (counter + two LFSRs)
#       fanned out to every leaf; mix / constant-rotate primitives.
#
#     Family 4 (tools/gen_grind.py   -> lsd_grind_u####   + lsd_grind_farm):
#       Crosscouple ring. Each leaf couples to both neighbors' previous
#       outputs; seed XORed into one ring edge prevents quiescence.
#
#     Family 5 (tools/gen_haze.py    -> lsd_haze_u####    + lsd_haze_farm):
#       Pairwise fan-in. Each leaf takes TWO distinct seed-derived inputs
#       through a 3-stage pipeline.
#
#     Family 6 (tools/gen_prism.py   -> lsd_prism_u####   + lsd_prism_farm):
#       64-bit MAC chain. Linear chain like family 1 but wider data path
#       with a real 32x32->64 multiplier per stage.
#
#     Family 7 (tools/gen_echo.py    -> lsd_echo_u####    + lsd_echo_farm):
#       Deep forward shift-register delay lines (D=16..32 per leaf), no
#       feedback -- long fan-out chains without cycles.
#
#     Family 8 (tools/gen_vortex.py  -> lsd_vortex_u####  + lsd_vortex_farm):
#       1-bit tick broadcast + tick-gated saturating counter banks per
#       leaf. Sparse broadcast signature distinct from family 3's dense one.
#
#   All families use unique LFSR polys, mix constants, and internal sizes
#   so the elaborator cannot merge units within a family either.
#
#   HEADS UP: total module count is 8 x BLOAT_COUNT. The scale guide below
#   is per-family; multiply compile/vopt time by roughly 8. Drop BLOAT_COUNT
#   to 250-500 for quick iteration on the eight-family layout.
#
#   The `gen` target regenerates the farm whenever BLOAT_COUNT changes.
#   `make compile` / `make sim` depend on `gen` and pick up new counts
#   automatically.
#
#   Practical scale guide (rough, ~16-core workstation with 32 GB RAM):
#       Value     Compile    vopt       Exec perf   Typical use
#       --------  ---------  ---------  ----------  -----------------------
#          500    ~5  s      ~15 s      fast        debug / fast iteration
#         2000    ~30 s      ~60 s      moderate    default stress
#        10000    ~5-10 min  ~5 min     slow        real stress
#        30000    ~30 min    ~20 min    very slow   extreme stress
#       100000    hours      hours      grinding    simulator-killer
#
#   Practical ceilings:
#     - File-name padding in gen_bloat.py uses 4 digits (u0000..u9999).
#       Values > 9999 still work but break sort order; bump {idx:04d} to
#       {idx:06d} inside the templates if you go above 10000.
#     - The bloat farm chains one 32-bit signal per module in a single
#       generate loop; vopt memory grows ~linearly. Past ~50000 you likely
#       need a 2-level hierarchical farm to keep vopt sane.
#     - Questa itself can hold millions of design units; the real wall is
#       host RAM at vopt time, not a tool-internal cap.
#
#   Override per-run:   make sim BLOAT_COUNT=10000
#   Force regenerate:   make gen BLOAT_COUNT=5000
# -----------------------------------------------------------------------------
BLOAT_COUNT ?= 1000

# --- Heartbeat period (simulated ns). tb_top prints a progress line every
#     HEARTBEAT ns of sim time so a batch run visibly advances.
HEARTBEAT   ?= 10000

# -----------------------------------------------------------------------------
# RUN: simulation run command passed to vsim/qsim's -do.
#      Defaults to "-all" (run until $finish / UVM drop-objection).
#      Override to stop earlier for quick triage or timing measurements.
#
#   Examples:
#       make smokesim                       -> run -all; quit    (default)
#       make smokesim RUN="1 us"            -> run 1 us;  quit
#       make smokesim RUN="100 ns"          -> run 100 ns; quit
#       make sim      RUN="500 us"          -> run 500 us; quit
#       make sim      RUN="-all -until 2ms" -> any legal vsim run expression
#
#   Notes:
#     - Values with spaces must be quoted on the shell:  RUN="1 us"
#     - The simulation also stops naturally when all UVM objections drop,
#       so RUN=-all is safe for tests that end on their own.
#     - If the test keeps objecting (e.g. infinite sequence), use an
#       explicit time like RUN="5 us" to force termination.
# -----------------------------------------------------------------------------
RUN         ?= -all

# --- Debug mode: wlf (classic) | vis (Visualizer)
#DEBUG       ?= wlf
DEBUG       ?= vis

# qsim engine cannot use the classic WLF debug — force vis if the user picked
# qsim/qrun with DEBUG=wlf, but warn so it is obvious.
ifneq ($(ENGINE),vsim)
    ifneq ($(DEBUG),vis)
        $(warning [Makefile] ENGINE=$(ENGINE) requires DEBUG=vis; overriding)
        override DEBUG = vis
    endif
endif

# --- File lists
RTL_FL      = rtl_filelist.f
TB_FL       = tb_filelist.f

# --- UVM library link (Questa ships precompiled UVM as 'mtiUvm')
UVM_LIB     = mtiUvm

# --- Compile flags
VLOG_FLAGS  = -sv -mfcu -timescale=1ns/1ps \
              -suppress 2583 -suppress 13314 -suppress 13288 \
              +define+UVM_NO_DEPRECATED
VLOG_TB_FLAGS = $(VLOG_FLAGS) -L $(UVM_LIB)

# --- Debug-mode-specific optimization and run-time flags
ifeq ($(DEBUG),wlf)
    # Classic access + WLF waveform log
    VOPT_DBG_FLAGS = +acc=npr
    VSIM_DBG_FLAGS = -wlf vsim.wlf
    QOPT_DBG_FLAGS = $(error DEBUG=wlf is not supported for ENGINE=qsim)
    QSIM_DBG_FLAGS = $(error DEBUG=wlf is not supported for ENGINE=qsim)
else ifeq ($(DEBUG),vis)
    # Visualizer: vopt emits design.bin (default name), vsim records qwavedb.
    # NOTE: +acc is NOT permitted alongside -debug +designfile.
    VOPT_DBG_FLAGS = -debug +designfile
    VSIM_DBG_FLAGS = -qwavedb=+signal+class
    QOPT_DBG_FLAGS = -debug +designfile
    QSIM_DBG_FLAGS = -qwavedb=+signal+class
else
    $(error Unknown DEBUG=$(DEBUG) - valid: wlf | vis)
endif

# --- Aggregated per-tool flags
VOPT_FLAGS  = -O5 -L $(UVM_LIB) $(VOPT_DBG_FLAGS)
QOPT_FLAGS  = -O5 -L $(UVM_LIB) $(QOPT_DBG_FLAGS)

VSIM_FLAGS  = -batch -l vsim.log -do "run $(RUN); quit" -L $(UVM_LIB) \
              -sv_seed $(SEED) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERB) \
              +heartbeat=$(HEARTBEAT) \
              $(VSIM_DBG_FLAGS)

QSIM_FLAGS  = -batch -l qsim.log -do "run $(RUN); quit" -L $(UVM_LIB) \
              -sv_seed $(SEED) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERB) \
              +heartbeat=$(HEARTBEAT) \
              $(QSIM_DBG_FLAGS)

# qrun: modern 1-step flow, Visualizer-native
QRUN_FLAGS  = -sv -mfcu -timescale=1ns/1ps -uvm -uvmcontrol=all \
              -O5 -optimize -debug +designfile -qwavedb=+signal+class \
              -batch -l qrun.log -do "run $(RUN); quit" \
              -sv_seed $(SEED) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERB) \
              +heartbeat=$(HEARTBEAT) \
              -f $(RTL_FL) -f $(TB_FL) -top tb_top

WORKLIB     = work

# =============================================================================
.PHONY: all sim smokesim bmtsim stress gen clean workdir compile optimize run \
        run_vsim run_qsim run_qrun info

all: sim

# Regenerate all eight bloat farms. All honour BLOAT_COUNT — total generated
# module count is 8 x BLOAT_COUNT. Each family lives in its own subdir under
# ../rtl/gen/ so the directory stays navigable at large counts.
gen:
	python tools/gen_bloat.py  --out ../rtl/gen/bloat  --count $(BLOAT_COUNT)
	python tools/gen_bloat2.py --out ../rtl/gen/bloat2 --count $(BLOAT_COUNT)
	python tools/gen_churn.py  --out ../rtl/gen/churn  --count $(BLOAT_COUNT)
	python tools/gen_grind.py  --out ../rtl/gen/grind  --count $(BLOAT_COUNT)
	python tools/gen_haze.py   --out ../rtl/gen/haze   --count $(BLOAT_COUNT)
	python tools/gen_prism.py  --out ../rtl/gen/prism  --count $(BLOAT_COUNT)
	python tools/gen_echo.py   --out ../rtl/gen/echo   --count $(BLOAT_COUNT)
	python tools/gen_vortex.py --out ../rtl/gen/vortex --count $(BLOAT_COUNT)

workdir:
	@if [ ! -d $(WORKLIB) ]; then vlib $(WORKLIB); vmap $(WORKLIB) $(WORKLIB); fi

# -----------------------------------------------------------------------------
# Compile (vlog) — shared between vsim, qsim engines
# -----------------------------------------------------------------------------
compile: workdir gen
	vlog $(VLOG_FLAGS)    -f $(RTL_FL) -l vlog.log
	vlog $(VLOG_TB_FLAGS) -f $(TB_FL)  -l vlog_tb.log

# -----------------------------------------------------------------------------
# Optimize (vopt or qopt)
# -----------------------------------------------------------------------------
optimize: compile
ifeq ($(ENGINE),vsim)
	vopt $(VOPT_FLAGS) tb_top -o tb_top_opt -l vopt.log
else ifeq ($(ENGINE),qsim)
	qopt $(QOPT_FLAGS) tb_top -o tb_top_opt -l qopt.log
endif

# -----------------------------------------------------------------------------
# Run — dispatches to the selected engine
# -----------------------------------------------------------------------------
run: optimize
ifeq ($(ENGINE),vsim)
	$(MAKE) run_vsim
else ifeq ($(ENGINE),qsim)
	$(MAKE) run_qsim
else ifeq ($(ENGINE),qrun)
	$(MAKE) run_qrun
else
	$(error Unknown ENGINE=$(ENGINE) - valid: vsim | qsim | qrun)
endif

run_vsim:
	vsim $(VSIM_FLAGS) -uvmcontrol=all tb_top_opt

run_qsim:
	qsim $(QSIM_FLAGS) -uvmcontrol=all tb_top_opt

run_qrun:
	$(MAKE) gen
	qrun $(QRUN_FLAGS)

# -----------------------------------------------------------------------------
# Top-level targets
# -----------------------------------------------------------------------------
sim:
	$(MAKE) run TEST=lsd_stress_test ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

smokesim:
	$(MAKE) run TEST=lsd_smoke_test  ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

bmtsim:
	$(MAKE) run TEST=lsd_bmt_test    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

stress:
	$(MAKE) run TEST=lsd_stress_test ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

clean:
	rm -rf $(WORKLIB) transcript vsim.wlf tb.vcd design.bin \
	       *.db *.log modelsim.ini .vscode \
	       tb_top_opt covhtmlreport qrun.out *.xml
	@echo "Clean complete"

# Convenience: show which engine and debug mode will be used
info:
	@echo "ENGINE      = $(ENGINE)"
	@echo "DEBUG       = $(DEBUG)"
	@echo "TEST        = $(TEST)"
	@echo "SEED        = $(SEED)"
	@echo "BLOAT_COUNT = $(BLOAT_COUNT)"
	@echo "HEARTBEAT   = $(HEARTBEAT) ns"
	@echo "RUN         = $(RUN)"
	@echo "VOPT flags  = $(VOPT_FLAGS)"
	@echo "VSIM flags  = $(VSIM_FLAGS)"
