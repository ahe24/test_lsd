//==============================================================================
// gfx_top.sv
// Graphics subsystem top: vertex transform → tile rasterizer → shader/blend
// stages for a bank of fragments.
//==============================================================================
module gfx_top (
    input  logic                clk,
    input  logic                rst_n,
    lsd_cmd_if.slave            cmd_if,
    lsd_stream_if.consumer      in_s,
    lsd_stream_if.producer      out_s
);
    import lsd_pkg::*;

    // Simple register-file fed by commands
    logic signed [31:0] mvp [0:15];
    logic signed [31:0] v_in [0:3];
    logic signed [31:0] v_out [0:3];
    logic               vtx_v;
    logic               vtx_en;

    gfx_vertex_transform u_vtx (
        .clk(clk), .rst_n(rst_n), .en(vtx_en),
        .mvp(mvp), .v_in(v_in), .v_out(v_out), .valid(vtx_v)
    );

    // Three transformed vertices feed rasterizer
    logic signed [31:0] tv0x, tv0y, tv1x, tv1y, tv2x, tv2y;
    logic signed [31:0] tile_x, tile_y;
    logic pix_v;
    logic signed [31:0] pix_x, pix_y, bw0, bw1, bw2;
    logic               rast_done;
    logic               rast_start;

    gfx_tile_rasterizer u_rast (
        .clk(clk), .rst_n(rst_n), .start(rast_start),
        .v0x(tv0x), .v0y(tv0y), .v1x(tv1x), .v1y(tv1y), .v2x(tv2x), .v2y(tv2y),
        .tile_x(tile_x), .tile_y(tile_y),
        .pix_valid(pix_v), .pix_x(pix_x), .pix_y(pix_y),
        .bary_w0(bw0), .bary_w1(bw1), .bary_w2(bw2),
        .done(rast_done)
    );

    // Bank of 8 uniquely-instanced phong shaders (different material seeds)
    logic [7:0] shade_val [0:7];
    logic       shade_v   [0:7];
    genvar s;
    generate
        for (s = 0; s < 8; s++) begin : g_sh
            gfx_phong_shader u_sh (
                .clk(clk), .rst_n(rst_n), .en(pix_v),
                .nx(16'sh2000), .ny(16'sh2000), .nz(16'sh2000),
                .lx(16'sh3000 + s[15:0]), .ly(16'sh3000 - s[15:0]), .lz(16'sh2000),
                .vx(16'sh2000), .vy(16'sh2000), .vz(16'sh4000),
                .mat_diffuse (8'h80 + s[7:0]*8'h05),
                .mat_specular(8'hC0 - s[7:0]*8'h03),
                .shade(shade_val[s]), .valid(shade_v[s])
            );
        end
    endgenerate

    // Alpha-blend 4 fragments pairwise, tex-filter one stream
    logic [31:0] frag_src_rgba;
    logic [31:0] frag_dst_rgba;
    logic [31:0] blended;
    logic        blended_v;
    assign frag_src_rgba = {shade_val[0], shade_val[1], shade_val[2], shade_val[3]};
    assign frag_dst_rgba = {shade_val[4], shade_val[5], shade_val[6], shade_val[7]};
    gfx_blend_alpha u_blend (
        .clk(clk), .rst_n(rst_n), .en(shade_v[0]),
        .src_rgba(frag_src_rgba), .dst_rgba(frag_dst_rgba),
        .out_rgba(blended), .valid(blended_v)
    );

    logic [31:0] tex_rgba;
    logic        tex_v;
    gfx_tex_bilinear u_tex (
        .clk(clk), .rst_n(rst_n), .en(blended_v),
        .t00(blended), .t10(frag_src_rgba), .t01(frag_dst_rgba),
        .t11(blended ^ 32'hA5A5A5A5),
        .fx(pix_x[7:0]), .fy(pix_y[7:0]),
        .rgba(tex_rgba), .valid(tex_v)
    );

    // Command decode: register-write to the MVP/vertex file
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
            vtx_en     <= 1'b0;
            rast_start <= 1'b0;
            tile_x <= '0; tile_y <= '0;
            tv0x <= '0; tv0y <= '0; tv1x <= '0; tv1y <= '0; tv2x <= '0; tv2y <= '0;
            for (int k = 0; k < 16; k++) mvp[k] <= '0;
            for (int k = 0; k < 4;  k++) v_in[k] <= '0;
        end else begin
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
            vtx_en     <= 1'b0;
            rast_start <= 1'b0;
            if (cmd_if.cmd_valid && cmd_if.cmd_ready) begin
                case (cmd_if.cmd.addr[7:5])
                    3'd0: mvp [cmd_if.cmd.addr[4:1]] <= cmd_if.cmd.data[31:0];
                    3'd1: v_in[cmd_if.cmd.addr[3:1]] <= cmd_if.cmd.data[31:0];
                    3'd2: begin
                        case (cmd_if.cmd.addr[4:2])
                            3'd0: tv0x <= cmd_if.cmd.data[31:0];
                            3'd1: tv0y <= cmd_if.cmd.data[31:0];
                            3'd2: tv1x <= cmd_if.cmd.data[31:0];
                            3'd3: tv1y <= cmd_if.cmd.data[31:0];
                            3'd4: tv2x <= cmd_if.cmd.data[31:0];
                            3'd5: tv2y <= cmd_if.cmd.data[31:0];
                            3'd6: tile_x <= cmd_if.cmd.data[31:0];
                            3'd7: tile_y <= cmd_if.cmd.data[31:0];
                        endcase
                    end
                    3'd3: begin
                        vtx_en     <= (cmd_if.cmd.op == OP_KICK);
                        rast_start <= (cmd_if.cmd.op == OP_KICK);
                    end
                    default: ;
                endcase
                cmd_if.rsp_valid <= 1'b1;
                cmd_if.rsp       <= '{tag: cmd_if.cmd.tag, sub: SUB_GFX, err: 1'b0, data: {32'h0, tex_rgba}};
            end
        end
    end

    assign in_s.ready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_s.valid <= 1'b0; out_s.data <= '0;
            out_s.sop <= 0; out_s.eop <= 0; out_s.keep <= '1;
        end else begin
            out_s.valid <= tex_v;
            out_s.sop   <= 1'b1;
            out_s.eop   <= 1'b1;
            out_s.keep  <= '1;
            out_s.data  <= {16{tex_rgba}};
        end
    end
endmodule : gfx_top
