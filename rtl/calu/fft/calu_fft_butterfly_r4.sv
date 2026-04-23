//==============================================================================
// calu_fft_butterfly_r4.sv
// Radix-4 DIT butterfly: 4 complex inputs, 3 complex twiddles, 4 outputs.
// Uses 3 calu_fp_mul units plus four calu_fp_add / calu_fp_sub pipelines —
// lots of distinct hierarchy to elaborate.
//==============================================================================
module calu_fft_butterfly_r4 (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  x0r, x0i,
    input  logic signed [31:0]  x1r, x1i,
    input  logic signed [31:0]  x2r, x2i,
    input  logic signed [31:0]  x3r, x3i,
    input  logic signed [31:0]  w1r, w1i,
    input  logic signed [31:0]  w2r, w2i,
    input  logic signed [31:0]  w3r, w3i,
    output logic signed [31:0]  y0r, y0i,
    output logic signed [31:0]  y1r, y1i,
    output logic signed [31:0]  y2r, y2i,
    output logic signed [31:0]  y3r, y3i,
    output logic                valid
);
    logic signed [31:0] p1r, p1i, p2r, p2i, p3r, p3i;
    logic               v1, v2, v3;

    calu_fp_mul u_m1 (.clk(clk), .rst_n(rst_n), .en(en),
                      .ar(x1r), .ai(x1i), .br(w1r), .bi(w1i),
                      .yr(p1r), .yi(p1i), .valid(v1));
    calu_fp_mul u_m2 (.clk(clk), .rst_n(rst_n), .en(en),
                      .ar(x2r), .ai(x2i), .br(w2r), .bi(w2i),
                      .yr(p2r), .yi(p2i), .valid(v2));
    calu_fp_mul u_m3 (.clk(clk), .rst_n(rst_n), .en(en),
                      .ar(x3r), .ai(x3i), .br(w3r), .bi(w3i),
                      .yr(p3r), .yi(p3i), .valid(v3));

    // Stage 2: DFT-4 combine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y0r <= '0; y0i <= '0; y1r <= '0; y1i <= '0;
            y2r <= '0; y2i <= '0; y3r <= '0; y3i <= '0;
            valid <= 1'b0;
        end else begin
            valid <= v1;
            if (v1) begin
                logic signed [31:0] t0r, t0i, t1r, t1i, t2r, t2i, t3r, t3i;
                t0r =  x0r + p1r + p2r + p3r;
                t0i =  x0i + p1i + p2i + p3i;
                t1r =  x0r + p1i - p2r - p3i;
                t1i =  x0i - p1r - p2i + p3r;
                t2r =  x0r - p1r + p2r - p3r;
                t2i =  x0i - p1i + p2i - p3i;
                t3r =  x0r - p1i - p2r + p3i;
                t3i =  x0i + p1r - p2i - p3r;
                y0r <= t0r; y0i <= t0i;
                y1r <= t1r; y1i <= t1i;
                y2r <= t2r; y2i <= t2i;
                y3r <= t3r; y3i <= t3i;
            end
        end
    end
endmodule : calu_fft_butterfly_r4
