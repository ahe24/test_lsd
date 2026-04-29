//==============================================================================
// lsd_bloat_islands.sv
// One closed module per bloat farm.  Each island contains:
//   * a free-running 32-bit LFSR seed generator (so the linear-chain
//     family doesn't settle into a static state)
//   * the corresponding lsd_<family>_farm instance.
//
// External interface is only (clk, rst_n) — the seed signal is internal,
// so it never crosses a partition boundary.  Eight islands, one per
// bloat family.
//==============================================================================
`ifndef LSD_BLOAT_ISLANDS_SV
`define LSD_BLOAT_ISLANDS_SV

`define LSD_BLOAT_ISLAND(name, init_const, farm_module)               \
module name (                                                          \
    input logic clk,                                                   \
    input logic rst_n                                                  \
);                                                                     \
    import lsd_pkg::*;                                                 \
    logic [31:0] seed;                                                 \
    always_ff @(posedge clk or negedge rst_n) begin                    \
        if (!rst_n) seed <= init_const;                                \
        else        seed <= lsd_lfsr32(seed);                          \
    end                                                                \
    farm_module u_farm (.clk(clk), .rst_n(rst_n), .seed(seed));        \
endmodule

`LSD_BLOAT_ISLAND(lsd_bloat_island,  32'h1234_5678, lsd_bloat_farm )
`LSD_BLOAT_ISLAND(lsd_bloat2_island, 32'hB7E1_5163, lsd_bloat2_farm)
`LSD_BLOAT_ISLAND(lsd_churn_island,  32'h7137_4D9C, lsd_churn_farm )
`LSD_BLOAT_ISLAND(lsd_grind_island,  32'h45A1_F2EB, lsd_grind_farm )
`LSD_BLOAT_ISLAND(lsd_haze_island,   32'hC0FF_EE00, lsd_haze_farm  )
`LSD_BLOAT_ISLAND(lsd_prism_island,  32'hAB54_A98C, lsd_prism_farm )
`LSD_BLOAT_ISLAND(lsd_echo_island,   32'h5DEE_CE2D, lsd_echo_farm  )
`LSD_BLOAT_ISLAND(lsd_vortex_island, 32'h7C2F_91AA, lsd_vortex_farm)

`undef LSD_BLOAT_ISLAND

`endif // LSD_BLOAT_ISLANDS_SV
