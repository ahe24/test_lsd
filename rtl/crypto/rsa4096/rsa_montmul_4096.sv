//==============================================================================
// rsa_montmul_4096.sv
// Word-serial Montgomery multiplier for 4096-bit operands.
// Implements the classic CIOS (coarsely integrated operand scanning) form.
// Word width = 64 bits → 64 outer and 64 inner iterations → 4096 cycles/op.
//==============================================================================
module rsa_montmul_4096 (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [4095:0]      a,
    input  logic [4095:0]      b,
    input  logic [4095:0]      n,
    input  logic [63:0]        n0_inv,   // -n^-1 mod 2^64
    output logic [4095:0]      result,
    output logic               done
);
    localparam int W   = 64;
    localparam int WRD = 64;      // number of 64-bit words in 4096 bits

    typedef enum logic [2:0] {S_IDLE, S_OUTER, S_INNER_A, S_INNER_B, S_REDUCE, S_DONE} st_e;
    st_e st;

    logic [W-1:0] t [0:WRD+1];   // t has one guard word at the top
    logic [W-1:0] a_w [0:WRD-1];
    logic [W-1:0] b_w [0:WRD-1];
    logic [W-1:0] n_w [0:WRD-1];

    logic [$clog2(WRD+1)-1:0] i_cnt;
    logic [$clog2(WRD+1)-1:0] j_cnt;
    logic [W-1:0]             m;
    logic [2*W-1:0]           prod_ab;
    logic [2*W-1:0]           prod_mn;
    logic [2*W-1:0]           tmp;
    logic [W-1:0]             c_hi;

    integer k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st    <= S_IDLE;
            i_cnt <= '0;
            j_cnt <= '0;
            done  <= 1'b0;
            for (k = 0; k < WRD+2; k++) t[k] <= '0;
            for (k = 0; k < WRD;   k++) begin
                a_w[k] <= '0; b_w[k] <= '0; n_w[k] <= '0;
            end
        end else begin
            done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    for (k = 0; k < WRD; k++) begin
                        a_w[k] <= a[W*k +: W];
                        b_w[k] <= b[W*k +: W];
                        n_w[k] <= n[W*k +: W];
                    end
                    for (k = 0; k < WRD+2; k++) t[k] <= '0;
                    i_cnt <= '0;
                    st    <= S_OUTER;
                end
                S_OUTER: begin
                    j_cnt <= '0;
                    st    <= S_INNER_A;
                end
                // Inner step A: t = t + a_i * b
                S_INNER_A: begin
                    tmp      = a_w[i_cnt] * b_w[j_cnt] + {64'd0, t[j_cnt]} + {64'd0, c_hi};
                    t[j_cnt] <= tmp[W-1:0];
                    c_hi     <= tmp[2*W-1:W];
                    if (j_cnt == WRD-1) begin
                        t[WRD]   <= t[WRD] + c_hi;
                        t[WRD+1] <= t[WRD+1] + ((t[WRD] + c_hi) < t[WRD] ? 1 : 0);
                        c_hi     <= '0;
                        m        <= (t[0]) * n0_inv;
                        j_cnt    <= '0;
                        st       <= S_INNER_B;
                    end else begin
                        j_cnt <= j_cnt + 1'b1;
                    end
                end
                // Inner step B: t = (t + m * n) / 2^W
                S_INNER_B: begin
                    tmp      = m * n_w[j_cnt] + {64'd0, t[j_cnt]} + {64'd0, c_hi};
                    t[j_cnt] <= tmp[W-1:0];
                    c_hi     <= tmp[2*W-1:W];
                    if (j_cnt == WRD-1) begin
                        t[WRD]   <= t[WRD] + c_hi;
                        t[WRD+1] <= t[WRD+1] + ((t[WRD] + c_hi) < t[WRD] ? 1 : 0);
                        c_hi     <= '0;
                        // shift t right by one word
                        for (k = 0; k <= WRD; k++) t[k] <= t[k+1];
                        t[WRD+1] <= '0;
                        if (i_cnt == WRD-1) st <= S_REDUCE;
                        else begin
                            i_cnt <= i_cnt + 1'b1;
                            st    <= S_OUTER;
                        end
                    end else begin
                        j_cnt <= j_cnt + 1'b1;
                    end
                end
                S_REDUCE: begin
                    // Final subtractive reduction if t >= n
                    logic [4095:0] t_full;
                    logic [4095:0] diff;
                    logic          borrow;
                    t_full = '0;
                    for (k = 0; k < WRD; k++) t_full[W*k +: W] = t[k];
                    diff   = t_full - n;
                    borrow = (t_full < n);
                    result <= borrow ? t_full : diff;
                    done   <= 1'b1;
                    st     <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : rsa_montmul_4096
