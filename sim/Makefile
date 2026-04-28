# =============================================================================
#  LSD Simulation Makefile  (Questasim / Questa One Sim)
# -----------------------------------------------------------------------------
#  Targets
#    sim smokesim bmtsim stress   run a UVM test (default ENGINE=vsim)
#    qual qfbk psim uni           ParallelSim flow (qsim only) — see below
#    gen                          regenerate bloat farms if stale (cached)
#    clean-gen                    wipe gen stamps (force full regen next run)
#    clean                        remove build artifacts
#    info                         print current knob values
#
#  Knobs  (override at CLI, e.g.  make sim ENGINE=qrun BLOAT_COUNT=5000 RUN="1 us")
#    ENGINE       vsim | qsim | qrun           default: vsim
#    DEBUG        wlf | vis                    default: vis    (qsim/qrun force vis)
#    RUN          "-all" | "1 us" | "100 ns"   default: -all   (run until $finish)
#    TEST         <uvm_test class name>        default: lsd_smoke_test
#    SEED         <int>                        default: 1
#    VERB         UVM_NONE..UVM_FULL           default: UVM_MEDIUM
#    BLOAT_COUNT  per-family generator count   default: 1000   (total modules = 8 x this)
#    HEARTBEAT    ns between progress prints   default: 10000
#    FLPS         ParallelSim partitions       default: (unset; required for psim)
#    FBK_FDB      qsim.fdb for feedback flow   default: newest fprofile/*.fdb
#    QOPT_EXTRA   appended to QOPT_FLAGS       default: empty
#    QSIM_EXTRA   appended to QSIM_FLAGS       default: empty
#    QSIM_LOG     qsim transcript filename     default: qsim.log
#
#  Debug modes (waveforms are always dumped; no GUI launch from this flow):
#    DEBUG=wlf    vopt +acc=npr    + vsim -wlf vsim.wlf   (vsim engine only)
#    DEBUG=vis    vopt +designfile + vsim -qwavedb        (Visualizer)
#    Open the WLF or design.bin separately once the batch run completes.
#
#  ParallelSim flow  (Questa One tutorial Ch. 1; qsim engine only)
#    1) make qual                Qualifier run.  Open `qsim -fprofile+flps`
#                                in the GUI and read the recommended N from
#                                the Partition Analysis window.
#    2) make qfbk                (Optional) Qualifier feedback run — only if
#                                qual flags unsupported dynamic external
#                                accesses (e.g. UVM-HDL backdoor reads).
#                                Auto-picks newest fprofile/*.fdb.
#    3) make psim FLPS=N         ParallelSim run with N partitions.
#                                Auto-attaches FBK_FDB if step 2 was run.
#    4) make uni                 Single-core baseline.  Diff qsimuni.log
#                                against qsimparallelsim.log to see gain.
# =============================================================================

# -----------------------------------------------------------------------------
# Knobs — overridable on the command line (see header for descriptions)
# -----------------------------------------------------------------------------
ENGINE      ?= vsim
RUN         ?= -all
#DEBUG       ?= wlf
DEBUG       ?= vis

TEST        ?= lsd_smoke_test
SEED        ?= 1
VERB        ?= UVM_MEDIUM

BLOAT_COUNT ?= 1000
HEARTBEAT   ?= 10000

# ParallelSim (qsim only) — see "ParallelSim flow" in the header.
FLPS        ?=
FBK_FDB     ?= $(shell ls -t fprofile/*.fdb 2>/dev/null | head -1)
QOPT_EXTRA  ?=
QSIM_EXTRA  ?=
QSIM_LOG    ?= qsim.log

# Only vsim supports the classic WLF debug flow; qsim/qrun force vis.
ifneq ($(ENGINE),vsim)
    ifneq ($(DEBUG),vis)
        $(warning [Makefile] ENGINE=$(ENGINE) requires DEBUG=vis; overriding)
        override DEBUG = vis
    endif
endif

# -----------------------------------------------------------------------------
# Bloat farms: eight structurally distinct families in rtl/gen/<family>/ run
# side-by-side so the simulator's optimizer cannot collapse the workload by
# matching any single topology. See tools/gen_*.py for per-family details.
#
#   Families:  bloat  bloat2  churn  grind  haze  prism  echo  vortex
#
#   Per-family scale guide (~16-core, 32 GB; total load = 8 x BLOAT_COUNT):
#     Value     Compile    vopt       Typical use
#     --------  ---------  ---------  -----------------------
#        500    ~5  s      ~15 s      debug / fast iteration
#       2000    ~30 s      ~60 s      default stress
#      10000    ~5-10 min  ~5 min     real stress
#      30000    ~30 min    ~20 min    extreme stress
#     100000    hours      hours      simulator-killer
#
#   Beyond 9999 per family, bump the 4-digit padding in tools/gen_*.py.
#   Past ~50000 per family, vopt RAM can blow up — consider a 2-level farm.
# -----------------------------------------------------------------------------

# --- File lists and libraries (UVM_LIB is Questa's precompiled UVM)
RTL_FL      = rtl_filelist.f
TB_FL       = tb_filelist.f
UVM_LIB     = mtiUvm
WORKLIB     = work

# --- Compile flags
VLOG_FLAGS  = -sv -mfcu -timescale=1ns/1ps \
              -suppress 2583 -suppress 13314 -suppress 13288 \
              +define+UVM_NO_DEPRECATED
VLOG_TB_FLAGS = $(VLOG_FLAGS) -L $(UVM_LIB)

# --- Debug-mode-specific vopt / vsim flags
ifeq ($(DEBUG),wlf)
    # Classic access + WLF waveform log
    VOPT_DBG_FLAGS = +acc=npr
    VSIM_DBG_FLAGS = -wlf vsim.wlf
    QOPT_DBG_FLAGS = $(error DEBUG=wlf is not supported for ENGINE=qsim)
    QSIM_DBG_FLAGS = $(error DEBUG=wlf is not supported for ENGINE=qsim)
else ifeq ($(DEBUG),vis)
    # Visualizer: vopt emits design.bin; vsim records qwavedb.
    # NOTE: +acc is NOT permitted alongside -debug +designfile.
    VOPT_DBG_FLAGS = -debug +designfile
    VSIM_DBG_FLAGS = -qwavedb=+signal+class
    QOPT_DBG_FLAGS = -debug +designfile
    QSIM_DBG_FLAGS = -qwavedb=+signal+class
else
    $(error Unknown DEBUG=$(DEBUG) - valid: wlf | vis)
endif

# --- Aggregated per-tool flags
#     QOPT_EXTRA / QSIM_EXTRA are passthrough hooks for the ParallelSim flow
#     (qual / qfbk / psim) and any ad-hoc qopt|qsim switches.
VOPT_FLAGS  = -O5 -L $(UVM_LIB) $(VOPT_DBG_FLAGS)
QOPT_FLAGS  = -O5 -L $(UVM_LIB) $(QOPT_DBG_FLAGS) $(QOPT_EXTRA)

VSIM_FLAGS  = -batch -l vsim.log -do "run $(RUN); quit" -L $(UVM_LIB) \
              -sv_seed $(SEED) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERB) \
              +heartbeat=$(HEARTBEAT) \
              $(VSIM_DBG_FLAGS)

QSIM_FLAGS  = -batch -l $(QSIM_LOG) -do "run $(RUN); quit" -L $(UVM_LIB) \
              -sv_seed $(SEED) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERB) \
              +heartbeat=$(HEARTBEAT) \
              $(QSIM_DBG_FLAGS) $(QSIM_EXTRA)

# qrun: 1-step flow (vlog + vopt + vsim), Visualizer-native.
#   - Do NOT pass -compile / -optimize / -simulate: those are PHASE selectors
#     that stop qrun early. For a full run, pass no phase flag. (-O5 is the
#     optimization LEVEL and is fine.)
#   - Do NOT pass -uvm: that recompiles UVM DPI sources and needs a host
#     C/C++ compiler (vlog-7019). -L $(UVM_LIB) links the precompiled UVM
#     library instead, matching the vsim flow.
QRUN_FLAGS  = -sv -mfcu -timescale=1ns/1ps \
              -suppress 2583 -suppress 13314 -suppress 13288 \
              +define+UVM_NO_DEPRECATED \
              -L $(UVM_LIB) -uvmcontrol=all \
              -O5 -debug +designfile -qwavedb=+signal+class \
              -batch -l qrun.log -do "run $(RUN); quit" \
              -sv_seed $(SEED) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERB) \
              +heartbeat=$(HEARTBEAT) \
              -f $(RTL_FL) -f $(TB_FL) -top tb_top

# =============================================================================
.PHONY: all sim smokesim bmtsim stress qual qfbk psim uni gen clean-gen clean \
        workdir compile optimize run run_vsim run_qsim run_qrun info

all: sim

# -----------------------------------------------------------------------------
# gen — regenerate bloat farms, cached by per-family stamp file.
#
#   Stamp path encodes BLOAT_COUNT, so changing the count picks up a missing
#   target and forces regen. Touching a tools/gen_<family>.py invalidates
#   only that family's stamp. Up-to-date families are skipped.
#
#     Force full regen:    make clean-gen gen
#     Force one family:    rm ../rtl/gen/<family>/.stamp-* && make gen
# -----------------------------------------------------------------------------
BLOAT_FAMILIES := bloat bloat2 churn grind haze prism echo vortex
BLOAT_STAMPS   := $(foreach f,$(BLOAT_FAMILIES),../rtl/gen/$(f)/.stamp-$(BLOAT_COUNT))

gen: $(BLOAT_STAMPS)

../rtl/gen/%/.stamp-$(BLOAT_COUNT): tools/gen_%.py
	@echo "[gen] $* (count=$(BLOAT_COUNT))"
	python $< --out $(@D) --count $(BLOAT_COUNT)
	-@rm -f $(@D)/.stamp-* 2>/dev/null
	@touch $@

clean-gen:
	-@rm -f ../rtl/gen/*/.stamp-* 2>/dev/null
	@echo "[clean-gen] all family stamps removed"

workdir:
	@if [ ! -d $(WORKLIB) ]; then vlib $(WORKLIB); vmap $(WORKLIB) $(WORKLIB); fi

# --- Compile (vlog) — shared by the vsim and qsim engines
compile: workdir gen
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
#     The `optimize`/`compile` deps live on run_vsim / run_qsim, not on `run`.
#     qrun is 1-step and must not be preceded by vlog/vopt.
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
	vsim $(VSIM_FLAGS) -uvmcontrol=all tb_top_opt

run_qsim: optimize
	qsim $(QSIM_FLAGS) -uvmcontrol=all tb_top_opt

run_qrun: gen
	qrun $(QRUN_FLAGS)

# --- Top-level test entry points
sim:
	$(MAKE) run TEST=lsd_stress_test ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

smokesim:
	$(MAKE) run TEST=lsd_smoke_test  ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

bmtsim:
	$(MAKE) run TEST=lsd_bmt_test    ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

stress:
	$(MAKE) run TEST=lsd_stress_test ENGINE=$(ENGINE) DEBUG=$(DEBUG) RUN="$(RUN)"

# -----------------------------------------------------------------------------
# ParallelSim (qsim only) — see header for the four-phase flow.
# -----------------------------------------------------------------------------
qual:
	$(MAKE) run TEST=$(TEST) ENGINE=qsim DEBUG=$(DEBUG) RUN="$(RUN)" \
	    QOPT_EXTRA="-fprofile+flps" QSIM_EXTRA="-fprofile+flps" \
	    QSIM_LOG=qsim_qual.log

qfbk:
	@if [ -z "$(FBK_FDB)" ]; then \
	    echo "[Makefile] FBK_FDB empty and no fprofile/*.fdb found - run 'make qual' first"; \
	    exit 1; \
	fi
	$(MAKE) run TEST=$(TEST) ENGINE=qsim DEBUG=$(DEBUG) RUN="$(RUN)" \
	    QOPT_EXTRA="-fprofile+flps -flpsfprof=$(FBK_FDB)" \
	    QSIM_EXTRA="-fprofile+flps" \
	    QSIM_LOG=qsim_qfbk.log

psim:
	@if [ -z "$(FLPS)" ]; then \
	    echo "[Makefile] FLPS is required (e.g. make psim FLPS=3) - run 'make qual' to find N"; \
	    exit 1; \
	fi
	$(MAKE) run TEST=$(TEST) ENGINE=qsim DEBUG=$(DEBUG) RUN="$(RUN)" \
	    QOPT_EXTRA="-flps=$(FLPS)$(if $(FBK_FDB), -flpsfprof=$(FBK_FDB))" \
	    QSIM_EXTRA="-flps" \
	    QSIM_LOG=qsimparallelsim.log

uni:
	$(MAKE) run TEST=$(TEST) ENGINE=qsim DEBUG=$(DEBUG) RUN="$(RUN)" \
	    QSIM_LOG=qsimuni.log

clean:
	rm -rf $(WORKLIB) transcript vsim.wlf tb.vcd design.bin \
	       *.db *.log modelsim.ini .vscode \
	       tb_top_opt covhtmlreport qrun.out *.xml
	@echo "Clean complete"

# Single-quoted echoes keep flag strings literal. $(VSIM_FLAGS) contains
# `-do "run $(RUN); quit"`, whose embedded " and ; would otherwise break
# out of a double-quoted echo and fail at the shell.
info:
	@echo 'ENGINE      = $(ENGINE)'
	@echo 'DEBUG       = $(DEBUG)'
	@echo 'TEST        = $(TEST)'
	@echo 'SEED        = $(SEED)'
	@echo 'BLOAT_COUNT = $(BLOAT_COUNT)'
	@echo 'HEARTBEAT   = $(HEARTBEAT) ns'
	@echo 'RUN         = $(RUN)'
	@echo 'FLPS        = $(FLPS)'
	@echo 'FBK_FDB     = $(FBK_FDB)'
	@echo 'QOPT_EXTRA  = $(QOPT_EXTRA)'
	@echo 'QSIM_EXTRA  = $(QSIM_EXTRA)'
	@echo 'QSIM_LOG    = $(QSIM_LOG)'
	@echo 'VOPT flags  = $(VOPT_FLAGS)'
	@echo 'VSIM flags  = $(VSIM_FLAGS)'
	@echo 'QOPT flags  = $(QOPT_FLAGS)'
	@echo 'QSIM flags  = $(QSIM_FLAGS)'
	@echo 'QRUN flags  = $(QRUN_FLAGS)'
