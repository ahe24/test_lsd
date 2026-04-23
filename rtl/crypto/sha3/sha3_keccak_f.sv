//==============================================================================
// sha3_keccak_f.sv
// Fully unrolled 24-round Keccak-f[1600] permutation. One combinational
// datapath — pipelined by a single register on the output.
//==============================================================================
module sha3_keccak_f (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          en,
    input  logic [63:0]   state_in  [0:24],
    output logic [63:0]   state_out [0:24],
    output logic          valid
);
    logic [63:0] wires [0:24][0:24];

    genvar r, i;
    generate
        for (i = 0; i < 25; i++) begin : g_in
            assign wires[0][i] = state_in[i];
        end
        for (r = 0; r < 24; r++) begin : g_r
            sha3_round u_r (
                .round_idx(r[4:0]),
                .state_in (wires[r]),
                .state_out(wires[r+1])
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 1'b0;
            for (int k = 0; k < 25; k++) state_out[k] <= '0;
        end else begin
            valid <= en;
            if (en) begin
                for (int k = 0; k < 25; k++) state_out[k] <= wires[24][k];
            end
        end
    end
endmodule : sha3_keccak_f
