//==============================================================================
// cnn_pool_avg2x2.sv  -  2x2 average pool (stride 2). Symmetric rounding.
//==============================================================================
module cnn_pool_avg2x2 #(parameter int unsigned W = 16) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  en,
    input  logic signed [W-1:0]   a, b, c, d,
    output logic signed [W-1:0]   y,
    output logic                  valid
);
    logic signed [W+1:0] sum;
    assign sum = $signed(a) + $signed(b) + $signed(c) + $signed(d) + 2'sd2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin y <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) y <= sum[W+1:2];
        end
    end
endmodule : cnn_pool_avg2x2
