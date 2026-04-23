//==============================================================================
// sha3_rho_pi.sv  -  Rho and Pi steps of Keccak-f[1600]
//==============================================================================
module sha3_rho_pi (
    input  logic [63:0] state_in  [0:24],
    output logic [63:0] state_out [0:24]
);
    // Rotation offsets (Keccak-f[1600]), indexed by (x, y) linear position x+5*y
    localparam int ROT [0:24] = '{
         0,  1, 62, 28, 27,
        36, 44,  6, 55, 20,
         3, 10, 43, 25, 39,
        41, 45, 15, 21,  8,
        18,  2, 61, 56, 14
    };

    // Pi permutation maps (x,y) → (y, (2x+3y) mod 5). Implement mapping from
    // source (i) to destination (j).
    function automatic int pi_dst (input int i);
        automatic int x, y, xp, yp;
        x = i % 5; y = i / 5;
        xp = y;
        yp = (2*x + 3*y) % 5;
        return xp + 5*yp;
    endfunction

    // Rotate left
    function automatic logic [63:0] rol64 (input logic [63:0] v, input int n);
        rol64 = (v << n) | (v >> (64 - n));
    endfunction

    always_comb begin
        for (int i = 0; i < 25; i++) state_out[i] = 64'h0;
        for (int i = 0; i < 25; i++) begin
            automatic int d = pi_dst(i);
            state_out[d] = (ROT[i] == 0) ? state_in[i] : rol64(state_in[i], ROT[i]);
        end
    end
endmodule : sha3_rho_pi
