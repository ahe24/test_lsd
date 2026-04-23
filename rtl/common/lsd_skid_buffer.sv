//==============================================================================
// lsd_skid_buffer.sv
// 2-entry skid buffer used pervasively to pipeline valid/ready handshakes
//==============================================================================
`ifndef LSD_SKID_BUFFER_SV
`define LSD_SKID_BUFFER_SV

module lsd_skid_buffer #(parameter int unsigned W = 64) (
    input  logic           clk,
    input  logic           rst_n,
    input  logic           in_valid,
    output logic           in_ready,
    input  logic [W-1:0]   in_data,
    output logic           out_valid,
    input  logic           out_ready,
    output logic [W-1:0]   out_data
);
    logic [W-1:0] r_main,  r_skid;
    logic         v_main,  v_skid;

    assign in_ready  = ~v_skid;
    assign out_valid = v_main;
    assign out_data  = r_main;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_main  <= 1'b0;
            v_skid  <= 1'b0;
            r_main  <= '0;
            r_skid  <= '0;
        end else begin
            // Pop out_main
            if (v_main && out_ready) begin
                if (v_skid) begin
                    r_main <= r_skid;
                    v_skid <= 1'b0;
                end else begin
                    v_main <= 1'b0;
                end
            end
            // Accept new input
            if (in_valid && in_ready) begin
                if (!v_main || (v_main && out_ready && !v_skid)) begin
                    r_main <= in_data;
                    v_main <= 1'b1;
                end else begin
                    r_skid <= in_data;
                    v_skid <= 1'b1;
                end
            end
        end
    end
endmodule : lsd_skid_buffer

`endif // LSD_SKID_BUFFER_SV
