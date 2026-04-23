//==============================================================================
// aes_mixcolumns.sv  -  AES MixColumns. Explicit xtime multiplier per byte.
//==============================================================================
module aes_mixcolumns (
    input  logic [127:0] state_in,
    output logic [127:0] state_out
);
    function automatic logic [7:0] xt (input logic [7:0] a);
        xt = (a[7]) ? ((a << 1) ^ 8'h1b) : (a << 1);
    endfunction

    genvar c;
    generate
        for (c = 0; c < 4; c++) begin : g_col
            logic [7:0] a0, a1, a2, a3;
            logic [7:0] r0, r1, r2, r3;
            assign a0 = state_in[32*c + 0  +: 8];
            assign a1 = state_in[32*c + 8  +: 8];
            assign a2 = state_in[32*c + 16 +: 8];
            assign a3 = state_in[32*c + 24 +: 8];
            assign r0 = xt(a0) ^ (xt(a1) ^ a1) ^ a2 ^ a3;
            assign r1 = a0 ^ xt(a1) ^ (xt(a2) ^ a2) ^ a3;
            assign r2 = a0 ^ a1 ^ xt(a2) ^ (xt(a3) ^ a3);
            assign r3 = (xt(a0) ^ a0) ^ a1 ^ a2 ^ xt(a3);
            assign state_out[32*c + 0  +: 8] = r0;
            assign state_out[32*c + 8  +: 8] = r1;
            assign state_out[32*c + 16 +: 8] = r2;
            assign state_out[32*c + 24 +: 8] = r3;
        end
    endgenerate
endmodule : aes_mixcolumns
