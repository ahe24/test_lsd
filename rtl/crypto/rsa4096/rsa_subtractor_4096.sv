//==============================================================================
// rsa_subtractor_4096.sv
// 4096-bit subtractor (a - b). borrow-out indicates a<b.
//==============================================================================
module rsa_subtractor_4096 (
    input  logic [4095:0] a,
    input  logic [4095:0] b,
    output logic [4095:0] diff,
    output logic          borrow
);
    logic [4096:0] x;
    assign x = {1'b0, a} - {1'b0, b};
    assign diff   = x[4095:0];
    assign borrow = x[4096];
endmodule : rsa_subtractor_4096
