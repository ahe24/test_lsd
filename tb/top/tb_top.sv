//==============================================================================
// tb_top.sv  -  UVM testbench top wrapping lsd_top
//
// PARTITION-FRIENDLY (Phase 1) DESIGN
// -----------------------------------
// The DUT is now self-traffic-driven: each subsystem owns an internal PRBS
// generator (see rtl/common/lsd_self_traffic.sv).  The testbench therefore
// no longer passes any virtual interface across the design boundary, which
// removes the ParallelSim "Virtual interface" Unsupp entries.  We still run
// UVM (run_test()) so the existing reporting / objection machinery stays in
// place, but no agent reaches into the DUT — see lsd_tests.sv.
//==============================================================================
`timescale 1ns/1ps

module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import lsd_uvm_pkg::*;
    import lsd_tests::*;

    logic clk = 0;
    logic rst_n;

    always #2.5 clk = ~clk; // 200 MHz

    // DUT — fully self-contained, only clock and reset cross the boundary.
    lsd_top u_dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        run_test();
    end

    // -------------------------------------------------------------------------
    // Heartbeat — simple time-only progress, since the testbench has no
    // direct visibility into the DUT's internal handshake signals.  Period
    // is configurable via +heartbeat=<ns> (default 10 us).
    // -------------------------------------------------------------------------
    int unsigned hb_ticks;
    int          hb_period_ns;

    initial begin
        hb_ticks = 0;
        if (!$value$plusargs("heartbeat=%d", hb_period_ns)) hb_period_ns = 10_000;
        #200;
        $display("[tb_top] heartbeat period = %0d ns (override with +heartbeat=<ns>)",
                 hb_period_ns);
        $fflush;
        forever begin
            #(hb_period_ns);
            hb_ticks++;
            $display("[tb_top] HB#%0d t=%0t", hb_ticks, $realtime);
            $fflush;
        end
    end

    final begin
        $display("[tb_top] FINAL t=%0t  heartbeats=%0d", $realtime, hb_ticks);
    end
endmodule : tb_top
