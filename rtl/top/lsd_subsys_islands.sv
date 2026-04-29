//==============================================================================
// lsd_subsys_islands.sv
// One closed module per functional subsystem.  Each island contains the
// per-subsystem PRBS self-traffic generator + its DUT block + the three
// internal interfaces between them.  External interface is only (clk,
// rst_n) so the ParallelSim partitioner CANNOT split the island across
// partitions — the cross-partition signal count drops from O(thousands
// of interface bits per cycle) to O(2 control bits).
//
// Five islands:  lsd_cnn_island, lsd_crypto_island, lsd_gfx_island,
//                lsd_calu_island, lsd_eccd_island
//==============================================================================
`ifndef LSD_SUBSYS_ISLANDS_SV
`define LSD_SUBSYS_ISLANDS_SV

// -----------------------------------------------------------------------------
// CNN island
// -----------------------------------------------------------------------------
module lsd_cnn_island
    import lsd_pkg::*;
(
    input  logic clk,
    input  logic rst_n
);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) cmd_int (clk, rst_n);
    lsd_stream_if #(.W(512))                  in_int  (clk, rst_n);
    lsd_stream_if #(.W(512))                  out_int (clk, rst_n);

    lsd_self_traffic #(
        .SEED(32'h0BAD_F00D), .POLY(32'hEDB8_8320),
        .CMD_PERIOD(5),  .STREAM_PERIOD(1), .SUB_KIND(SUB_CNN),
        .INST_TAG("cnn")
    ) u_self (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.master),
        .in_s  (in_int .producer),
        .out_s (out_int.consumer)
    );

    cnn_top #(.NUM_TILES(16)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.slave),
        .in_s  (in_int .consumer),
        .out_s (out_int.producer)
    );
endmodule : lsd_cnn_island

// -----------------------------------------------------------------------------
// Crypto island
// -----------------------------------------------------------------------------
module lsd_crypto_island
    import lsd_pkg::*;
(
    input  logic clk,
    input  logic rst_n
);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) cmd_int (clk, rst_n);
    lsd_stream_if #(.W(512))                  in_int  (clk, rst_n);
    lsd_stream_if #(.W(512))                  out_int (clk, rst_n);

    lsd_self_traffic #(
        .SEED(32'hCAFE_BABE), .POLY(32'h04C1_1DB7),
        .CMD_PERIOD(7),  .STREAM_PERIOD(2), .SUB_KIND(SUB_CRYPTO),
        .INST_TAG("crypto")
    ) u_self (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.master),
        .in_s  (in_int .producer),
        .out_s (out_int.consumer)
    );

    crypto_top u_dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.slave),
        .in_s  (in_int .consumer),
        .out_s (out_int.producer)
    );
endmodule : lsd_crypto_island

// -----------------------------------------------------------------------------
// Graphics island
// -----------------------------------------------------------------------------
module lsd_gfx_island
    import lsd_pkg::*;
(
    input  logic clk,
    input  logic rst_n
);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) cmd_int (clk, rst_n);
    lsd_stream_if #(.W(512))                  in_int  (clk, rst_n);
    lsd_stream_if #(.W(512))                  out_int (clk, rst_n);

    lsd_self_traffic #(
        .SEED(32'h1357_9BDF), .POLY(32'h82F6_3B78),
        .CMD_PERIOD(9),  .STREAM_PERIOD(1), .SUB_KIND(SUB_GFX),
        .INST_TAG("gfx")
    ) u_self (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.master),
        .in_s  (in_int .producer),
        .out_s (out_int.consumer)
    );

    gfx_top u_dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.slave),
        .in_s  (in_int .consumer),
        .out_s (out_int.producer)
    );
endmodule : lsd_gfx_island

// -----------------------------------------------------------------------------
// Complex ALU island
// -----------------------------------------------------------------------------
module lsd_calu_island
    import lsd_pkg::*;
(
    input  logic clk,
    input  logic rst_n
);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) cmd_int (clk, rst_n);
    lsd_stream_if #(.W(512))                  in_int  (clk, rst_n);
    lsd_stream_if #(.W(512))                  out_int (clk, rst_n);

    lsd_self_traffic #(
        .SEED(32'h2468_ACE0), .POLY(32'hEB31_D82E),
        .CMD_PERIOD(11), .STREAM_PERIOD(3), .SUB_KIND(SUB_CALU),
        .INST_TAG("calu")
    ) u_self (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.master),
        .in_s  (in_int .producer),
        .out_s (out_int.consumer)
    );

    calu_top u_dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.slave),
        .in_s  (in_int .consumer),
        .out_s (out_int.producer)
    );
endmodule : lsd_calu_island

// -----------------------------------------------------------------------------
// ECC codecs island
// -----------------------------------------------------------------------------
module lsd_eccd_island
    import lsd_pkg::*;
(
    input  logic clk,
    input  logic rst_n
);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) cmd_int (clk, rst_n);
    lsd_stream_if #(.W(512))                  in_int  (clk, rst_n);
    lsd_stream_if #(.W(512))                  out_int (clk, rst_n);

    lsd_self_traffic #(
        .SEED(32'hDEAD_BEEF), .POLY(32'hD419_CC15),
        .CMD_PERIOD(13), .STREAM_PERIOD(2), .SUB_KIND(SUB_ECCD),
        .INST_TAG("eccd")
    ) u_self (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.master),
        .in_s  (in_int .producer),
        .out_s (out_int.consumer)
    );

    eccd_top u_dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cmd_int.slave),
        .in_s  (in_int .consumer),
        .out_s (out_int.producer)
    );
endmodule : lsd_eccd_island

`endif // LSD_SUBSYS_ISLANDS_SV
