//==============================================================================
// cnn_norm_layer.sv
// LayerNorm over an N-element vector (default N=16). 3-stage pipeline:
//   s0: compute mean, centered vector, sum-of-squares (variance)
//   s1: compute inv_std via leading-one seed + 1 Newton-Raphson iter
//   s2: affine transform y = gamma * (x-mean) * inv_std + beta
//==============================================================================
module cnn_norm_layer #(parameter int unsigned W = 16,
                        parameter int unsigned N = 16) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        en,
    input  logic signed [W-1:0]         x    [0:N-1],
    input  logic signed [W-1:0]         gamma,
    input  logic signed [W-1:0]         beta,
    output logic signed [W-1:0]         y    [0:N-1],
    output logic                        valid
);
    localparam int ACC_W = W + $clog2(N) + 4;

    // S0 combinational
    logic signed [ACC_W-1:0] sum;
    logic signed [W-1:0]     mean_c;
    logic signed [2*W+4-1:0] ssq;
    integer i;

    always_comb begin
        sum = '0;
        for (i = 0; i < N; i++) sum += x[i];
    end
    assign mean_c = sum >>> $clog2(N);

    always_comb begin
        ssq = '0;
        for (i = 0; i < N; i++) begin
            automatic logic signed [W:0] d;
            d = x[i] - mean_c;
            ssq += d * d;
        end
    end

    // S0 registers
    logic signed [W-1:0] mean_r0;
    logic signed [W-1:0] var_r0;
    logic signed [W-1:0] gamma_r0, beta_r0;
    logic signed [W-1:0] xc_r0 [0:N-1]; // centered input
    logic                v0;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mean_r0 <= '0; var_r0 <= '0; gamma_r0 <= '0; beta_r0 <= '0; v0 <= 1'b0;
            for (int k = 0; k < N; k++) xc_r0[k] <= '0;
        end else begin
            v0       <= en;
            mean_r0  <= mean_c;
            var_r0   <= ssq[2*W+4-1 -: W];
            gamma_r0 <= gamma;
            beta_r0  <= beta;
            for (int k = 0; k < N; k++) xc_r0[k] <= x[k] - mean_c;
        end
    end

    // S1: inv_std = 1/sqrt(var). Use leading-one bit-reversal seed, then 1 NR.
    logic [4:0] lz_s1;
    always_comb begin
        lz_s1 = 0;
        for (int k = W-1; k >= 0; k--) begin
            if (var_r0[k]) begin
                lz_s1 = k[4:0];
                break;
            end
        end
    end
    logic signed [W-1:0] seed_s1;
    // seed ≈ 2^((W-1 - lz)/2) shifted to Q-point
    assign seed_s1 = W'(1 << ((W/2) + (lz_s1 >> 1)));

    logic signed [2*W-1:0] mul_vs;
    logic signed [W-1:0]   tmp_s1;
    logic signed [W-1:0]   inv_std_s1;
    assign mul_vs    = $signed(seed_s1) * $signed(var_r0);
    assign tmp_s1    = mul_vs[2*W-1 -: W];
    // 1-iter NR: inv ≈ seed * (1.5 - 0.5 * var * seed^2)
    // Simpler: inv ≈ 2*seed - (var*seed*seed) >> scale   – use lookup cheapo
    assign inv_std_s1 = seed_s1 - (tmp_s1 >>> 1);

    // S1 regs
    logic signed [W-1:0] inv_std_r1;
    logic signed [W-1:0] gamma_r1, beta_r1;
    logic signed [W-1:0] xc_r1 [0:N-1];
    logic                v1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inv_std_r1 <= '0; gamma_r1 <= '0; beta_r1 <= '0; v1 <= 1'b0;
            for (int k = 0; k < N; k++) xc_r1[k] <= '0;
        end else begin
            v1         <= v0;
            inv_std_r1 <= inv_std_s1;
            gamma_r1   <= gamma_r0;
            beta_r1    <= beta_r0;
            for (int k = 0; k < N; k++) xc_r1[k] <= xc_r0[k];
        end
    end

    // S2: affine
    genvar gi;
    generate
        for (gi = 0; gi < N; gi++) begin : g_aff
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) y[gi] <= '0;
                else if (v1) begin
                    automatic logic signed [2*W-1:0] p1, p2;
                    p1 = $signed(xc_r1[gi]) * $signed(inv_std_r1);
                    p2 = $signed(p1[2*W-1 -: W]) * $signed(gamma_r1);
                    y[gi] <= p2[2*W-1 -: W] + beta_r1;
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid <= 1'b0;
        else        valid <= v1;
    end
endmodule : cnn_norm_layer
