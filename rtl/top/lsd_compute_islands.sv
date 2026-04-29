//==============================================================================
// lsd_compute_islands.sv
// Eight closed islands, each wrapping one lsd_heavy_compute instance with a
// distinct SEED.  Each island has only (clk, rst_n) as inputs and a single
// 32-bit `tap` output that is XOR-folded into a design-level design_tap by
// lsd_top — no system tasks live inside the island, so the partitioner is
// free to place each island in whichever worker it likes.
//
// Why no `final $display(tap)` here?  Phase 3.0 used a final block to keep
// `tap` observable, but $display is a master-scope system task and that
// dragged every compute_island into the master partition (test_logs/
// test1444 partition_analysis.txt: master 72.6% with all eight compute
// islands hidden under tb_top scope).  Routing tap as a real output and
// observing it once at $finish from tb_top achieves the same DCE-defeating
// effect without forcing the partitioner's hand.
//==============================================================================
`ifndef LSD_COMPUTE_ISLANDS_SV
`define LSD_COMPUTE_ISLANDS_SV

`define LSD_COMPUTE_ISLAND(name, seed_const)                              \
module name (                                                              \
    input  logic        clk,                                               \
    input  logic        rst_n,                                             \
    output logic [31:0] tap                                                \
);                                                                         \
    lsd_heavy_compute #(                                                   \
        .MEM_DEPTH(1024),                                                  \
        .MEM_WIDTH(256),                                                   \
        .N_PORTS  (8),                                                     \
        .SEED     (seed_const)                                             \
    ) u_eng (                                                              \
        .clk  (clk),                                                       \
        .rst_n(rst_n),                                                     \
        .tap  (tap)                                                        \
    );                                                                     \
endmodule

`LSD_COMPUTE_ISLAND(lsd_compute0_island, 64'h0123_4567_89AB_CDEF)
`LSD_COMPUTE_ISLAND(lsd_compute1_island, 64'hFEDC_BA98_7654_3210)
`LSD_COMPUTE_ISLAND(lsd_compute2_island, 64'hCAFE_BABE_DEAD_BEEF)
`LSD_COMPUTE_ISLAND(lsd_compute3_island, 64'hA5A5_A5A5_5A5A_5A5A)
`LSD_COMPUTE_ISLAND(lsd_compute4_island, 64'h1357_9BDF_2468_ACE0)
`LSD_COMPUTE_ISLAND(lsd_compute5_island, 64'hF00D_BABE_C0DE_BABE)
`LSD_COMPUTE_ISLAND(lsd_compute6_island, 64'hB16B_00B5_DEAD_C0DE)
`LSD_COMPUTE_ISLAND(lsd_compute7_island, 64'h7137_4D9C_45A1_F2EB)

`undef LSD_COMPUTE_ISLAND

`endif // LSD_COMPUTE_ISLANDS_SV
