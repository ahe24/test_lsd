//==============================================================================
// cnn_act_relu.sv
// Plain ReLU activation, signed fixed-point.
//==============================================================================
module cnn_act_relu #(parameter int unsigned W = 32) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [W-1:0] x,
    output logic signed [W-1:0] y,
    output logic                valid
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) y <= (x[W-1]) ? '0 : x;
        end
    end
endmodule : cnn_act_relu
