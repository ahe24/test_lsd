//==============================================================================
// gfx_edge_function.sv
// Computes the signed area / edge function used for barycentric coverage:
//   e(P) = (P.x - v0.x)*(v1.y - v0.y) - (P.y - v0.y)*(v1.x - v0.x)
// 32-bit inputs, 64-bit output.
//==============================================================================
module gfx_edge_function (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  v0x, v0y, v1x, v1y, px, py,
    output logic signed [63:0]  e_out,
    output logic                valid
);
    logic signed [63:0] dx1, dy1, dx2, dy2;
    always_comb begin
        dx1 = $signed(px - v0x) * $signed(v1y - v0y);
        dy1 = $signed(py - v0y) * $signed(v1x - v0x);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin e_out <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) e_out <= dx1 - dy1;
        end
    end
endmodule : gfx_edge_function
