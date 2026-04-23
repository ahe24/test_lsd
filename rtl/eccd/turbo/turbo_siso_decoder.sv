//==============================================================================
// turbo_siso_decoder.sv
// Log-MAP soft-input-soft-output decoder over K=1024 trellis. Uses 8-state
// trellis (K=4 constraint length). Implements forward/backward recursions
// on explicit state-metric arrays, then a per-bit L-value computation.
// This is intentionally compute-heavy.
//==============================================================================
module turbo_siso_decoder #(parameter int K = 1024) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 start,
    input  logic signed [7:0]    sys_llr  [0:K-1],
    input  logic signed [7:0]    par_llr  [0:K-1],
    input  logic signed [7:0]    a_priori [0:K-1],
    output logic signed [9:0]    ext_llr  [0:K-1],
    output logic                 done
);
    localparam int S = 8;

    // Trellis transitions (hand-coded for an 8-state recursive systematic code).
    // For each (state, input_bit) → next_state, output_parity
    // Here we pick a toy generator — not the real 3GPP one — to keep the
    // structure clean. The arithmetic scale matches.
    function automatic int nxt_state (input int s, input int u);
        return ((s << 1) | u) & (S - 1);
    endfunction
    function automatic int out_parity (input int s, input int u);
        return (u ^ s[0] ^ s[2]);
    endfunction

    typedef enum logic [2:0] {S_IDLE, S_FWD, S_BWD, S_LLR, S_DONE} st_e;
    st_e st;

    logic signed [15:0] alpha [0:K][0:S-1];
    logic signed [15:0] beta  [0:K][0:S-1];
    logic signed [15:0] gamma [0:K-1][0:1];

    int t;

    function automatic logic signed [15:0] max_star (
        input logic signed [15:0] a,
        input logic signed [15:0] b
    );
        // log-sum-exp approximation (max plus small correction)
        logic signed [15:0] d;
        if (a > b) begin
            d = a - b;
            if (d > 16'sd512) max_star = a;
            else              max_star = a + (16'sd32 - (d >>> 4));
        end else begin
            d = b - a;
            if (d > 16'sd512) max_star = b;
            else              max_star = b + (16'sd32 - (d >>> 4));
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st   <= S_IDLE;
            t    <= 0;
            done <= 1'b0;
            for (int k = 0; k < K; k++) begin
                ext_llr[k] <= '0;
                gamma[k][0] <= '0; gamma[k][1] <= '0;
            end
            for (int k = 0; k <= K; k++)
                for (int s = 0; s < S; s++) begin
                    alpha[k][s] <= '0;
                    beta [k][s] <= '0;
                end
        end else begin
            done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    // Compute branch metrics
                    for (int k = 0; k < K; k++) begin
                        gamma[k][0] <=  sys_llr[k] + a_priori[k];
                        gamma[k][1] <= -sys_llr[k] - a_priori[k] + par_llr[k];
                    end
                    // Initialise alpha[0], beta[K] with terminations
                    alpha[0][0] <= 16'sd0;
                    for (int s = 1; s < S; s++) alpha[0][s] <= -16'sh7FFF;
                    beta [K][0] <= 16'sd0;
                    for (int s = 1; s < S; s++) beta[K][s] <= -16'sh7FFF;
                    t  <= 0;
                    st <= S_FWD;
                end
                S_FWD: begin
                    for (int s = 0; s < S; s++) begin
                        automatic logic signed [15:0] a0, a1;
                        a0 = alpha[t][s >> 1]                 + gamma[t][0];
                        a1 = alpha[t][(s >> 1) | (S >> 1)]    + gamma[t][1];
                        alpha[t+1][s] <= max_star(a0, a1);
                    end
                    if (t == K-1) begin t <= K-1; st <= S_BWD; end
                    else          t <= t + 1;
                end
                S_BWD: begin
                    for (int s = 0; s < S; s++) begin
                        automatic logic signed [15:0] b0, b1;
                        b0 = beta[t+1][(s << 1) & (S-1)]     + gamma[t][0];
                        b1 = beta[t+1][((s << 1) | 1) & (S-1)]+ gamma[t][1];
                        beta[t][s] <= max_star(b0, b1);
                    end
                    if (t == 0) begin t <= 0; st <= S_LLR; end
                    else        t <= t - 1;
                end
                S_LLR: begin
                    logic signed [15:0] l0, l1;
                    l0 = -16'sh7FFF;
                    l1 = -16'sh7FFF;
                    for (int s = 0; s < S; s++) begin
                        automatic logic signed [15:0] m0, m1;
                        m0 = alpha[t][s] + gamma[t][0] + beta[t+1][(s << 1)         & (S-1)];
                        m1 = alpha[t][s] + gamma[t][1] + beta[t+1][((s << 1) | 1)   & (S-1)];
                        l0 = max_star(l0, m0);
                        l1 = max_star(l1, m1);
                    end
                    ext_llr[t] <= (l0 - l1) >>> 4;
                    if (t == K-1) st <= S_DONE;
                    else          t <= t + 1;
                end
                S_DONE: begin
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : turbo_siso_decoder
