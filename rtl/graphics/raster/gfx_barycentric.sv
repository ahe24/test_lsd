//==============================================================================
// gfx_barycentric.sv
// Computes barycentric weights for a triangle. Three parallel edge functions,
// then normalise by triangle signed area (inverse via 8-bit seed LUT + NR).
//==============================================================================
module gfx_barycentric (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  v0x, v0y,
    input  logic signed [31:0]  v1x, v1y,
    input  logic signed [31:0]  v2x, v2y,
    input  logic signed [31:0]  px,  py,
    output logic signed [31:0]  w0, w1, w2,
    output logic                valid,
    output logic                in_tri
);
    logic signed [63:0] e0, e1, e2;
    logic               ev0, ev1, ev2;

    gfx_edge_function u_e0 (.clk(clk), .rst_n(rst_n), .en(en),
                             .v0x(v1x), .v0y(v1y), .v1x(v2x), .v1y(v2y),
                             .px(px), .py(py), .e_out(e0), .valid(ev0));
    gfx_edge_function u_e1 (.clk(clk), .rst_n(rst_n), .en(en),
                             .v0x(v2x), .v0y(v2y), .v1x(v0x), .v1y(v0y),
                             .px(px), .py(py), .e_out(e1), .valid(ev1));
    gfx_edge_function u_e2 (.clk(clk), .rst_n(rst_n), .en(en),
                             .v0x(v0x), .v0y(v0y), .v1x(v1x), .v1y(v1y),
                             .px(px), .py(py), .e_out(e2), .valid(ev2));

    logic signed [63:0] area;
    always_comb area = e0 + e1 + e2;

    // Reciprocal area via LUT + 1 NR
    logic [31:0] rec_lut [0:255];
    initial begin
        for (int k = 1; k < 256; k++) rec_lut[k] = int'(real'(1 << 24) / real'(k));
        rec_lut[0] = 32'hFFFFFFFF;
    end

    logic [7:0]         area_top;
    logic signed [31:0] inv_a_seed;
    logic signed [63:0] nr_prod;
    logic signed [31:0] inv_a_nr;
    assign area_top   = area[31 -: 8];
    assign inv_a_seed = $signed(rec_lut[area_top]);
    assign nr_prod    = ($signed(area) * $signed(inv_a_seed)) >>> 24;
    assign inv_a_nr   = ($signed(inv_a_seed) * ($signed(64'sd33554432) - nr_prod)) >>> 24;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w0 <= '0; w1 <= '0; w2 <= '0;
            valid <= 1'b0; in_tri <= 1'b0;
        end else begin
            valid <= ev0;
            if (ev0) begin
                automatic logic signed [63:0] t0, t1, t2;
                t0 = ($signed(e0) * $signed(inv_a_nr)) >>> 24;
                t1 = ($signed(e1) * $signed(inv_a_nr)) >>> 24;
                t2 = ($signed(e2) * $signed(inv_a_nr)) >>> 24;
                w0 <= t0[31:0]; w1 <= t1[31:0]; w2 <= t2[31:0];
                in_tri <= (e0 >= 0) && (e1 >= 0) && (e2 >= 0);
            end
        end
    end
endmodule : gfx_barycentric
