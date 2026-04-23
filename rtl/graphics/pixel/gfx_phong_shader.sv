//==============================================================================
// gfx_phong_shader.sv
// Simplified Phong shader: computes diffuse + specular from unit normal N,
// light direction L, view direction V. Everything in Q2.14 fixed-point.
// Specular uses an 8-term Maclaurin approximation of pow(x, 16).
//==============================================================================
module gfx_phong_shader (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [15:0]  nx, ny, nz,     // normal  (Q2.14)
    input  logic signed [15:0]  lx, ly, lz,     // light   (Q2.14)
    input  logic signed [15:0]  vx, vy, vz,     // view    (Q2.14)
    input  logic [7:0]          mat_diffuse,
    input  logic [7:0]          mat_specular,
    output logic [7:0]          shade,
    output logic                valid
);
    logic signed [31:0] ndotl, rdotv, two_ndotl;
    logic signed [15:0] rx, ry, rz;
    logic signed [15:0] diff_q;

    assign ndotl     = ($signed(nx)*lx + $signed(ny)*ly + $signed(nz)*lz) >>> 14;
    assign two_ndotl = ndotl <<< 1;
    // Reflected = 2*(N.L)*N - L
    assign rx = ((two_ndotl * nx) >>> 14) - lx;
    assign ry = ((two_ndotl * ny) >>> 14) - ly;
    assign rz = ((two_ndotl * nz) >>> 14) - lz;
    assign rdotv = ($signed(rx)*vx + $signed(ry)*vy + $signed(rz)*vz) >>> 14;

    // Clamp negative to 0
    logic signed [15:0] d_c, s_c;
    assign d_c = (ndotl < 0) ? 16'sd0 : ndotl[15:0];
    assign s_c = (rdotv < 0) ? 16'sd0 : rdotv[15:0];

    // pow16 ≈ x^16 via 4 successive squares
    logic signed [15:0] s2, s4, s8, s16;
    assign s2  = ($signed(s_c)*s_c) >>> 14;
    assign s4  = ($signed(s2)*s2)  >>> 14;
    assign s8  = ($signed(s4)*s4)  >>> 14;
    assign s16 = ($signed(s8)*s8)  >>> 14;

    // Combine
    logic [23:0] mix;
    assign mix = mat_diffuse  * $unsigned(d_c[14:7])
               + mat_specular * $unsigned(s16[14:7]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin shade <= '0; valid <= 1'b0; end
        else begin
            valid <= en;
            if (en) shade <= (mix[23:8] > 16'hFF) ? 8'hFF : mix[15:8];
        end
    end
endmodule : gfx_phong_shader
