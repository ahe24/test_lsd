//==============================================================================
// lsd_top.sv
// Top-level integration of all five functional subsystems plus the eight
// uniqueness-padding bloat farms.
//
// PARTITION-FRIENDLY (Phase 2) DESIGN
// -----------------------------------
// Every functional/bloat block is wrapped in its own *island* module
// (lsd_subsys_islands.sv, lsd_bloat_islands.sv).  Each island exposes
// only (clk, rst_n) externally — the per-subsystem cmd / stream
// interfaces and the per-bloat seed generator live entirely inside
// their island.  The ParallelSim partitioner therefore cannot split an
// island across partitions, so cross-partition signals collapse from
// "thousands of interface bits per cycle" (Phase 1.5 had self_traffic
// in master and the subsystem in a worker, see test_logs/test_1222
// qsimparallelsim.log:97-145) to just clk + rst_n broadcasts.
//
// The DUT has no testbench-driven ports.  tb_top instantiates lsd_top
// with just (clk, rst_n) and observes via heartbeats.
//==============================================================================
module lsd_top (
    input  logic           clk,
    input  logic           rst_n
);
    // -------------------------------------------------------------------------
    // Five functional subsystem islands.  Each owns an internal PRBS
    // self-traffic generator + the matching DUT block.
    // -------------------------------------------------------------------------
    lsd_cnn_island    u_cnn    (.clk(clk), .rst_n(rst_n));
    lsd_crypto_island u_crypto (.clk(clk), .rst_n(rst_n));
    lsd_gfx_island    u_gfx    (.clk(clk), .rst_n(rst_n));
    lsd_calu_island   u_calu   (.clk(clk), .rst_n(rst_n));
    lsd_eccd_island   u_eccd   (.clk(clk), .rst_n(rst_n));

    // -------------------------------------------------------------------------
    // Eight uniqueness-padding bloat-farm islands.  Each contains its own
    // 32-bit free-running LFSR seed so the linear-chain family stays
    // toggling.  See gen/<family>/ for the underlying generated farms.
    // -------------------------------------------------------------------------
    lsd_bloat_island   u_bloat   (.clk(clk), .rst_n(rst_n));
    lsd_bloat2_island  u_bloat2  (.clk(clk), .rst_n(rst_n));
    lsd_churn_island   u_churn   (.clk(clk), .rst_n(rst_n));
    lsd_grind_island   u_grind   (.clk(clk), .rst_n(rst_n));
    lsd_haze_island    u_haze    (.clk(clk), .rst_n(rst_n));
    lsd_prism_island   u_prism   (.clk(clk), .rst_n(rst_n));
    lsd_echo_island    u_echo    (.clk(clk), .rst_n(rst_n));
    lsd_vortex_island  u_vortex  (.clk(clk), .rst_n(rst_n));
endmodule : lsd_top
