//==============================================================================
// ecc_fp_add256.sv
// 256-bit prime-field addition mod p. Single cycle (combinational add + cond sub).
//==============================================================================
module ecc_fp_add256 (
    input  logic [255:0] a,
    input  logic [255:0] b,
    input  logic [255:0] p,
    output logic [255:0] r
);
    logic [256:0] s;
    logic [256:0] t;
    assign s = {1'b0, a} + {1'b0, b};
    assign t = s - {1'b0, p};
    assign r = (s >= {1'b0, p}) ? t[255:0] : s[255:0];
endmodule : ecc_fp_add256
