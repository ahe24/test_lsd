//==============================================================================
// lsd_prbs_driver.sv
// Pure LFSR-based pseudo-random source.  No pulse / divider — period control
// lives in callers (e.g. lsd_self_traffic) so it can be runtime-overridden
// from plusargs without forcing this module to be re-elaborated per use.
//
//   prbs_data : full WIDTH-bit register, advanced every cycle
//   prbs_bit  : 1-bit serial bit (LSB), useful when callers only need 1 bit
//
// POLY is supplied as a WIDTH-bit Galois tap mask.  The defaults are 32-bit
// CRC primitives picked for non-overlapping spectra so neighbouring
// instances see uncorrelated traffic — helps the optimiser and parallel
// simulator see independent activity per partition.
//==============================================================================
`ifndef LSD_PRBS_DRIVER_SV
`define LSD_PRBS_DRIVER_SV

module lsd_prbs_driver #(
    parameter int unsigned       WIDTH = 32,
    parameter logic [WIDTH-1:0]  SEED  = 'h12345678,
    parameter logic [WIDTH-1:0]  POLY  = 'hEDB88320
) (
    input  logic                 clk,
    input  logic                 rst_n,
    output logic [WIDTH-1:0]     prbs_data,
    output logic                 prbs_bit
);
    logic [WIDTH-1:0] state;
    logic             fb;

    // Generic Galois LFSR: shift right, XOR poly when LSB is 1.
    assign fb = state[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= (SEED == '0) ? {{(WIDTH-1){1'b0}}, 1'b1} : SEED;
        else        state <= fb ? ((state >> 1) ^ POLY) : (state >> 1);
    end

    assign prbs_data = state;
    assign prbs_bit  = state[0];
endmodule : lsd_prbs_driver

`endif // LSD_PRBS_DRIVER_SV
