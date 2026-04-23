//==============================================================================
// cnn_conv5x5_stride1.sv
// 5x5 convolution engine. 25 parallel MACs feed a 3-level adder tree.
//==============================================================================
module cnn_conv5x5_stride1 #(parameter int unsigned IW = 16,
                             parameter int unsigned WW = 16,
                             parameter int unsigned OW = 28) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,
    input  logic signed [IW-1:0]    x [0:24],
    input  logic signed [WW-1:0]    w [0:24],
    input  logic signed [OW-1:0]    bias,
    output logic signed [OW-1:0]    y,
    output logic                    valid
);
    logic signed [IW+WW-1:0]     p   [0:24];
    logic signed [IW+WW+2:0]     l1  [0:8];  // sums of triples
    logic signed [IW+WW+4:0]     l2  [0:2];
    logic signed [IW+WW+5:0]     sumall;

    always_comb begin
        for (int i = 0; i < 25; i++) p[i] = $signed(x[i]) * $signed(w[i]);
        // 9 groups of 3 (last contains only one entry)
        l1[0] = p[ 0] + p[ 1] + p[ 2];
        l1[1] = p[ 3] + p[ 4] + p[ 5];
        l1[2] = p[ 6] + p[ 7] + p[ 8];
        l1[3] = p[ 9] + p[10] + p[11];
        l1[4] = p[12] + p[13] + p[14];
        l1[5] = p[15] + p[16] + p[17];
        l1[6] = p[18] + p[19] + p[20];
        l1[7] = p[21] + p[22] + p[23];
        l1[8] = p[24];
        // 3 groups of 3
        l2[0] = l1[0] + l1[1] + l1[2];
        l2[1] = l1[3] + l1[4] + l1[5];
        l2[2] = l1[6] + l1[7] + l1[8];
        sumall = l2[0] + l2[1] + l2[2];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin y <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) y <= sumall[OW-1:0] + bias;
        end
    end
endmodule : cnn_conv5x5_stride1
