//==============================================================================
// lsd_top.sv
// Top-level integration of all functional subsystems plus eight heavy-
// compute islands.
//
// PARTITION-FRIENDLY (Phase 3.1) DESIGN
// -------------------------------------
// Five functional subsystem islands + eight heavy-compute islands.  The
// only signals crossing each island's boundary are clk, rst_n, and (for
// the compute islands) a 32-bit `tap` output that lsd_top XOR-folds into
// a single `design_tap` register.  tb_top observes design_tap once at
// $finish, so the simulator must keep the entire compute chain alive to
// produce that final value — which is what defeats qopt -O5 DCE.
//
// Phase 3.0 used a `final $display` inside each compute_island to keep
// the tap observable; that worked but forced the partitioner to put every
// island in master (system tasks are master-scope by default), and master
// ballooned back to 72% of profiler weight (test_logs/test1444).  Phase
// 3.1 keeps the same DCE protection but routes tap as a real port, so
// the partitioner is free to place compute islands in workers.
//==============================================================================
module lsd_top (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] design_tap
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
    // Eight heavy-compute islands.  Each is a 1024×256b memory bank +
    // 8-port wide-MAC engine, with a unique SEED so qopt cannot dedup.
    // Each island exposes a 32-bit `tap` we fold into design_tap below.
    // -------------------------------------------------------------------------
    logic [31:0] taps [0:7];
    lsd_compute0_island u_c0 (.clk(clk), .rst_n(rst_n), .tap(taps[0]));
    lsd_compute1_island u_c1 (.clk(clk), .rst_n(rst_n), .tap(taps[1]));
    lsd_compute2_island u_c2 (.clk(clk), .rst_n(rst_n), .tap(taps[2]));
    lsd_compute3_island u_c3 (.clk(clk), .rst_n(rst_n), .tap(taps[3]));
    lsd_compute4_island u_c4 (.clk(clk), .rst_n(rst_n), .tap(taps[4]));
    lsd_compute5_island u_c5 (.clk(clk), .rst_n(rst_n), .tap(taps[5]));
    lsd_compute6_island u_c6 (.clk(clk), .rst_n(rst_n), .tap(taps[6]));
    lsd_compute7_island u_c7 (.clk(clk), .rst_n(rst_n), .tap(taps[7]));

    // -------------------------------------------------------------------------
    // 8-way XOR fold of compute taps into a single design_tap register.
    // tb_top observes design_tap in its `final` block, which is what keeps
    // qopt from DCE-ing the compute chain.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) design_tap <= '0;
        else        design_tap <= taps[0] ^ taps[1] ^ taps[2] ^ taps[3]
                                ^ taps[4] ^ taps[5] ^ taps[6] ^ taps[7];
    end
endmodule : lsd_top
