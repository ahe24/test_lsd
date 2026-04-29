//==============================================================================
// lsd_self_traffic.sv
// Per-subsystem self-driving stimulus block.  Owns one cmd master + one
// stream producer + one stream consumer, all driven by an internal PRBS
// source.  Each instance is a closed traffic island: ParallelSim can place
// it in its own partition without any cross-partition handle from the
// testbench.
//
// PLUSARG INTERFACE (read once at time 0, then frozen)
// ----------------------------------------------------
// INST_TAG = "cnn"  ⇒
//   +cnn_cmd_period=<int>   per-cycle cmd issuance period (default = CMD_PERIOD)
//   +cnn_str_period=<int>   per-cycle stream beat period  (default = STREAM_PERIOD)
//   +cnn_disable=<0|1>      mute this island entirely (cmd/stream stay quiet,
//                           consumer stays ready)         (default = 0)
//
// Reading once and storing in module-local registers means the testbench
// never reaches *into* the module at runtime — every signal that crosses
// the partition boundary is determined at $value$plusargs() time, which
// happens before any clocked simulation.  Safe for ParallelSim FoU.
//==============================================================================
`ifndef LSD_SELF_TRAFFIC_SV
`define LSD_SELF_TRAFFIC_SV

module lsd_self_traffic
    import lsd_pkg::*;
#(
    parameter int unsigned       W              = 512,
    parameter logic [31:0]       SEED           = 32'h1234_5678,
    parameter logic [31:0]       POLY           = 32'hEDB8_8320,
    parameter int unsigned       CMD_PERIOD     = 8,    // cycles between cmds (default)
    parameter int unsigned       STREAM_PERIOD  = 1,    // cycles between beats (default)
    parameter sub_e              SUB_KIND       = SUB_CNN,
    parameter string             INST_TAG       = "x"
) (
    input  logic                clk,
    input  logic                rst_n,
    lsd_cmd_if.master           cmd_if,
    lsd_stream_if.producer      in_s,
    lsd_stream_if.consumer      out_s
);
    // -------------------------------------------------------------------------
    // Plusarg-overridable knobs.  Captured at time 0; after that the values
    // never change, so no tb→DUT signal crosses the partition wall.
    // -------------------------------------------------------------------------
    int  cmd_period_eff;
    int  str_period_eff;
    int  disable_eff;

    initial begin
        string s;
        cmd_period_eff = CMD_PERIOD;
        str_period_eff = STREAM_PERIOD;
        disable_eff    = 0;
        $sformat(s, "%0s_cmd_period=%%d", INST_TAG);
        void'($value$plusargs(s, cmd_period_eff));
        $sformat(s, "%0s_str_period=%%d", INST_TAG);
        void'($value$plusargs(s, str_period_eff));
        $sformat(s, "%0s_disable=%%d",    INST_TAG);
        void'($value$plusargs(s, disable_eff));
        if (cmd_period_eff < 1) cmd_period_eff = 1;
        if (str_period_eff < 1) str_period_eff = 1;
        $display("[self_traffic %0s] cmd_period=%0d str_period=%0d disable=%0d",
                 INST_TAG, cmd_period_eff, str_period_eff, disable_eff);
    end

    // -------------------------------------------------------------------------
    // PRBS engines: one for cmd, one for stream — different polynomials so
    // the two streams aren't trivially correlated.
    // -------------------------------------------------------------------------
    logic [31:0] prbs_cmd_data;
    logic [31:0] prbs_str_data;

    lsd_prbs_driver #(
        .WIDTH(32),
        .SEED (SEED ^ 32'hA5A5_A5A5),
        .POLY (POLY)
    ) u_prbs_cmd (
        .clk      (clk),
        .rst_n    (rst_n),
        .prbs_data(prbs_cmd_data),
        .prbs_bit ()
    );

    lsd_prbs_driver #(
        .WIDTH(32),
        .SEED (SEED ^ 32'h5A5A_5A5A),
        .POLY (32'h04C1_1DB7)
    ) u_prbs_str (
        .clk      (clk),
        .rst_n    (rst_n),
        .prbs_data(prbs_str_data),
        .prbs_bit ()
    );

    // -------------------------------------------------------------------------
    // Period dividers — runtime configurable counters.
    // -------------------------------------------------------------------------
    int   cmd_div_cnt;
    int   str_div_cnt;
    logic cmd_pulse_raw;
    logic str_pulse_raw;
    logic cmd_pulse;
    logic str_pulse;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                                 cmd_div_cnt <= 0;
        else if (cmd_div_cnt + 1 >= cmd_period_eff) cmd_div_cnt <= 0;
        else                                        cmd_div_cnt <= cmd_div_cnt + 1;
    end
    assign cmd_pulse_raw = (cmd_div_cnt + 1 >= cmd_period_eff);
    assign cmd_pulse     = cmd_pulse_raw & ~|disable_eff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                                 str_div_cnt <= 0;
        else if (str_div_cnt + 1 >= str_period_eff) str_div_cnt <= 0;
        else                                        str_div_cnt <= str_div_cnt + 1;
    end
    assign str_pulse_raw = (str_div_cnt + 1 >= str_period_eff);
    assign str_pulse     = str_pulse_raw & ~|disable_eff;

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
            if (cmd_valid_r && cmd_if.cmd_ready) begin
                cmd_valid_r <= 1'b0;
                tag_ctr     <= tag_ctr + 1'b1;
            end
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

    assign cmd_if.cmd_valid = cmd_valid_r & ~|disable_eff;
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

    assign in_s.valid = in_valid_r & ~|disable_eff;
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

    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused_ok = |out_beats ^ |prbs_cmd_data ^ |prbs_str_data;
    /* verilator lint_on UNUSEDSIGNAL */
endmodule : lsd_self_traffic

`endif // LSD_SELF_TRAFFIC_SV
