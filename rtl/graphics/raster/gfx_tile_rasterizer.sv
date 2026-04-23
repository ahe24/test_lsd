//==============================================================================
// gfx_tile_rasterizer.sv
// Iterates a 16x16 pixel tile, computing barycentric weights for a triangle.
// Emits covered pixels as a stream.
//==============================================================================
module gfx_tile_rasterizer (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                start,
    input  logic signed [31:0]  v0x, v0y, v1x, v1y, v2x, v2y,
    input  logic signed [31:0]  tile_x, tile_y,
    output logic                pix_valid,
    output logic signed [31:0]  pix_x, pix_y,
    output logic signed [31:0]  bary_w0, bary_w1, bary_w2,
    output logic                done
);
    logic [4:0] sx, sy;
    typedef enum logic [1:0] {S_IDLE, S_STEP, S_DONE} st_e;
    st_e st;

    logic signed [31:0] px, py;
    logic signed [31:0] w0_w, w1_w, w2_w;
    logic               bv, in_tri;
    gfx_barycentric u_b (
        .clk(clk), .rst_n(rst_n), .en(1'b1),
        .v0x(v0x), .v0y(v0y), .v1x(v1x), .v1y(v1y), .v2x(v2x), .v2y(v2y),
        .px(px), .py(py),
        .w0(w0_w), .w1(w1_w), .w2(w2_w), .valid(bv), .in_tri(in_tri)
    );

    assign px = tile_x + {27'h0, sx};
    assign py = tile_y + {27'h0, sy};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; sx <= '0; sy <= '0;
            pix_valid <= 1'b0; done <= 1'b0;
            pix_x <= '0; pix_y <= '0; bary_w0 <= '0; bary_w1 <= '0; bary_w2 <= '0;
        end else begin
            pix_valid <= 1'b0; done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin sx <= 0; sy <= 0; st <= S_STEP; end
                S_STEP: begin
                    if (bv && in_tri) begin
                        pix_valid <= 1'b1;
                        pix_x <= px; pix_y <= py;
                        bary_w0 <= w0_w; bary_w1 <= w1_w; bary_w2 <= w2_w;
                    end
                    if (sx == 5'd15) begin
                        sx <= 0;
                        if (sy == 5'd15) begin st <= S_DONE; end
                        else sy <= sy + 1'b1;
                    end else sx <= sx + 1'b1;
                end
                S_DONE: begin done <= 1'b1; st <= S_IDLE; end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : gfx_tile_rasterizer
