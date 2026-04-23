//==============================================================================
// cnn_conv_depthwise3x3.sv
// 3x3 depthwise convolution over C=8 parallel channels. Each channel has its
// own 9 weights and 9 inputs — no cross-channel reduction.
//==============================================================================
module cnn_conv_depthwise3x3 #(parameter int unsigned IW = 16,
                               parameter int unsigned WW = 16,
                               parameter int unsigned OW = 24,
                               parameter int unsigned C  = 8) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 en,
    input  logic signed [IW-1:0] x [0:C*9-1],
    input  logic signed [WW-1:0] w [0:C*9-1],
    input  logic signed [OW-1:0] bias [0:C-1],
    output logic signed [OW-1:0] y    [0:C-1],
    output logic                 valid
);
    genvar c;
    generate
        for (c = 0; c < C; c++) begin : g_ch
            logic signed [IW-1:0]  xc [0:8];
            logic signed [WW-1:0]  wc [0:8];
            logic signed [OW-1:0]  yc;
            logic                  vc;
            for (genvar ix = 0; ix < 9; ix++) begin : g_wire
                assign xc[ix] = x[c*9 + ix];
                assign wc[ix] = w[c*9 + ix];
            end
            cnn_conv3x3_stride1 #(.IW(IW), .WW(WW), .OW(OW)) u_conv (
                .clk  (clk),
                .rst_n(rst_n),
                .en   (en),
                .x    (xc),
                .w    (wc),
                .bias (bias[c]),
                .y    (yc),
                .valid(vc)
            );
            assign y[c] = yc;
            if (c == 0) assign valid = vc;
        end
    endgenerate
endmodule : cnn_conv_depthwise3x3
