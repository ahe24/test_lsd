//==============================================================================
// lsd_fifo_sync.sv
// Parameterisable synchronous FIFO
//==============================================================================
`ifndef LSD_FIFO_SYNC_SV
`define LSD_FIFO_SYNC_SV

module lsd_fifo_sync #(parameter int unsigned W     = 64,
                       parameter int unsigned DEPTH = 16) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         wr,
    input  logic [W-1:0] wr_data,
    output logic         full,
    input  logic         rd,
    output logic [W-1:0] rd_data,
    output logic         empty,
    output logic [$clog2(DEPTH+1)-1:0] count
);
    localparam int AW = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    logic [W-1:0]      mem [0:DEPTH-1];
    logic [AW-1:0]     wptr, rptr;
    logic [$clog2(DEPTH+1)-1:0] cnt;

    assign full  = (cnt == DEPTH[$clog2(DEPTH+1)-1:0]);
    assign empty = (cnt == '0);
    assign count = cnt;
    assign rd_data = mem[rptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= '0;
            rptr <= '0;
            cnt  <= '0;
        end else begin
            if (wr && !full) begin
                mem[wptr] <= wr_data;
                wptr      <= (wptr == DEPTH-1) ? '0 : wptr + 1'b1;
            end
            if (rd && !empty) begin
                rptr <= (rptr == DEPTH-1) ? '0 : rptr + 1'b1;
            end
            case ({wr && !full, rd && !empty})
                2'b10: cnt <= cnt + 1'b1;
                2'b01: cnt <= cnt - 1'b1;
                default: /* no change */ ;
            endcase
        end
    end
endmodule : lsd_fifo_sync

`endif // LSD_FIFO_SYNC_SV
