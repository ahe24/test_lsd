//==============================================================================
// cnn_act_leaky_relu.sv
// Leaky ReLU with a 0.125× negative slope (i.e., >>3 on negative inputs).
//==============================================================================
module cnn_act_leaky_relu #(parameter int unsigned W = 32) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [W-1:0] x,
    output logic signed [W-1:0] y,
    output logic                valid
);
    logic signed [W-1:0] neg_branch;
    assign neg_branch = x >>> 3; // arithmetic shift preserves sign

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) y <= (x[W-1]) ? neg_branch : x;
        end
    end
endmodule : cnn_act_leaky_relu
