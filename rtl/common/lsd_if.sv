//==============================================================================
// lsd_if.sv
// Standard LSD command/response interface used between subsystems
//==============================================================================
`ifndef LSD_IF_SV
`define LSD_IF_SV

interface lsd_cmd_if #(parameter int unsigned DATA_W = 64,
                       parameter int unsigned ADDR_W = 32) (input logic clk,
                                                            input logic rst_n);
    import lsd_pkg::*;

    logic        cmd_valid;
    logic        cmd_ready;
    cmd_t        cmd;

    logic        rsp_valid;
    logic        rsp_ready;
    rsp_t        rsp;

    modport master (
        output cmd_valid, cmd,
        input  cmd_ready,
        input  rsp_valid, rsp,
        output rsp_ready
    );

    modport slave (
        input  cmd_valid, cmd,
        output cmd_ready,
        output rsp_valid, rsp,
        input  rsp_ready
    );
endinterface : lsd_cmd_if

// Simple streaming AXI-lite-ish sample interface used for bulk data flows
interface lsd_stream_if #(parameter int unsigned W = 512) (input logic clk,
                                                           input logic rst_n);
    logic          valid;
    logic          ready;
    logic [W-1:0]  data;
    logic          sop;
    logic          eop;
    logic [W/8-1:0] keep;

    modport producer (output valid, data, sop, eop, keep, input ready);
    modport consumer (input  valid, data, sop, eop, keep, output ready);
endinterface : lsd_stream_if

`endif // LSD_IF_SV
