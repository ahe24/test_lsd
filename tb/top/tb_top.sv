//==============================================================================
// tb_top.sv  -  UVM testbench top wrapping lsd_top
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

    // Interfaces (shared clk/rst_n)
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) cmd_if (clk, rst_n);
    lsd_stream_if #(.W(512))                  in_if  (clk, rst_n);
    lsd_stream_if #(.W(512))                  out_if (clk, rst_n);

    // DUT
    lsd_top u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .host_cmd (cmd_if),
        .host_in  (in_if),
        .host_out (out_if)
    );

    // Drive out_if consumer ready (we are the sink of the DUT output)
    assign out_if.ready = 1'b1;

    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        uvm_config_db#(virtual lsd_cmd_if)   ::set(null, "*", "vif_cmd", cmd_if);
        uvm_config_db#(virtual lsd_stream_if)::set(null, "*", "vif_in",  in_if);
        uvm_config_db#(virtual lsd_stream_if)::set(null, "*", "vif_out", out_if);
        run_test();
    end

    // -------------------------------------------------------------------------
    // Progress / heartbeat
    // -------------------------------------------------------------------------
    // Periodically prints simulation time plus handshake-event counters so a
    // batch run visibly advances. Period is configurable from the command line
    // via  +heartbeat=<ns>  (default 10 us of simulated time).
    // Counters let you tell "stalled" from "still busy" at a glance: if cmd_hs
    // stops advancing across heartbeats, something blocked the command path.
    // -------------------------------------------------------------------------
    int unsigned n_cmd_hs;
    int unsigned n_in_hs;
    int unsigned n_out_hs;
    int unsigned n_rsp_hs;
    int unsigned last_cmd_hs;
    int unsigned hb_ticks;
    int          hb_period_ns;

    always @(posedge clk) begin
        if (rst_n) begin
            if (cmd_if.cmd_valid && cmd_if.cmd_ready) n_cmd_hs <= n_cmd_hs + 1;
            if (cmd_if.rsp_valid && cmd_if.rsp_ready) n_rsp_hs <= n_rsp_hs + 1;
            if (in_if.valid      && in_if.ready)      n_in_hs  <= n_in_hs  + 1;
            if (out_if.valid     && out_if.ready)     n_out_hs <= n_out_hs + 1;
        end
    end

    initial begin
        automatic int    delta;
        automatic string stall_tag;
        n_cmd_hs = 0; n_in_hs = 0; n_out_hs = 0; n_rsp_hs = 0;
        last_cmd_hs = 0; hb_ticks = 0;
        if (!$value$plusargs("heartbeat=%d", hb_period_ns)) hb_period_ns = 10_000;
        // Defer first heartbeat past reset
        #200;
        $display("[tb_top] heartbeat period = %0d ns (override with +heartbeat=<ns>)",
                 hb_period_ns);
        $fflush;
        forever begin
            #(hb_period_ns);
            hb_ticks++;
            delta     = n_cmd_hs - last_cmd_hs;
            stall_tag = (delta == 0 && hb_ticks > 1) ? "  [STALL?]" : "";
            last_cmd_hs = n_cmd_hs;
            $display("[tb_top] HB#%0d t=%0t  cmd=%0d rsp=%0d in=%0d out=%0d  d_cmd=%0d%s",
                     hb_ticks, $realtime,
                     n_cmd_hs, n_rsp_hs, n_in_hs, n_out_hs,
                     delta, stall_tag);
            $fflush;
        end
    end

    // Final summary at simulation end
    final begin
        $display("[tb_top] FINAL t=%0t  cmd=%0d rsp=%0d in=%0d out=%0d  heartbeats=%0d",
                 $realtime, n_cmd_hs, n_rsp_hs, n_in_hs, n_out_hs, hb_ticks);
    end
endmodule : tb_top
