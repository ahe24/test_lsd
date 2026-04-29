//==============================================================================
// lsd_compute_islands.sv
// Eight closed islands, each wrapping one lsd_heavy_compute instance with a
// distinct SEED (so qopt cannot dedup them across instances).  External
// interface is just (clk, rst_n).  These replace the previous bloat-farm
// islands: the bloat farms generated thousands of unique modules but each
// was so light qopt collapsed them to ~0% profiler weight, leaving crypto
// as the sole significant block and capping psim speedup at the Amdahl
// limit (~1.6x).  The compute islands are deliberately heavy each cycle
// (memory + 256b multiplications), so total work scales with island count
// and the partitioner has real CPU to redistribute.
//
// Eight islands (matching the previous bloat-island count) → with 5
// functional islands (cnn / crypto / gfx / calu / eccd) the partitioner has
// 13 atomic units to spread across (master + N workers), each with only
// (clk, rst_n) crossing the partition boundary.
//==============================================================================
`ifndef LSD_COMPUTE_ISLANDS_SV
`define LSD_COMPUTE_ISLANDS_SV

`define LSD_COMPUTE_ISLAND(name, seed_const)                              \
module name (                                                              \
    input  logic        clk,                                               \
    input  logic        rst_n                                              \
);                                                                         \
    logic [31:0] tap;                                                      \
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
    /* `final` at $finish references tap, so qopt cannot DCE the engine: */\
    /* the simulator must keep tap alive (and hence the whole compute    */\
    /* chain) until end-of-sim.  This stays partition-local — no signal  */\
    /* leaves the island besides clk/rst_n.                              */\
    final $display("[compute_island] final tap=%08h", tap);                \
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
