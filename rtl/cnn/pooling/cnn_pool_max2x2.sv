//==============================================================================
// cnn_pool_max2x2.sv  -  2x2 max pool (stride 2)
//==============================================================================
module cnn_pool_max2x2 #(parameter int unsigned W = 16) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  en,
    input  logic signed [W-1:0]   a,
    input  logic signed [W-1:0]   b,
    input  logic signed [W-1:0]   c,
    input  logic signed [W-1:0]   d,
    output logic signed [W-1:0]   y,
    output logic                  valid
);
    logic signed [W-1:0] t1, t2;
    assign t1 = (a > b) ? a : b;
    assign t2 = (c > d) ? c : d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin y <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) y <= (t1 > t2) ? t1 : t2;
        end
    end
endmodule : cnn_pool_max2x2
