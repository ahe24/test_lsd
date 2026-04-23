//==============================================================================
// cnn_act_swish_hw.sv
// Hard Swish: y = x * relu6(x + 3) / 6. All fixed point, no multiplier-free
// shortcuts taken on purpose so the simulator has arithmetic to grind on.
//==============================================================================
module cnn_act_swish_hw #(parameter int unsigned W = 16) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [W-1:0] x,     // Q8.8
    output logic signed [W-1:0] y,     // Q8.8
    output logic                valid
);
    logic signed [W:0]   x_plus_3;
    logic signed [W:0]   clamped;
    logic signed [2*W:0] prod;
    logic signed [W-1:0] scaled;

    assign x_plus_3 = $signed({x[W-1], x}) + $signed({{(W-10){1'b0}}, 10'd768}); // 3.0 in Q8.8 = 768

    always_comb begin
        if ($signed(x_plus_3) < 0)                     clamped = '0;
        else if ($signed(x_plus_3) > 17'sd1536)        clamped = 17'sd1536;
        else                                           clamped = x_plus_3;
    end

    assign prod   = $signed(x) * $signed(clamped);
    // Divide by 6 in Q8.8 → shift right 8 then divide by 6
    // Implement /6 as *10923 >> 16  (≈ 1/6)
    assign scaled = (prod * 17'sd10923) >>> (16 + 8);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) y <= scaled;
        end
    end
endmodule : cnn_act_swish_hw
