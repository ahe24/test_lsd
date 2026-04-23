//==============================================================================
// calu_mat_mul_8x8.sv
// 8x8 × 8x8 real matrix multiply in Q16.16. Fully unrolled 512 MACs.
//==============================================================================
module calu_mat_mul_8x8 (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 en,
    input  logic signed [31:0]   A [0:7][0:7],
    input  logic signed [31:0]   B [0:7][0:7],
    output logic signed [31:0]   C [0:7][0:7],
    output logic                 valid
);
    genvar i, j, k;
    generate
        for (i = 0; i < 8; i++) begin : g_row
            for (j = 0; j < 8; j++) begin : g_col
                logic signed [63:0] acc;
                always_comb begin
                    acc = 64'sd0;
                    for (int kk = 0; kk < 8; kk++) begin
                        acc += ($signed(A[i][kk]) * $signed(B[kk][j])) >>> 16;
                    end
                end
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) C[i][j] <= '0;
                    else if (en) C[i][j] <= acc[31:0];
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) valid <= 1'b0; else valid <= en;
endmodule : calu_mat_mul_8x8
