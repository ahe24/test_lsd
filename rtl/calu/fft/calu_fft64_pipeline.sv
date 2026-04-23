//==============================================================================
// calu_fft64_pipeline.sv
// A 64-point pipelined radix-2 DIT FFT. Six stages of butterflies, each with
// 32 parallel butterfly instances. Twiddles supplied via a pre-computed ROM.
//==============================================================================
module calu_fft64_pipeline (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  x_re [0:63],
    input  logic signed [31:0]  x_im [0:63],
    output logic signed [31:0]  y_re [0:63],
    output logic signed [31:0]  y_im [0:63],
    output logic                valid
);
    // ROM of twiddles (Q2.30). Initialise from real cos/sin.
    logic signed [31:0] tw_re [0:31];
    logic signed [31:0] tw_im [0:31];
    initial begin
        for (int k = 0; k < 32; k++) begin
            automatic real th;
            th = -2.0 * 3.141592653589793 * real'(k) / 64.0;
            tw_re[k] = int'( $cos(th) * real'(1 << 30) );
            tw_im[k] = int'( $sin(th) * real'(1 << 30) );
        end
    end

    // Inter-stage wires
    logic signed [31:0] sr [0:6][0:63];
    logic signed [31:0] si [0:6][0:63];

    genvar k;
    generate
        for (k = 0; k < 64; k++) begin : g_in
            assign sr[0][k] = x_re[k];
            assign si[0][k] = x_im[k];
        end
    endgenerate

    // 6 stages of 32 butterflies
    genvar s, j;
    generate
        for (s = 0; s < 6; s++) begin : g_stage
            for (j = 0; j < 32; j++) begin : g_bf
                localparam int M    = 1 << (s+1);
                localparam int HALF = 1 << s;
                localparam int GRP  = (j / HALF) * M;
                localparam int POS  = j % HALF;
                localparam int IDX0 = GRP + POS;
                localparam int IDX1 = GRP + POS + HALF;
                localparam int TWID = (POS * (32 >> s));

                logic signed [31:0] o0r, o0i, o1r, o1i;
                logic v_bf;
                calu_fft_butterfly_r2 u_bf (
                    .clk(clk), .rst_n(rst_n), .en(en),
                    .a_re(sr[s][IDX0]), .a_im(si[s][IDX0]),
                    .b_re(sr[s][IDX1]), .b_im(si[s][IDX1]),
                    .w_re(tw_re[TWID]), .w_im(tw_im[TWID]),
                    .o0_re(o0r), .o0_im(o0i),
                    .o1_re(o1r), .o1_im(o1i),
                    .valid(v_bf)
                );
                assign sr[s+1][IDX0] = o0r;
                assign si[s+1][IDX0] = o0i;
                assign sr[s+1][IDX1] = o1r;
                assign si[s+1][IDX1] = o1i;
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid <= 1'b0;
        else        valid <= en;
    end

    genvar o;
    generate
        for (o = 0; o < 64; o++) begin : g_out
            assign y_re[o] = sr[6][o];
            assign y_im[o] = si[6][o];
        end
    endgenerate
endmodule : calu_fft64_pipeline
