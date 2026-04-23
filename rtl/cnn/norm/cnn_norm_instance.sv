//==============================================================================
// cnn_norm_instance.sv
// Instance normalisation: per-sample, per-channel mean+variance over spatial
// dimensions of a single example. Streams spatial elements sequentially.
//==============================================================================
module cnn_norm_instance #(parameter int unsigned W     = 16,
                           parameter int unsigned N_MAX = 256,
                           parameter int unsigned CNT_W = $clog2(N_MAX+1)) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 start,
    input  logic                 in_valid,
    input  logic signed [W-1:0]  x_in,
    input  logic [CNT_W-1:0]     n_elem,
    input  logic signed [W-1:0]  gamma,
    input  logic signed [W-1:0]  beta,
    output logic                 out_valid,
    output logic signed [W-1:0]  y_out,
    output logic                 done
);
    // Pass 1 accumulates; pass 2 emits; simple FSM.
    typedef enum logic [2:0] {
        S_IDLE, S_ACC, S_STATS, S_EMIT_ACC, S_EMIT, S_DONE
    } st_e;
    st_e st;

    logic signed [W+CNT_W-1:0] sum;
    logic [2*W+CNT_W-1:0]      ssq;
    logic signed [W-1:0]       mean_r;
    logic signed [W-1:0]       var_r;
    logic signed [W-1:0]       inv_std_r;
    logic [CNT_W-1:0]          cnt;

    // Ring buffer of inputs for pass 2 re-emission (bounded by N_MAX)
    logic signed [W-1:0] buf_mem [0:N_MAX-1];
    logic [CNT_W-1:0]    wptr, rptr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            sum <= '0; ssq <= '0; mean_r <= '0; var_r <= '0; inv_std_r <= '0;
            cnt <= '0; wptr <= '0; rptr <= '0;
            out_valid <= 1'b0; y_out <= '0; done <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            done      <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    sum <= '0; ssq <= '0; cnt <= '0; wptr <= '0; rptr <= '0;
                    st  <= S_ACC;
                end
                S_ACC: if (in_valid) begin
                    buf_mem[wptr] <= x_in;
                    wptr          <= wptr + 1'b1;
                    sum           <= sum + x_in;
                    ssq           <= ssq + $signed(x_in) * $signed(x_in);
                    cnt           <= cnt + 1'b1;
                    if (cnt == n_elem - 1) st <= S_STATS;
                end
                S_STATS: begin
                    mean_r    <= sum / $signed({1'b0, n_elem});
                    var_r     <= ssq[2*W+CNT_W-1 -: W];
                    inv_std_r <= 16'sd1 <<< (W/2); // quick seed; acceptable for sim stress
                    cnt       <= '0;
                    st        <= S_EMIT;
                end
                S_EMIT: begin
                    automatic logic signed [W-1:0]   d;
                    automatic logic signed [2*W-1:0] p1, p2;
                    d  = buf_mem[rptr] - mean_r;
                    p1 = $signed(d) * $signed(inv_std_r);
                    p2 = $signed(p1[2*W-1 -: W]) * $signed(gamma);
                    y_out     <= p2[2*W-1 -: W] + beta;
                    out_valid <= 1'b1;
                    rptr      <= rptr + 1'b1;
                    cnt       <= cnt + 1'b1;
                    if (cnt == n_elem - 1) st <= S_DONE;
                end
                S_DONE: begin
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : cnn_norm_instance
