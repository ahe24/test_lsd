//==============================================================================
// eccd_top.sv
// ECC codec subsystem: LDPC(648,540) and Turbo(K=1024).
//==============================================================================
module eccd_top (
    input  logic                clk,
    input  logic                rst_n,
    lsd_cmd_if.slave            cmd_if,
    lsd_stream_if.consumer      in_s,
    lsd_stream_if.producer      out_s
);
    import lsd_pkg::*;

    // LDPC
    logic signed [7:0]  ldpc_ch [0:647];
    logic               ldpc_out[0:539];
    logic               ldpc_start, ldpc_done;
    ldpc_decoder_648 u_ldpc (
        .clk(clk), .rst_n(rst_n), .start(ldpc_start),
        .ch_llr(ldpc_ch), .out_bit(ldpc_out), .done(ldpc_done)
    );

    // Turbo
    logic signed [7:0]  turbo_sys  [0:1023];
    logic signed [7:0]  turbo_par1 [0:1023];
    logic signed [7:0]  turbo_par2 [0:1023];
    logic               turbo_out  [0:1023];
    logic               turbo_start, turbo_done;
    turbo_decoder_top u_turbo (
        .clk(clk), .rst_n(rst_n), .start(turbo_start),
        .sys_llr(turbo_sys), .par1_llr(turbo_par1), .par2_llr(turbo_par2),
        .out_bit(turbo_out), .done(turbo_done)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
            ldpc_start <= 1'b0;
            turbo_start <= 1'b0;
            for (int k = 0; k < 648;  k++) ldpc_ch[k]    <= '0;
            for (int k = 0; k < 1024; k++) begin
                turbo_sys[k]  <= '0;
                turbo_par1[k] <= '0;
                turbo_par2[k] <= '0;
            end
        end else begin
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
            ldpc_start  <= 1'b0;
            turbo_start <= 1'b0;
            if (cmd_if.cmd_valid && cmd_if.cmd_ready) begin
                case (cmd_if.cmd.addr[11:10])
                    2'd0: begin // LDPC channel LLR loads
                        if (cmd_if.cmd.addr[9:0] < 648)
                            ldpc_ch[cmd_if.cmd.addr[9:0]] <= cmd_if.cmd.data[7:0];
                    end
                    2'd1: turbo_sys [cmd_if.cmd.addr[9:0]] <= cmd_if.cmd.data[7:0];
                    2'd2: turbo_par1[cmd_if.cmd.addr[9:0]] <= cmd_if.cmd.data[7:0];
                    2'd3: turbo_par2[cmd_if.cmd.addr[9:0]] <= cmd_if.cmd.data[7:0];
                    default: ;
                endcase
                case (cmd_if.cmd.addr[3:0])
                    4'hE: ldpc_start  <= (cmd_if.cmd.op == OP_KICK);
                    4'hF: turbo_start <= (cmd_if.cmd.op == OP_KICK);
                    default: ;
                endcase
                cmd_if.rsp_valid <= 1'b1;
                cmd_if.rsp       <= '{tag: cmd_if.cmd.tag, sub: SUB_ECCD, err: 1'b0, data: 64'h0};
            end
        end
    end

    assign in_s.ready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_s.valid <= 0; out_s.data <= '0;
            out_s.sop <= 0; out_s.eop <= 0; out_s.keep <= '1;
        end else begin
            out_s.valid <= ldpc_done | turbo_done;
            out_s.sop   <= 1'b1;
            out_s.eop   <= 1'b1;
            out_s.keep  <= '1;
            if (ldpc_done) begin
                automatic logic [511:0] pack_word;
                pack_word = '0;
                for (int k = 0; k < 512; k++) pack_word[k] = ldpc_out[k];
                out_s.data <= pack_word;
            end else if (turbo_done) begin
                automatic logic [511:0] pack_word;
                pack_word = '0;
                for (int k = 0; k < 512; k++) pack_word[k] = turbo_out[k];
                out_s.data <= pack_word;
            end
        end
    end
endmodule : eccd_top
