//==============================================================================
// cnn_conv_dilated7x7.sv
// 7x7 dilated convolution. The dilation is folded into the input routing —
// the arithmetic is a full 49-tap dot-product.
//==============================================================================
module cnn_conv_dilated7x7 #(parameter int unsigned IW = 16,
                             parameter int unsigned WW = 16,
                             parameter int unsigned OW = 32) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,
    input  logic signed [IW-1:0]    x [0:48],
    input  logic signed [WW-1:0]    w [0:48],
    input  logic signed [OW-1:0]    bias,
    output logic signed [OW-1:0]    y,
    output logic                    valid
);
    logic signed [IW+WW-1:0] p [0:48];
    logic signed [IW+WW+3:0] l1 [0:15]; // stage-1 partial sums
    logic signed [IW+WW+5:0] l2 [0:3];
    logic signed [IW+WW+7:0] total;

    always_comb begin
        for (int i = 0; i < 49; i++) p[i] = $signed(x[i]) * $signed(w[i]);
        // 15 sums of 3 (+ last single)
        for (int j = 0; j < 15; j++) begin
            l1[j] = p[j*3] + p[j*3+1] + p[j*3+2];
        end
        // l1[15] unused: include the 49th product into l1[15]? We have 15 triples = 45 products.
        // Put last 4 (p[45..48]) into l2 manually
        l2[0] = l1[0]  + l1[1]  + l1[2]  + l1[3];
        l2[1] = l1[4]  + l1[5]  + l1[6]  + l1[7];
        l2[2] = l1[8]  + l1[9]  + l1[10] + l1[11];
        l2[3] = l1[12] + l1[13] + l1[14] + p[45] + p[46] + p[47] + p[48];
        total = l2[0] + l2[1] + l2[2] + l2[3];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin y <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) y <= total[OW-1:0] + bias;
        end
    end
endmodule : cnn_conv_dilated7x7
