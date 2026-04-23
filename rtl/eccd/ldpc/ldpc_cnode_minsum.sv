//==============================================================================
// ldpc_cnode_minsum.sv
// LDPC check node with 8 incoming variable-node messages. Min-sum update:
// for each output j, find min(|L_i|, i≠j) and product of signs.
//==============================================================================
module ldpc_cnode_minsum #(parameter int DEG = 8,
                           parameter int W   = 8) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     en,
    input  logic signed [W-1:0]      in_llr  [0:DEG-1],
    output logic signed [W-1:0]      out_llr [0:DEG-1],
    output logic                     valid
);
    // Stage 1: absolute values, signs, find two smallest mins
    logic [W-2:0] mag [0:DEG-1];
    logic         sg  [0:DEG-1];
    logic [W-2:0] min1, min2;
    logic [$clog2(DEG)-1:0] min1_idx;
    logic         sign_xor;

    always_comb begin
        min1 = {(W-1){1'b1}};
        min2 = {(W-1){1'b1}};
        min1_idx = 0;
        sign_xor = 1'b0;
        for (int i = 0; i < DEG; i++) begin
            mag[i] = in_llr[i][W-1] ? (-in_llr[i]) : in_llr[i];
            sg[i]  = in_llr[i][W-1];
            sign_xor ^= sg[i];
            if (mag[i] < min1) begin
                min2 = min1;
                min1 = mag[i];
                min1_idx = i[$clog2(DEG)-1:0];
            end else if (mag[i] < min2) begin
                min2 = mag[i];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 1'b0;
            for (int k = 0; k < DEG; k++) out_llr[k] <= '0;
        end else begin
            valid <= en;
            if (en) begin
                for (int k = 0; k < DEG; k++) begin
                    logic [W-2:0] m;
                    logic         s;
                    m = (k == min1_idx) ? min2 : min1;
                    s = sign_xor ^ sg[k];
                    out_llr[k] <= s ? -$signed({1'b0, m}) : $signed({1'b0, m});
                end
            end
        end
    end
endmodule : ldpc_cnode_minsum
