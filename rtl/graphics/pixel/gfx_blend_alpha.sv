//==============================================================================
// gfx_blend_alpha.sv
// OpenGL-style src-over alpha blending:
//   out = src.rgb * src.a + dst.rgb * (1 - src.a)
// 8-bit per channel, fixed point multiply + saturating add.
//==============================================================================
module gfx_blend_alpha (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic [31:0]         src_rgba,
    input  logic [31:0]         dst_rgba,
    output logic [31:0]         out_rgba,
    output logic                valid
);
    logic [7:0]  sr, sg, sb, sa, dr, dg, db, da;
    logic [7:0]  inv_sa;
    logic [15:0] out_r, out_g, out_b, out_a;

    assign sr = src_rgba[31:24]; assign sg = src_rgba[23:16];
    assign sb = src_rgba[15:8];  assign sa = src_rgba[7:0];
    assign dr = dst_rgba[31:24]; assign dg = dst_rgba[23:16];
    assign db = dst_rgba[15:8];  assign da = dst_rgba[7:0];
    assign inv_sa = 8'hFF - sa;

    assign out_r = (sr * sa + dr * inv_sa + 8'd127) >> 8;
    assign out_g = (sg * sa + dg * inv_sa + 8'd127) >> 8;
    assign out_b = (sb * sa + db * inv_sa + 8'd127) >> 8;
    assign out_a = (sa      + da * inv_sa + 8'd127) >> 8;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin out_rgba <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) begin
                out_rgba <= {
                    (out_r > 16'hFF) ? 8'hFF : out_r[7:0],
                    (out_g > 16'hFF) ? 8'hFF : out_g[7:0],
                    (out_b > 16'hFF) ? 8'hFF : out_b[7:0],
                    (out_a > 16'hFF) ? 8'hFF : out_a[7:0]
                };
            end
        end
    end
endmodule : gfx_blend_alpha
