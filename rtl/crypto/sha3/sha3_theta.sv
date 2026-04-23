//==============================================================================
// sha3_theta.sv  -  Theta step of Keccak-f[1600]
//==============================================================================
module sha3_theta (
    input  logic [63:0] state_in  [0:24],
    output logic [63:0] state_out [0:24]
);
    logic [63:0] C [0:4];
    logic [63:0] D [0:4];

    always_comb begin
        for (int x = 0; x < 5; x++) begin
            C[x] = state_in[x] ^ state_in[x+5] ^ state_in[x+10]
                 ^ state_in[x+15] ^ state_in[x+20];
        end
        for (int x = 0; x < 5; x++) begin
            automatic int xm1 = (x + 4) % 5;
            automatic int xp1 = (x + 1) % 5;
            D[x] = C[xm1] ^ { C[xp1][62:0], C[xp1][63] };
        end
        for (int y = 0; y < 5; y++) begin
            for (int x = 0; x < 5; x++) begin
                state_out[x + 5*y] = state_in[x + 5*y] ^ D[x];
            end
        end
    end
endmodule : sha3_theta
