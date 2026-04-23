//==============================================================================
// gfx_tex_bilinear.sv
// 2x2 bilinear texture filter. Consumes 4 texel RGBA samples and two Q0.8
// fractional weights; produces bilinearly filtered RGBA.
//==============================================================================
module gfx_tex_bilinear (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic [31:0]         t00,     // RGBA at (i,   j)
    input  logic [31:0]         t10,     // RGBA at (i+1, j)
    input  logic [31:0]         t01,     // RGBA at (i,   j+1)
    input  logic [31:0]         t11,     // RGBA at (i+1, j+1)
    input  logic [7:0]          fx,      // Q0.8 fraction
    input  logic [7:0]          fy,
    output logic [31:0]         rgba,
    output logic                valid
);
    logic [7:0] ifx, ify;
    assign ifx = 8'hFF - fx;
    assign ify = 8'hFF - fy;

    genvar ch;
    logic [7:0] out_ch [0:3];
    generate
        for (ch = 0; ch < 4; ch++) begin : g_ch
            logic [7:0]  a, b, c, d;
            logic [15:0] ab, cd, abf, cdf, yabcd;
            assign a   = t00[31 - 8*ch -: 8];
            assign b   = t10[31 - 8*ch -: 8];
            assign c   = t01[31 - 8*ch -: 8];
            assign d   = t11[31 - 8*ch -: 8];
            assign ab  = a * ifx + b * fx + 8'd127;
            assign cd  = c * ifx + d * fx + 8'd127;
            assign abf = ab >> 8;
            assign cdf = cd >> 8;
            assign yabcd = abf[7:0] * ify + cdf[7:0] * fy + 8'd127;
            assign out_ch[ch] = yabcd[15:8];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rgba <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) rgba <= {out_ch[0], out_ch[1], out_ch[2], out_ch[3]};
        end
    end
endmodule : gfx_tex_bilinear
