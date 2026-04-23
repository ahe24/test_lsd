//==============================================================================
// aes_subbytes.sv  —  AES SubBytes over a 128-bit state (16 independent S-boxes)
//==============================================================================
module aes_subbytes (
    input  logic [127:0] state_in,
    output logic [127:0] state_out
);
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : g_sbox
            aes_sbox_combinational u_sbox (
                .in_byte (state_in [8*i +: 8]),
                .out_byte(state_out[8*i +: 8])
            );
        end
    endgenerate
endmodule : aes_subbytes
