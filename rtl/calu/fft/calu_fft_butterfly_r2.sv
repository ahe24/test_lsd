//==============================================================================
// calu_fft_butterfly_r2.sv
// Radix-2 DIT butterfly:
//   out0 = in0 + W·in1
//   out1 = in0 - W·in1
// Q16.16 inputs, Q16.16 twiddle.
//==============================================================================
module calu_fft_butterfly_r2 (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  a_re, a_im,
    input  logic signed [31:0]  b_re, b_im,
    input  logic signed [31:0]  w_re, w_im,
    output logic signed [31:0]  o0_re, o0_im,
    output logic signed [31:0]  o1_re, o1_im,
    output logic                valid
);
    logic signed [31:0] bw_re, bw_im;
    logic               bw_v;

    calu_fp_mul u_mul (
        .clk(clk), .rst_n(rst_n), .en(en),
        .ar(b_re), .ai(b_im),
        .br(w_re), .bi(w_im),
        .yr(bw_re), .yi(bw_im),
        .valid(bw_v)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o0_re <= '0; o0_im <= '0; o1_re <= '0; o1_im <= '0;
            valid <= 1'b0;
        end else begin
            valid <= bw_v;
            if (bw_v) begin
                o0_re <= a_re + bw_re;
                o0_im <= a_im + bw_im;
                o1_re <= a_re - bw_re;
                o1_im <= a_im - bw_im;
            end
        end
    end
endmodule : calu_fft_butterfly_r2
