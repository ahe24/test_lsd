//==============================================================================
// ldpc_vnode.sv
// Variable node: receives channel LLR plus DEG check-node messages and
// computes each outgoing message as sum(all others). DEG=4 default.
//==============================================================================
module ldpc_vnode #(parameter int DEG = 4,
                    parameter int W   = 8) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     en,
    input  logic signed [W-1:0]      ch_llr,
    input  logic signed [W-1:0]      in_llr  [0:DEG-1],
    output logic signed [W-1:0]      out_llr [0:DEG-1],
    output logic signed [W+2:0]      post_llr,
    output logic                     valid
);
    logic signed [W+2:0] sum_all;
    always_comb begin
        sum_all = ch_llr;
        for (int i = 0; i < DEG; i++) sum_all += in_llr[i];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            post_llr <= '0; valid <= 1'b0;
            for (int k = 0; k < DEG; k++) out_llr[k] <= '0;
        end else begin
            valid <= en;
            if (en) begin
                post_llr <= sum_all;
                for (int k = 0; k < DEG; k++) begin
                    logic signed [W+2:0] t;
                    t = sum_all - in_llr[k];
                    out_llr[k] <= (t > {1'b0, {(W-1){1'b1}}}) ? {(W){1'b0}} | { {1{1'b0}}, {(W-1){1'b1}} } :
                                  (t < -{1'b0, {(W-1){1'b1}}}) ? -{(W-1){1'b1}} : t[W-1:0];
                end
            end
        end
    end
endmodule : ldpc_vnode
