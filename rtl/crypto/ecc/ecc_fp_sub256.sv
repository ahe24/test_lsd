//==============================================================================
// ecc_fp_sub256.sv  -  256-bit field subtraction (a - b) mod p
//==============================================================================
module ecc_fp_sub256 (
    input  logic [255:0] a,
    input  logic [255:0] b,
    input  logic [255:0] p,
    output logic [255:0] r
);
    logic [256:0] d;
    assign d = {1'b0, a} - {1'b0, b};
    assign r = d[256] ? (a + p - b) : d[255:0];
endmodule : ecc_fp_sub256
