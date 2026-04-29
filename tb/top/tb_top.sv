//==============================================================================
// tb_top.sv  -  Plain-SystemVerilog testbench top wrapping lsd_top
//
// PARTITION-FRIENDLY (Phase 1.5) DESIGN — UVM-FREE
// ------------------------------------------------
// The DUT generates its own traffic via per-subsystem PRBS islands (see
// rtl/common/lsd_self_traffic.sv).  This testbench therefore has *no*
// UVM machinery — no factory, no _global_reporter, no run_test, no
// virtual-interface bindings.  That kills the "Cross-Partition VPI - C
// Callback access" Negative Factor that ParallelSim's qualifier flagged
// against /uvm_pkg, and is the final blocker the Phase 1 report identified.
//
// The TB owns only:
//   * Clock + reset generation
//   * A `+run_ns=<int>` plusarg controlling sim length (calls $finish)
//   * A `+heartbeat=<int>` plusarg for periodic progress prints
// Workload variation comes from per-instance plusargs read inside each
// lsd_self_traffic island (see that file for the +<tag>_cmd_period /
// +<tag>_str_period / +<tag>_disable interface).  Different testcases
// in sim/Makefile pass different plusarg sets — no testbench-side
// recompile is needed.
//==============================================================================
`timescale 1ns/1ps

module tb_top;
    logic clk = 0;
    logic rst_n = 0;

    always #2.5 clk = ~clk; // 200 MHz

    // DUT — only clk/rst_n flow into the design.  design_tap is a 32-bit
    // XOR-fold of all eight compute_island taps; the TB observes it once
    // in the final block below, which is what keeps qopt -O5 from DCE-ing
    // the compute chain.  See rtl/top/lsd_compute_islands.sv for the
    // partition-friendly rationale.
    logic [31:0] design_tap;
    lsd_top u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .design_tap (design_tap)
    );

    // -------------------------------------------------------------------------
    // Run-length / heartbeat config (read once at time 0)
    // -------------------------------------------------------------------------
    int unsigned run_ns;
    int unsigned hb_period_ns;

    initial begin
        run_ns       = 5_000;     // 5 us default
        hb_period_ns = 10_000;    // 10 us default
        void'($value$plusargs("run_ns=%d",    run_ns));
        void'($value$plusargs("heartbeat=%d", hb_period_ns));
        $display("[tb_top] run_ns=%0d  heartbeat=%0d ns", run_ns, hb_period_ns);
    end

    // -------------------------------------------------------------------------
    // Reset + run window
    // -------------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        // run_ns is in nanoseconds; timescale is 1ns/1ps, so #N is N ns.
        #(run_ns);
        $display("[tb_top] FINAL t=%0t", $realtime);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Heartbeat — time-only progress (TB has no XMR into DUT counters).
    // -------------------------------------------------------------------------
    int unsigned hb_ticks;

    initial begin
        hb_ticks = 0;
        #200;
        forever begin
            #(hb_period_ns);
            hb_ticks++;
            $display("[tb_top] HB#%0d t=%0t", hb_ticks, $realtime);
        end
    end

    final begin
        $display("[tb_top] FINAL-final t=%0t  heartbeats=%0d  design_tap=%08h",
                 $realtime, hb_ticks, design_tap);
    end
endmodule : tb_top
