//==============================================================================
// lsd_top.sv
// Top-level integration of all five functional subsystems plus the eight
// uniqueness-padding bloat farms.
//
// PARTITION-FRIENDLY (Phase 1) DESIGN
// -----------------------------------
// The DUT no longer takes any host-side cmd/stream interface from the
// testbench.  Each subsystem owns a self-contained PRBS traffic generator
// (lsd_self_traffic) so that ParallelSim sees five independent islands
// with no virtual-interface boundary crossing the partition wall.  The
// testbench instantiates lsd_top with just (clk, rst_n) and observes
// progress via heartbeats — it does not reach into the design.
//
// The eight bloat farms are seeded from a free-running 32-bit LFSR so they
// toggle continuously rather than settling on a static input value.
//==============================================================================
module lsd_top (
    input  logic           clk,
    input  logic           rst_n
);
    import lsd_pkg::*;

    // -------------------------------------------------------------------------
    // Per-subsystem internal interfaces (driven exclusively by self_traffic).
    // -------------------------------------------------------------------------
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) cnn_cmd    (clk, rst_n);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) crypto_cmd (clk, rst_n);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) gfx_cmd    (clk, rst_n);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) calu_cmd   (clk, rst_n);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) eccd_cmd   (clk, rst_n);

    lsd_stream_if #(.W(512)) cnn_in     (clk, rst_n);
    lsd_stream_if #(.W(512)) crypto_in  (clk, rst_n);
    lsd_stream_if #(.W(512)) gfx_in     (clk, rst_n);
    lsd_stream_if #(.W(512)) calu_in    (clk, rst_n);
    lsd_stream_if #(.W(512)) eccd_in    (clk, rst_n);

    lsd_stream_if #(.W(512)) cnn_out    (clk, rst_n);
    lsd_stream_if #(.W(512)) crypto_out (clk, rst_n);
    lsd_stream_if #(.W(512)) gfx_out    (clk, rst_n);
    lsd_stream_if #(.W(512)) calu_out   (clk, rst_n);
    lsd_stream_if #(.W(512)) eccd_out   (clk, rst_n);

    // -------------------------------------------------------------------------
    // Per-subsystem self-traffic islands.  Each pair (self + DUT block) is
    // structurally independent of the other four — exactly what ParallelSim
    // needs to place them in distinct partitions.
    //
    // The four CMD_PERIOD/STREAM_PERIOD numbers are deliberately mismatched
    // per subsystem so partitions don't all step in lockstep, which would
    // collapse to one event-queue serialisation point.
    // -------------------------------------------------------------------------
    lsd_self_traffic #(
        .SEED(32'h0BAD_F00D), .POLY(32'hEDB8_8320),
        .CMD_PERIOD(5),  .STREAM_PERIOD(1), .SUB_KIND(SUB_CNN)
    ) u_self_cnn (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cnn_cmd.master),
        .in_s  (cnn_in .producer),
        .out_s (cnn_out.consumer)
    );

    lsd_self_traffic #(
        .SEED(32'hCAFE_BABE), .POLY(32'h04C1_1DB7),
        .CMD_PERIOD(7),  .STREAM_PERIOD(2), .SUB_KIND(SUB_CRYPTO)
    ) u_self_crypto (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(crypto_cmd.master),
        .in_s  (crypto_in .producer),
        .out_s (crypto_out.consumer)
    );

    lsd_self_traffic #(
        .SEED(32'h1357_9BDF), .POLY(32'h82F6_3B78),
        .CMD_PERIOD(9),  .STREAM_PERIOD(1), .SUB_KIND(SUB_GFX)
    ) u_self_gfx (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(gfx_cmd.master),
        .in_s  (gfx_in .producer),
        .out_s (gfx_out.consumer)
    );

    lsd_self_traffic #(
        .SEED(32'h2468_ACE0), .POLY(32'hEB31_D82E),
        .CMD_PERIOD(11), .STREAM_PERIOD(3), .SUB_KIND(SUB_CALU)
    ) u_self_calu (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(calu_cmd.master),
        .in_s  (calu_in .producer),
        .out_s (calu_out.consumer)
    );

    lsd_self_traffic #(
        .SEED(32'hDEAD_BEEF), .POLY(32'hD419_CC15),
        .CMD_PERIOD(13), .STREAM_PERIOD(2), .SUB_KIND(SUB_ECCD)
    ) u_self_eccd (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(eccd_cmd.master),
        .in_s  (eccd_in .producer),
        .out_s (eccd_out.consumer)
    );

    // -------------------------------------------------------------------------
    // Functional subsystems — wiring identical to the previous host-driven
    // version, but the upstream producer is now lsd_self_traffic instead of
    // lsd_stream_fanout / lsd_interconnect.
    // -------------------------------------------------------------------------
    cnn_top #(.NUM_TILES(16)) u_cnn (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cnn_cmd.slave), .in_s(cnn_in.consumer), .out_s(cnn_out.producer)
    );
    crypto_top u_crypto (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(crypto_cmd.slave), .in_s(crypto_in.consumer), .out_s(crypto_out.producer)
    );
    gfx_top u_gfx (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(gfx_cmd.slave), .in_s(gfx_in.consumer), .out_s(gfx_out.producer)
    );
    calu_top u_calu (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(calu_cmd.slave), .in_s(calu_in.consumer), .out_s(calu_out.producer)
    );
    eccd_top u_eccd (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(eccd_cmd.slave), .in_s(eccd_in.consumer), .out_s(eccd_out.producer)
    );

    // -------------------------------------------------------------------------
    // Free-running 32-bit LFSR for bloat-farm seeds.  Without this, the
    // farms received a static seed (host_cmd.cmd.data was idle) and the
    // linear topologies settled into a fixed state, dropping their runtime
    // contribution to near zero.  A toggling seed keeps every family active.
    // -------------------------------------------------------------------------
    logic [31:0] seed_lfsr;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) seed_lfsr <= 32'h1234_5678;
        else        seed_lfsr <= lsd_lfsr32(seed_lfsr);
    end

    lsd_bloat_farm  u_bloat   (.clk(clk), .rst_n(rst_n), .seed(seed_lfsr                         ));
    lsd_bloat2_farm u_bloat2  (.clk(clk), .rst_n(rst_n), .seed(seed_lfsr ^ 32'hA5A5_A5A5         ));
    lsd_churn_farm  u_churn   (.clk(clk), .rst_n(rst_n), .seed(seed_lfsr ^ 32'h5A5A_5A5A         ));
    lsd_grind_farm  u_grind   (.clk(clk), .rst_n(rst_n), .seed(seed_lfsr ^ 32'h1122_3344         ));
    lsd_haze_farm   u_haze    (.clk(clk), .rst_n(rst_n), .seed(seed_lfsr ^ 32'hCCCC_3333         ));
    lsd_prism_farm  u_prism   (.clk(clk), .rst_n(rst_n), .seed(seed_lfsr ^ 32'h6677_8899         ));
    lsd_echo_farm   u_echo    (.clk(clk), .rst_n(rst_n), .seed(seed_lfsr ^ 32'hAABB_CCDD         ));
    lsd_vortex_farm u_vortex  (.clk(clk), .rst_n(rst_n), .seed(seed_lfsr ^ 32'hEEFF_0011         ));
endmodule : lsd_top
