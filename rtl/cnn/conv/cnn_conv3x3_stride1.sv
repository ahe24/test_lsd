//==============================================================================
// cnn_conv3x3_stride1.sv
// 3x3 convolution engine producing one output sample per cycle after the
// pipeline fill. 9 parallel MACs (Wallace), bias add, output saturation.
//==============================================================================
module cnn_conv3x3_stride1 #(parameter int unsigned IW = 16,
                             parameter int unsigned WW = 16,
                             parameter int unsigned OW = 24) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,
    input  logic signed [IW-1:0]    x [0:8],
    input  logic signed [WW-1:0]    w [0:8],
    input  logic signed [OW-1:0]    bias,
    output logic signed [OW-1:0]    y,
    output logic                    valid
);
    logic signed [IW+WW-1:0] p [0:8];
    logic signed [IW+WW+3:0] s012, s345, s678;
    logic signed [IW+WW+4:0] sall;

    always_comb begin
        for (int i = 0; i < 9; i++) p[i] = $signed(x[i]) * $signed(w[i]);
        s012 = p[0] + p[1] + p[2];
        s345 = p[3] + p[4] + p[5];
        s678 = p[6] + p[7] + p[8];
        sall = s012 + s345 + s678;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y <= '0; valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) begin
                logic signed [OW-1:0] t;
                t = sall[OW-1:0] + bias;
                y <= t;
            end
        end
    end
endmodule : cnn_conv3x3_stride1
