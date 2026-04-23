//==============================================================================
// turbo_interleaver.sv
// Quadratic permutation polynomial (QPP) interleaver used in LTE turbo codes.
// pi(i) = (f1*i + f2*i^2) mod K, with K=1024.
//==============================================================================
module turbo_interleaver #(parameter int K = 1024,
                           parameter int F1 = 31,
                           parameter int F2 = 64) (
    input  logic [$clog2(K)-1:0] i,
    output logic [$clog2(K)-1:0] pi
);
    logic [20:0] t0, t1, t2;
    assign t0 = F1 * i;
    assign t1 = F2 * i * i;
    assign t2 = t0 + t1;
    assign pi = t2[$clog2(K)-1:0];
endmodule : turbo_interleaver
