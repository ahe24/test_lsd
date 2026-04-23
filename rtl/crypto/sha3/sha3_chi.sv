//==============================================================================
// sha3_chi.sv  -  Chi step of Keccak-f[1600]
//==============================================================================
module sha3_chi (
    input  logic [63:0] state_in  [0:24],
    output logic [63:0] state_out [0:24]
);
    always_comb begin
        for (int y = 0; y < 5; y++) begin
            for (int x = 0; x < 5; x++) begin
                automatic int xp1 = (x + 1) % 5;
                automatic int xp2 = (x + 2) % 5;
                state_out[x + 5*y] = state_in[x + 5*y]
                                    ^ (~state_in[xp1 + 5*y] & state_in[xp2 + 5*y]);
            end
        end
    end
endmodule : sha3_chi
