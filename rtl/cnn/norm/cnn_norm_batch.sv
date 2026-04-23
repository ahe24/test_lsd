//==============================================================================
// cnn_norm_batch.sv
// Inference-time batch-norm: y = gamma * (x - mean) * inv_std + beta.
// inv_std is pre-computed and supplied externally.
//==============================================================================
module cnn_norm_batch #(parameter int unsigned W = 16) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [W-1:0] x,
    input  logic signed [W-1:0] mean,
    input  logic signed [W-1:0] inv_std,
    input  logic signed [W-1:0] gamma,
    input  logic signed [W-1:0] beta,
    output logic signed [W-1:0] y,
    output logic                valid
);
    logic signed [W:0]    diff;
    logic signed [2*W:0]  m1, m2;
    logic signed [W-1:0]  y_nxt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin y <= '0; valid <= 1'b0; end
        else begin
            // Pipeline: stage 1 compute m1=diff*inv_std, stage 2 m2=m1*gamma+beta
            diff  <= x - mean;
            m1    <= $signed(diff) * $signed(inv_std);
            m2    <= $signed(m1[2*W-1:W-1]) * $signed(gamma);
            y_nxt <= m2[2*W-1:W-1] + beta;
            y     <= y_nxt;
            valid <= en;
        end
    end
endmodule : cnn_norm_batch
