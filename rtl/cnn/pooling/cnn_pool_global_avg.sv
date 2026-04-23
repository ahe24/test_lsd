//==============================================================================
// cnn_pool_global_avg.sv  -  streaming global average pool
//==============================================================================
module cnn_pool_global_avg #(parameter int unsigned W        = 16,
                             parameter int unsigned CNT_W    = 20) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     start,
    input  logic                     sample_valid,
    input  logic signed [W-1:0]      sample,
    input  logic [CNT_W-1:0]         n_samples,
    output logic signed [W-1:0]      y,
    output logic                     done
);
    logic signed [W+CNT_W:0] acc;
    logic [CNT_W-1:0]        cnt;
    typedef enum logic [1:0] {S_IDLE, S_ACC, S_DIV} st_e;
    st_e st;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st   <= S_IDLE;
            acc  <= '0;
            cnt  <= '0;
            y    <= '0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    acc <= '0;
                    cnt <= '0;
                    st  <= S_ACC;
                end
                S_ACC: begin
                    if (sample_valid) begin
                        acc <= acc + $signed({{(CNT_W+1){sample[W-1]}}, sample});
                        cnt <= cnt + 1'b1;
                    end
                    if (cnt == n_samples - 1 && sample_valid) st <= S_DIV;
                end
                S_DIV: begin
                    if (n_samples != 0) y <= acc / $signed({1'b0, n_samples});
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
            endcase
        end
    end
endmodule : cnn_pool_global_avg
