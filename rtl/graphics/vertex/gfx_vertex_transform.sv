//==============================================================================
// gfx_vertex_transform.sv
// Vertex transform block: MVP matrix multiply followed by perspective divide.
// Reciprocal of w is approximated via a Newton-Raphson seed LUT.
//==============================================================================
module gfx_vertex_transform (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  mvp [0:15],
    input  logic signed [31:0]  v_in [0:3],
    output logic signed [31:0]  v_out [0:3],
    output logic                valid
);
    logic signed [31:0] v_clip [0:3];
    logic               v_clip_valid;

    gfx_vec4_mul_mat4 u_mat (
        .clk(clk), .rst_n(rst_n), .en(en),
        .m(mvp), .v(v_in), .r(v_clip), .valid(v_clip_valid)
    );

    // Reciprocal of w using a 256-entry seed LUT over Q8.24
    logic [7:0]          w_top;
    logic signed [31:0]  inv_w_seed, inv_w_nr;
    logic signed [31:0]  w_reg [0:3];
    logic                v_reg_valid;

    logic [31:0] rec_lut [0:255];
    initial begin
        for (int k = 1; k < 256; k++) rec_lut[k] = int'(real'(1 << 24) / real'(k));
        rec_lut[0] = 32'hFFFFFFFF;
    end

    assign w_top      = v_clip[3][31-1 -: 8];
    assign inv_w_seed = $signed(rec_lut[w_top]);
    // 1 Newton-Raphson iter: x*(2 - w*x)   (all in Q8.24)
    logic signed [63:0] nr_prod;
    assign nr_prod    = ($signed(v_clip[3]) * $signed(inv_w_seed)) >>> 24;
    assign inv_w_nr   = ($signed(inv_w_seed) * ($signed(64'sd33554432) - nr_prod)) >>> 24;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 4; k++) v_out[k] <= '0;
            valid <= 1'b0;
        end else begin
            valid <= v_clip_valid;
            if (v_clip_valid) begin
                for (int k = 0; k < 3; k++) begin
                    logic signed [63:0] p;
                    p = $signed(v_clip[k]) * $signed(inv_w_nr);
                    v_out[k] <= p[55:24];
                end
                v_out[3] <= 32'sd16777216; // 1.0 in Q8.24
            end
        end
    end
endmodule : gfx_vertex_transform
