//==============================================================================
// calu_fp_sub.sv  -  Fixed-point complex subtraction
//==============================================================================
module calu_fp_sub (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  ar, ai,
    input  logic signed [31:0]  br, bi,
    output logic signed [31:0]  yr, yi,
    output logic                valid
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin yr <= '0; yi <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) begin
                yr <= ar - br;
                yi <= ai - bi;
            end
        end
    end
endmodule : calu_fp_sub
