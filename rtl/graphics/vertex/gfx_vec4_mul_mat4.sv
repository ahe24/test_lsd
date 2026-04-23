//==============================================================================
// gfx_vec4_mul_mat4.sv
// 4x4 matrix × 4x1 vector multiplication in Q8.24 fixed-point. 16 parallel
// MACs, 2-level adder tree, saturating output.
//==============================================================================
module gfx_vec4_mul_mat4 (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 en,
    input  logic signed [31:0]   m [0:15],    // row-major
    input  logic signed [31:0]   v [0:3],
    output logic signed [31:0]   r [0:3],
    output logic                 valid
);
    genvar row;
    generate
        for (row = 0; row < 4; row++) begin : g_row
            logic signed [63:0] p0, p1, p2, p3;
            logic signed [63:0] s01, s23, sum;
            assign p0  = $signed(m[4*row+0]) * $signed(v[0]);
            assign p1  = $signed(m[4*row+1]) * $signed(v[1]);
            assign p2  = $signed(m[4*row+2]) * $signed(v[2]);
            assign p3  = $signed(m[4*row+3]) * $signed(v[3]);
            assign s01 = p0 + p1;
            assign s23 = p2 + p3;
            assign sum = s01 + s23;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) r[row] <= '0;
                else if (en) begin
                    logic signed [63:0] scaled;
                    scaled = sum >>> 24;
                    if      (scaled >  64'sh7FFFFFFF) r[row] <= 32'h7FFFFFFF;
                    else if (scaled < -64'sh80000000) r[row] <= 32'h80000000;
                    else                              r[row] <= scaled[31:0];
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) valid <= 1'b0; else valid <= en;
endmodule : gfx_vec4_mul_mat4
