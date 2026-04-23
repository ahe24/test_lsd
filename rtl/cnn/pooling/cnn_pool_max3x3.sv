//==============================================================================
// cnn_pool_max3x3.sv  -  3x3 max pool (stride 1). Takes 9 inputs in parallel.
//==============================================================================
module cnn_pool_max3x3 #(parameter int unsigned W = 16) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  en,
    input  logic signed [W-1:0]   in_grid [0:8],
    output logic signed [W-1:0]   y,
    output logic                  valid
);
    // Tournament tree of 9 comparators
    logic signed [W-1:0] r1a, r1b, r1c, r1d, r1e;
    logic signed [W-1:0] r2a, r2b, r2c;
    logic signed [W-1:0] r3a;

    assign r1a = (in_grid[0] > in_grid[1]) ? in_grid[0] : in_grid[1];
    assign r1b = (in_grid[2] > in_grid[3]) ? in_grid[2] : in_grid[3];
    assign r1c = (in_grid[4] > in_grid[5]) ? in_grid[4] : in_grid[5];
    assign r1d = (in_grid[6] > in_grid[7]) ? in_grid[6] : in_grid[7];
    assign r1e = in_grid[8];

    assign r2a = (r1a > r1b) ? r1a : r1b;
    assign r2b = (r1c > r1d) ? r1c : r1d;
    assign r2c = r1e;

    logic signed [W-1:0] m_ab;
    assign m_ab = (r2a > r2b) ? r2a : r2b;
    assign r3a  = (m_ab > r2c) ? m_ab : r2c;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin y <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) y <= r3a;
        end
    end
endmodule : cnn_pool_max3x3
