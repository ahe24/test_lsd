//==============================================================================
// rsa_adder_4096.sv
// 4096-bit carry-select adder built from 32 blocks of 128 bits each.
// Structure kept explicit (no '+' on the full 4097-bit vector).
//==============================================================================
module rsa_adder_4096 (
    input  logic [4095:0] a,
    input  logic [4095:0] b,
    input  logic          cin,
    output logic [4095:0] sum,
    output logic          cout
);
    localparam int BLK = 128;
    localparam int N   = 4096 / BLK;

    logic [N:0]          carry;
    logic [BLK-1:0]      sum_blk [0:N-1];

    assign carry[0] = cin;
    genvar i;
    generate
        for (i = 0; i < N; i++) begin : g_blk
            logic [BLK-1:0] sum0, sum1;
            logic           c0, c1;
            assign {c0, sum0} = {1'b0, a[i*BLK +: BLK]} + {1'b0, b[i*BLK +: BLK]} + 1'b0;
            assign {c1, sum1} = {1'b0, a[i*BLK +: BLK]} + {1'b0, b[i*BLK +: BLK]} + 1'b1;
            assign sum_blk[i] = carry[i] ? sum1 : sum0;
            assign carry[i+1] = carry[i] ? c1   : c0;
            assign sum[i*BLK +: BLK] = sum_blk[i];
        end
    endgenerate

    assign cout = carry[N];
endmodule : rsa_adder_4096
