//==============================================================================
// cnn_act_prelu.sv
// Parameterised (learnable) ReLU: y = x if x>=0 else alpha*x, where alpha is
// a per-channel signed 8-bit slope in Q1.7 format.
//==============================================================================
module cnn_act_prelu #(parameter int unsigned W = 32) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [W-1:0] x,
    input  logic signed [7:0]   alpha_q17,
    output logic signed [W-1:0] y,
    output logic                valid
);
    logic signed [W+7:0] scaled;
    assign scaled = $signed(x) * $signed(alpha_q17);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) begin
                if (x[W-1]) y <= scaled[W+6:7]; // shift-right by 7 (Q1.7)
                else        y <= x;
            end
        end
    end
endmodule : cnn_act_prelu
