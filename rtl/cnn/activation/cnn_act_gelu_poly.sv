//==============================================================================
// cnn_act_gelu_poly.sv
// GELU via the widely used polynomial approximation:
//   0.5 * x * (1 + tanh( sqrt(2/pi) * (x + 0.044715 * x^3) ))
// tanh is approximated with a simple clamp-and-mirror PWL (8 segments).
//==============================================================================
module cnn_act_gelu_poly (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [15:0]  x,     // Q4.12
    output logic signed [15:0]  y,     // Q4.12
    output logic                valid
);
    localparam logic signed [15:0] K_SQRT2_PI = 16'sd3268; // 0.7979 in Q4.12
    localparam logic signed [15:0] K_044715   = 16'sd183;  // 0.0447 in Q4.12

    logic signed [31:0] x2, x3, k_x3, inner;
    logic signed [31:0] inner_scaled;
    logic signed [15:0] tanh_in;
    logic signed [15:0] tanh_out;
    logic signed [31:0] one_plus, half_x;

    assign x2           = $signed(x) * $signed(x);
    assign x3           = (x2 >>> 12) * $signed(x);
    assign k_x3         = ((x3 >>> 12) * $signed(K_044715)) >>> 12;
    assign inner        = x + k_x3[15:0];
    assign inner_scaled = (inner * $signed(K_SQRT2_PI)) >>> 12;
    assign tanh_in      = inner_scaled[15:0];

    // PWL tanh: clamp to [-2,2] in Q4.12 and use a cheap polyline
    logic signed [15:0] at;
    logic signed [15:0] tanh_pos;
    assign at = tanh_in[15] ? -tanh_in : tanh_in;

    always_comb begin
        if      (at > 16'sd8192) tanh_pos = 16'sd4095;   // ~1.0
        else if (at > 16'sd4096) tanh_pos = 16'sd3686 + ((at - 16'sd4096) >>> 3);
        else if (at > 16'sd2048) tanh_pos = 16'sd3072 + ((at - 16'sd2048) >>> 2);
        else                     tanh_pos = at - (at >>> 3);
    end
    assign tanh_out = tanh_in[15] ? -tanh_pos : tanh_pos;

    // y = 0.5 * x * (1 + tanh_out). tanh_out is in Q4.12 so 4096 represents 1.
    assign one_plus = 16'sd4096 + tanh_out;
    assign half_x   = $signed(x) * $signed(one_plus);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) y <= half_x[28:13]; // >>13 = /(2*4096)
        end
    end
endmodule : cnn_act_gelu_poly
