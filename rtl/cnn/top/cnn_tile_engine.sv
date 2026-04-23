//==============================================================================
// cnn_tile_engine.sv
// A single CNN compute tile: an 8x8 systolic array followed by a bank of
// distinct activation functions wired in parallel, followed by a 2x2 avg pool.
//==============================================================================
module cnn_tile_engine #(parameter int TILE_ID = 0) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         en,
    input  logic         load_w,
    input  logic signed [15:0] w_flat   [0:63],
    input  logic signed [15:0] a_west   [0:7],
    input  logic signed [47:0] ps_north [0:7],
    output logic signed [15:0] act_out  [0:7],   // post-activation samples
    output logic signed [15:0] pool_out,
    output logic               valid
);
    logic signed [15:0] a_east   [0:7];
    logic signed [47:0] ps_south [0:7];

    cnn_mac_int16_systolic_array #(.R(8), .C(8)) u_sa (
        .clk     (clk),
        .rst_n   (rst_n),
        .load_w  (load_w),
        .w_flat  (w_flat),
        .a_west  (a_west),
        .ps_north(ps_north),
        .a_east  (a_east),
        .ps_south(ps_south)
    );

    // Drive 8 different activation functions (one per column) to maximise
    // logic diversity.
    logic signed [15:0] act [0:7];
    logic               v  [0:7];
    logic signed [15:0] trunc [0:7];
    genvar c;
    generate
        for (c = 0; c < 8; c++) begin : g_t
            assign trunc[c] = ps_south[c][23:8]; // crude Q8.8 reinterpretation
        end
    endgenerate

    cnn_act_relu        #(.W(16)) u_a0 (.clk(clk), .rst_n(rst_n), .en(en), .x(trunc[0]), .y(act[0]), .valid(v[0]));
    cnn_act_leaky_relu  #(.W(16)) u_a1 (.clk(clk), .rst_n(rst_n), .en(en), .x(trunc[1]), .y(act[1]), .valid(v[1]));
    cnn_act_prelu       #(.W(16)) u_a2 (.clk(clk), .rst_n(rst_n), .en(en), .x(trunc[2]), .alpha_q17(8'sd32), .y(act[2]), .valid(v[2]));
    cnn_act_sigmoid_plut           u_a3 (.clk(clk), .rst_n(rst_n), .en(en), .x(trunc[3]), .y({act[3]}), .valid(v[3]));
    cnn_act_tanh_cordic            u_a4 (.clk(clk), .rst_n(rst_n), .en(en), .x(trunc[4]), .y(act[4]), .valid(v[4]));
    cnn_act_gelu_poly              u_a5 (.clk(clk), .rst_n(rst_n), .en(en), .x(trunc[5]), .y(act[5]), .valid(v[5]));
    cnn_act_swish_hw    #(.W(16)) u_a6 (.clk(clk), .rst_n(rst_n), .en(en), .x(trunc[6]), .y(act[6]), .valid(v[6]));
    cnn_act_mish_approx            u_a7 (.clk(clk), .rst_n(rst_n), .en(en), .x(trunc[7]), .y(act[7]), .valid(v[7]));

    // 2x2 pooling of (act[0], act[1], act[2], act[3])
    logic signed [15:0] pool_y;
    logic               pool_v;
    cnn_pool_avg2x2 #(.W(16)) u_pool (
        .clk(clk), .rst_n(rst_n), .en(v[0]),
        .a(act[0]), .b(act[1]), .c(act[2]), .d(act[3]),
        .y(pool_y), .valid(pool_v)
    );

    genvar i;
    generate for (i = 0; i < 8; i++) assign act_out[i] = act[i]; endgenerate
    assign pool_out = pool_y;
    assign valid    = pool_v;
endmodule : cnn_tile_engine
