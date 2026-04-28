//==============================================================================
// lsd_self_traffic.sv
// Per-subsystem self-driving stimulus block.  Owns one cmd master + one
// stream producer + one stream consumer, all driven by an internal PRBS
// source.  The point: each subsystem becomes a closed traffic island that
// ParallelSim can place in its own partition without any cross-partition
// virtual-interface or testbench dependency.
//
// All control is statically parameterised — no plusargs, no DPI, no XMR —
// so qopt can fully resolve the partition footprint at elaboration time.
//
//   * cmd master path  : one cmd issued every CMD_PERIOD cycles (gated by
//                        cmd_ready).  rsp_ready is held high.
//   * stream input     : valid asserted every STREAM_PERIOD cycles, data
//                        is the PRBS register replicated across W bits.
//   * stream output    : ready held high so producer never back-pressures.
//
// SUB_KIND parameter is purely cosmetic (it XORs into the PRBS seed so each
// instance gets a distinct, but reproducible, traffic stream).
//==============================================================================
`ifndef LSD_SELF_TRAFFIC_SV
`define LSD_SELF_TRAFFIC_SV

module lsd_self_traffic
    import lsd_pkg::*;
#(
    parameter int unsigned       W              = 512,
    parameter logic [31:0]       SEED           = 32'h1234_5678,
    parameter logic [31:0]       POLY           = 32'hEDB8_8320,
    parameter int unsigned       CMD_PERIOD     = 8,    // cycles between cmds
    parameter int unsigned       STREAM_PERIOD  = 1,    // cycles between beats
    parameter sub_e              SUB_KIND       = SUB_CNN
) (
    input  logic                clk,
    input  logic                rst_n,
    lsd_cmd_if.master           cmd_if,
    lsd_stream_if.producer      in_s,
    lsd_stream_if.consumer      out_s
);
    // -------------------------------------------------------------------------
    // PRBS engines: one for cmd, one for stream — different polynomials so
    // the two streams aren't trivially correlated.
    // -------------------------------------------------------------------------
    logic [31:0] prbs_cmd_data;
    logic        prbs_cmd_bit;
    logic        cmd_pulse;

    logic [31:0] prbs_str_data;
    logic        prbs_str_bit;
    logic        str_pulse;

    lsd_prbs_driver #(
        .WIDTH        (32),
        .SEED         (SEED ^ 32'hA5A5_A5A5),
        .POLY         (POLY),
        .PULSE_PERIOD (CMD_PERIOD)
    ) u_prbs_cmd (
        .clk       (clk),
        .rst_n     (rst_n),
        .prbs_data (prbs_cmd_data),
        .prbs_bit  (prbs_cmd_bit),
        .pulse     (cmd_pulse)
    );

    lsd_prbs_driver #(
        .WIDTH        (32),
        .SEED         (SEED ^ 32'h5A5A_5A5A),
        .POLY         (32'h04C1_1DB7),
        .PULSE_PERIOD (STREAM_PERIOD)
    ) u_prbs_str (
        .clk       (clk),
        .rst_n     (rst_n),
        .prbs_data (prbs_str_data),
        .prbs_bit  (prbs_str_bit),
        .pulse     (str_pulse)
    );

    // -------------------------------------------------------------------------
    // Cmd master: hold cmd_valid until handshake, then re-arm on next pulse.
    // -------------------------------------------------------------------------
    logic        cmd_valid_r;
    cmd_t        cmd_r;
    tag_t        tag_ctr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_valid_r <= 1'b0;
            tag_ctr     <= '0;
            cmd_r       <= '0;
        end else begin
            // Clear after handshake.
            if (cmd_valid_r && cmd_if.cmd_ready) begin
                cmd_valid_r <= 1'b0;
                tag_ctr     <= tag_ctr + 1'b1;
            end
            // Arm a new cmd when the pulse fires and we're not already busy.
            if (!cmd_valid_r && cmd_pulse) begin
                cmd_valid_r  <= 1'b1;
                cmd_r.tag    <= tag_ctr;
                cmd_r.sub    <= SUB_KIND;
                cmd_r.op     <= op_e'(prbs_cmd_data[2:0]);
                cmd_r.addr   <= prbs_cmd_data;
                cmd_r.data   <= {prbs_cmd_data, prbs_cmd_data ^ 32'hDEAD_BEEF};
                cmd_r.len    <= prbs_cmd_data[15:0];
            end
        end
    end

    assign cmd_if.cmd_valid = cmd_valid_r;
    assign cmd_if.cmd       = cmd_r;
    assign cmd_if.rsp_ready = 1'b1;   // always drain responses

    // -------------------------------------------------------------------------
    // Stream producer: drive valid every str_pulse, data = repeated PRBS.
    // -------------------------------------------------------------------------
    logic                 in_valid_r;
    logic [W-1:0]         in_data_r;
    logic                 in_sop_r;
    logic                 in_eop_r;
    logic [W/8-1:0]       in_keep_r;
    logic [7:0]           beat_ctr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_valid_r <= 1'b0;
            in_data_r  <= '0;
            in_sop_r   <= 1'b0;
            in_eop_r   <= 1'b0;
            in_keep_r  <= '1;
            beat_ctr   <= '0;
        end else begin
            if (in_valid_r && in_s.ready) begin
                in_valid_r <= 1'b0;
                beat_ctr   <= beat_ctr + 1'b1;
            end
            if (!in_valid_r && str_pulse) begin
                // Build a wide data word by tiling the 32-bit PRBS state.
                logic [W-1:0] wide;
                for (int i = 0; i < W/32; i++) begin
                    wide[i*32 +: 32] = prbs_str_data
                                     ^ {prbs_str_data[7:0], i[7:0],
                                        prbs_str_data[15:8], beat_ctr};
                end
                in_valid_r <= 1'b1;
                in_data_r  <= wide;
                in_sop_r   <= (beat_ctr == 8'd0);
                in_eop_r   <= (beat_ctr == 8'hFF);
                in_keep_r  <= '1;
            end
        end
    end

    assign in_s.valid = in_valid_r;
    assign in_s.data  = in_data_r;
    assign in_s.sop   = in_sop_r;
    assign in_s.eop   = in_eop_r;
    assign in_s.keep  = in_keep_r;

    // -------------------------------------------------------------------------
    // Stream consumer: always-ready sink with a tiny activity counter so the
    // optimiser cannot prove the consumer is dead and DCE it.
    // -------------------------------------------------------------------------
    logic [31:0] out_beats;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                              out_beats <= '0;
        else if (out_s.valid && out_s.ready)     out_beats <= out_beats + 1'b1;
    end
    assign out_s.ready = 1'b1;

    // Keep out_beats observable so it isn't optimised away. Synthesis tools
    // would warn but qopt treats this as a normal floating output.
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused_ok = |out_beats ^ |prbs_cmd_data ^ |prbs_str_data;
    /* verilator lint_on UNUSEDSIGNAL */
endmodule : lsd_self_traffic

`endif // LSD_SELF_TRAFFIC_SV
