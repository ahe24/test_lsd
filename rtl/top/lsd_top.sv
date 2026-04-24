//==============================================================================
// lsd_top.sv
// Top-level integration of all five subsystems behind a single command port
// and shared in/out stream ports. Also instantiates a uniqueness-padding
// generator array of auto-generated bloater units.
//==============================================================================
module lsd_top (
    input  logic           clk,
    input  logic           rst_n,
    lsd_cmd_if.slave       host_cmd,
    lsd_stream_if.consumer host_in,
    lsd_stream_if.producer host_out
);
    import lsd_pkg::*;

    // Internal interfaces
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) cnn_cmd    (clk, rst_n);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) crypto_cmd (clk, rst_n);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) gfx_cmd    (clk, rst_n);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) calu_cmd   (clk, rst_n);
    lsd_cmd_if    #(.DATA_W(64), .ADDR_W(32)) eccd_cmd   (clk, rst_n);

    lsd_stream_if #(.W(512)) cnn_in    (clk, rst_n);
    lsd_stream_if #(.W(512)) crypto_in (clk, rst_n);
    lsd_stream_if #(.W(512)) gfx_in    (clk, rst_n);
    lsd_stream_if #(.W(512)) calu_in   (clk, rst_n);
    lsd_stream_if #(.W(512)) eccd_in   (clk, rst_n);

    lsd_stream_if #(.W(512)) cnn_out    (clk, rst_n);
    lsd_stream_if #(.W(512)) crypto_out (clk, rst_n);
    lsd_stream_if #(.W(512)) gfx_out    (clk, rst_n);
    lsd_stream_if #(.W(512)) calu_out   (clk, rst_n);
    lsd_stream_if #(.W(512)) eccd_out   (clk, rst_n);

    // Command interconnect
    lsd_interconnect u_xbar (
        .clk(clk), .rst_n(rst_n),
        .h_cmd    (host_cmd),
        .s_cnn    (cnn_cmd),
        .s_crypto (crypto_cmd),
        .s_gfx    (gfx_cmd),
        .s_calu   (calu_cmd),
        .s_eccd   (eccd_cmd)
    );

    // Stream fan-out (host → each subsystem)
    lsd_stream_fanout u_fan (
        .clk(clk), .rst_n(rst_n),
        .src(host_in),
        .cnn_s(cnn_in), .crypto_s(crypto_in), .gfx_s(gfx_in),
        .calu_s(calu_in), .eccd_s(eccd_in)
    );

    // Stream merge (all subsystems → host)
    lsd_stream_merge u_mrg (
        .clk(clk), .rst_n(rst_n),
        .cnn_s(cnn_out), .crypto_s(crypto_out), .gfx_s(gfx_out),
        .calu_s(calu_out), .eccd_s(eccd_out),
        .dst(host_out)
    );

    // Subsystems
    cnn_top     #(.NUM_TILES(16)) u_cnn (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(cnn_cmd.slave), .in_s(cnn_in.consumer), .out_s(cnn_out.producer)
    );
    crypto_top  u_crypto (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(crypto_cmd.slave), .in_s(crypto_in.consumer), .out_s(crypto_out.producer)
    );
    gfx_top     u_gfx (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(gfx_cmd.slave), .in_s(gfx_in.consumer), .out_s(gfx_out.producer)
    );
    calu_top    u_calu (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(calu_cmd.slave), .in_s(calu_in.consumer), .out_s(calu_out.producer)
    );
    eccd_top    u_eccd (
        .clk(clk), .rst_n(rst_n),
        .cmd_if(eccd_cmd.slave), .in_s(eccd_in.consumer), .out_s(eccd_out.producer)
    );

    // Uniqueness bloater - eight independent families of distinct generated
    // modules running side-by-side so the optimizer cannot collapse them by
    // pattern-matching any single topology or primitive. See gen/.
    //   u_bloat  : linear arithmetic chain   (gen_bloat.py  -> lsd_bloat_*)
    //   u_bloat2 : parallel mem/ring bank    (gen_bloat2.py -> lsd_bloat2_*)
    //   u_churn  : broadcast-fanout kernels  (gen_churn.py  -> lsd_churn_*)
    //   u_grind  : crosscouple ring          (gen_grind.py  -> lsd_grind_*)
    //   u_haze   : pairwise fan-in           (gen_haze.py   -> lsd_haze_*)
    //   u_prism  : 64-bit MAC chain          (gen_prism.py  -> lsd_prism_*)
    //   u_echo   : deep delay lines          (gen_echo.py   -> lsd_echo_*)
    //   u_vortex : tick + counter banks      (gen_vortex.py -> lsd_vortex_*)
    lsd_bloat_farm u_bloat (
        .clk    (clk),
        .rst_n  (rst_n),
        .seed   (host_cmd.cmd.data[31:0])
    );
    lsd_bloat2_farm u_bloat2 (
        .clk    (clk),
        .rst_n  (rst_n),
        .seed   (host_cmd.cmd.data[31:0] ^ 32'hA5A5A5A5)
    );
    lsd_churn_farm u_churn (
        .clk    (clk),
        .rst_n  (rst_n),
        .seed   (host_cmd.cmd.data[31:0] ^ 32'h5A5A5A5A)
    );
    lsd_grind_farm u_grind (
        .clk    (clk),
        .rst_n  (rst_n),
        .seed   (host_cmd.cmd.data[31:0] ^ 32'h11223344)
    );
    lsd_haze_farm u_haze (
        .clk    (clk),
        .rst_n  (rst_n),
        .seed   (host_cmd.cmd.data[31:0] ^ 32'hCCCC3333)
    );
    lsd_prism_farm u_prism (
        .clk    (clk),
        .rst_n  (rst_n),
        .seed   (host_cmd.cmd.data[31:0] ^ 32'h66778899)
    );
    lsd_echo_farm u_echo (
        .clk    (clk),
        .rst_n  (rst_n),
        .seed   (host_cmd.cmd.data[31:0] ^ 32'hAABBCCDD)
    );
    lsd_vortex_farm u_vortex (
        .clk    (clk),
        .rst_n  (rst_n),
        .seed   (host_cmd.cmd.data[31:0] ^ 32'hEEFF0011)
    );
endmodule : lsd_top
