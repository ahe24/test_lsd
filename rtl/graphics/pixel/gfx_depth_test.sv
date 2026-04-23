//==============================================================================
// gfx_depth_test.sv
// Compare incoming fragment depth against depth buffer value (less-equal).
//==============================================================================
module gfx_depth_test (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic [31:0]         frag_depth,
    input  logic [31:0]         buf_depth,
    output logic [31:0]         new_depth,
    output logic                pass,
    output logic                valid
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            new_depth <= '0; pass <= 1'b0; valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) begin
                if (frag_depth <= buf_depth) begin
                    pass <= 1'b1;
                    new_depth <= frag_depth;
                end else begin
                    pass <= 1'b0;
                    new_depth <= buf_depth;
                end
            end
        end
    end
endmodule : gfx_depth_test
