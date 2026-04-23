//==============================================================================
// calu_fp_mul.sv
// Fixed-point complex multiplication (3-multiplier Gauss scheme):
//   yr = ar*br - ai*bi
//   yi = (ar+ai)*(br+bi) - ar*br - ai*bi
//==============================================================================
module calu_fp_mul (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  ar, ai,
    input  logic signed [31:0]  br, bi,
    output logic signed [31:0]  yr, yi,
    output logic                valid
);
    logic signed [63:0] p1, p2, p3;
    assign p1 = $signed(ar) * $signed(br);
    assign p2 = $signed(ai) * $signed(bi);
    assign p3 = $signed(ar + ai) * $signed(br + bi);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin yr <= '0; yi <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) begin
                yr <= (p1 - p2) >>> 16;
                yi <= (p3 - p1 - p2) >>> 16;
            end
        end
    end
endmodule : calu_fp_mul
