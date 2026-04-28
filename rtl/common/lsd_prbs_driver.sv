//==============================================================================
// lsd_prbs_driver.sv
// Parameterised LFSR-based pseudo-random source.  Pure RTL — no plusargs, no
// system tasks — so it composes cleanly inside any partition under
// ParallelSim.  One free-running LFSR per instance, with separate "wide"
// and "valid-rate" outputs:
//
//   prbs_data : full WIDTH-bit register, advanced every cycle
//   prbs_bit  : 1-bit serial bit (LSB), useful for valid pulse trains
//   pulse     : 1 every PULSE_PERIOD cycles when PRBS bit-0 is 1
//
// Polynomial is supplied as a WIDTH-bit tap mask.  The default polys are
// 32-bit Fibonacci primitives picked for non-overlapping spectra so each
// subsystem's traffic looks distinct (helps the optimiser and parallel
// simulator see independent activity).
//==============================================================================
`ifndef LSD_PRBS_DRIVER_SV
`define LSD_PRBS_DRIVER_SV

module lsd_prbs_driver #(
    parameter int unsigned       WIDTH        = 32,
    parameter logic [WIDTH-1:0]  SEED         = 'h12345678,
    parameter logic [WIDTH-1:0]  POLY         = 'hEDB88320,
    parameter int unsigned       PULSE_PERIOD = 1   // pulse every N cycles
) (
    input  logic                 clk,
    input  logic                 rst_n,
    output logic [WIDTH-1:0]     prbs_data,
    output logic                 prbs_bit,
    output logic                 pulse
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

    // Free-running pulse divider (independent of the LFSR so the rate is
    // deterministic regardless of the polynomial).
    generate
        if (PULSE_PERIOD <= 1) begin : g_every_cycle
            assign pulse = 1'b1;
        end else begin : g_divider
            localparam int unsigned CW = $clog2(PULSE_PERIOD);
            logic [CW-1:0] cnt;
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)                       cnt <= '0;
                else if (cnt == PULSE_PERIOD - 1) cnt <= '0;
                else                              cnt <= cnt + 1'b1;
            end
            assign pulse = (cnt == PULSE_PERIOD - 1);
        end
    endgenerate
endmodule : lsd_prbs_driver

`endif // LSD_PRBS_DRIVER_SV
