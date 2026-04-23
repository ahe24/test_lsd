//==============================================================================
// lsd_rr_arbiter.sv
// Parameterisable round-robin arbiter
//==============================================================================
`ifndef LSD_RR_ARBITER_SV
`define LSD_RR_ARBITER_SV

module lsd_rr_arbiter #(parameter int unsigned N = 8) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [N-1:0] req,
    output logic [N-1:0] gnt,
    output logic         any_gnt,
    output logic [$clog2(N>1?N:2)-1:0] gnt_idx
);
    localparam int IW = (N>1) ? $clog2(N) : 1;
    logic [N-1:0] mask, mreq;
    logic [N-1:0] g;
    logic [IW-1:0] idx;

    // Masked priority: find first set bit at or after mask position
    always_comb begin
        mreq = req & mask;
        g    = '0;
        if (|mreq) begin
            for (int i = 0; i < N; i++) begin
                if (mreq[i]) begin
                    g = '0;
                    g[i] = 1'b1;
                    break;
                end
            end
        end else if (|req) begin
            for (int i = 0; i < N; i++) begin
                if (req[i]) begin
                    g = '0;
                    g[i] = 1'b1;
                    break;
                end
            end
        end
    end

    always_comb begin
        idx = '0;
        for (int i = 0; i < N; i++) begin
            if (g[i]) idx = i[IW-1:0];
        end
    end

    assign gnt     = g;
    assign any_gnt = |g;
    assign gnt_idx = idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask <= '1;
        end else if (|g) begin
            // Clear mask bits up to and including granted index
            mask <= ~((1 << (idx + 1)) - 1);
            if (idx == N-1) mask <= '1;
        end
    end
endmodule : lsd_rr_arbiter

`endif // LSD_RR_ARBITER_SV
