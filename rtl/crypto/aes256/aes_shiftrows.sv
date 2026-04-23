//==============================================================================
// aes_shiftrows.sv  -  AES ShiftRows
//==============================================================================
module aes_shiftrows (
    input  logic [127:0] state_in,
    output logic [127:0] state_out
);
    // State is column-major: bytes 0..3 = column 0 rows 0..3 etc.
    logic [7:0] s [0:15];
    logic [7:0] o [0:15];
    genvar g;
    generate
        for (g = 0; g < 16; g++) assign s[g] = state_in[8*g +: 8];
    endgenerate

    // row 0: no shift      row 1: shift left 1
    // row 2: shift left 2  row 3: shift left 3
    assign o[ 0] = s[ 0]; assign o[ 4] = s[ 4]; assign o[ 8] = s[ 8]; assign o[12] = s[12];
    assign o[ 1] = s[ 5]; assign o[ 5] = s[ 9]; assign o[ 9] = s[13]; assign o[13] = s[ 1];
    assign o[ 2] = s[10]; assign o[ 6] = s[14]; assign o[10] = s[ 2]; assign o[14] = s[ 6];
    assign o[ 3] = s[15]; assign o[ 7] = s[ 3]; assign o[11] = s[ 7]; assign o[15] = s[11];

    generate
        for (g = 0; g < 16; g++) assign state_out[8*g +: 8] = o[g];
    endgenerate
endmodule : aes_shiftrows
