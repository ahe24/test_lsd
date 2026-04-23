//==============================================================================
// crypto_top.sv
// Aggregates AES-256, SHA-3, RSA-4096 and ECC-256 as separate compute lanes.
// Each lane responds to commands tagged with a sub-op index in the command
// payload lower bits. Everything is wired at the top into one command slave
// and a data stream slave.
//==============================================================================
module crypto_top (
    input  logic                clk,
    input  logic                rst_n,
    lsd_cmd_if.slave            cmd_if,
    lsd_stream_if.consumer      in_s,
    lsd_stream_if.producer      out_s
);
    import lsd_pkg::*;

    // ---------------- AES lane
    logic          aes_en;
    logic [127:0]  aes_pt;
    logic [255:0]  aes_key;
    logic [127:0]  aes_ct;
    logic          aes_v;
    aes256_cipher u_aes (
        .clk(clk), .rst_n(rst_n), .en(aes_en),
        .plaintext(aes_pt), .key(aes_key),
        .ciphertext(aes_ct), .valid(aes_v)
    );

    // ---------------- SHA-3 lane
    logic          sha3_en;
    logic [63:0]   sha3_state_in  [0:24];
    logic [63:0]   sha3_state_out [0:24];
    logic          sha3_v;
    sha3_keccak_f u_sha3 (
        .clk(clk), .rst_n(rst_n), .en(sha3_en),
        .state_in(sha3_state_in), .state_out(sha3_state_out), .valid(sha3_v)
    );

    // ---------------- RSA lane
    logic          rsa_start;
    logic [4095:0] rsa_msg, rsa_exp, rsa_n, rsa_r2;
    logic [63:0]   rsa_n0_inv;
    logic [4095:0] rsa_result;
    logic          rsa_done;
    rsa_modexp_4096 u_rsa (
        .clk(clk), .rst_n(rst_n), .start(rsa_start),
        .msg(rsa_msg), .exp(rsa_exp), .n(rsa_n), .r2(rsa_r2),
        .n0_inv(rsa_n0_inv),
        .result(rsa_result), .done(rsa_done)
    );

    // ---------------- ECC lane
    logic          ecc_start;
    logic [255:0]  ecc_k;
    logic [255:0]  ecc_px, ecc_py, ecc_a, ecc_p;
    logic [255:0]  ecc_rx, ecc_ry;
    logic          ecc_done;
    ecc_scalar_mul u_ecc (
        .clk(clk), .rst_n(rst_n), .start(ecc_start),
        .k(ecc_k), .px(ecc_px), .py(ecc_py),
        .a_curve(ecc_a), .p(ecc_p),
        .rx(ecc_rx), .ry(ecc_ry), .done(ecc_done)
    );

    // ---------------- Register bank & command decode
    // addr bits [5:3] select lane, lower bits select register inside lane
    logic [255:0] shadow_key;
    logic [127:0] shadow_pt;
    logic [255:0] shadow_ecc_k;
    logic [255:0] shadow_ecc_px, shadow_ecc_py;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aes_en    <= 1'b0;
            sha3_en   <= 1'b0;
            rsa_start <= 1'b0;
            ecc_start <= 1'b0;
            shadow_key <= '0; shadow_pt <= '0;
            shadow_ecc_k <= '0; shadow_ecc_px <= '0; shadow_ecc_py <= '0;
            aes_pt <= '0; aes_key <= '0;
            rsa_msg <= '0; rsa_exp <= '0; rsa_n <= '0;
            rsa_r2 <= '0; rsa_n0_inv <= '0;
            ecc_k <= '0; ecc_px <= '0; ecc_py <= '0;
            ecc_a <= '0; ecc_p <= '0;
            for (int k = 0; k < 25; k++) sha3_state_in[k] <= '0;
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
        end else begin
            aes_en    <= 1'b0;
            sha3_en   <= 1'b0;
            rsa_start <= 1'b0;
            ecc_start <= 1'b0;
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;

            if (cmd_if.cmd_valid && cmd_if.cmd_ready) begin
                case (cmd_if.cmd.addr[5:3])
                    3'd0: begin // AES
                        aes_key <= {shadow_key[223:0], cmd_if.cmd.data[31:0]};
                        shadow_key <= aes_key;
                        aes_pt  <= {shadow_pt[95:0],  cmd_if.cmd.data[31:0]};
                        aes_en  <= (cmd_if.cmd.op == OP_KICK);
                    end
                    3'd1: begin // SHA3
                        sha3_state_in[cmd_if.cmd.addr[7:3] % 25] <= cmd_if.cmd.data;
                        sha3_en <= (cmd_if.cmd.op == OP_KICK);
                    end
                    3'd2: begin // RSA — receives streaming limbs in cmd.data
                        rsa_msg <= {rsa_msg[4031:0], cmd_if.cmd.data};
                        rsa_exp <= {rsa_exp[4031:0], cmd_if.cmd.data};
                        rsa_n   <= {rsa_n  [4031:0], cmd_if.cmd.data};
                        rsa_r2  <= {rsa_r2 [4031:0], cmd_if.cmd.data};
                        rsa_n0_inv <= cmd_if.cmd.data;
                        rsa_start  <= (cmd_if.cmd.op == OP_KICK);
                    end
                    3'd3: begin // ECC
                        ecc_k  <= {shadow_ecc_k[191:0],  cmd_if.cmd.data};
                        ecc_px <= {shadow_ecc_px[191:0], cmd_if.cmd.data};
                        ecc_py <= {shadow_ecc_py[191:0], cmd_if.cmd.data};
                        ecc_a  <= 256'h0;          // common choice; written by software normally
                        ecc_p  <= 256'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_FFFFFC2F; // secp256k1
                        ecc_start <= (cmd_if.cmd.op == OP_KICK);
                    end
                    default: ;
                endcase
                cmd_if.rsp_valid <= 1'b1;
                cmd_if.rsp       <= '{tag: cmd_if.cmd.tag, sub: SUB_CRYPTO, err: 1'b0,
                                      data: 64'h0};
            end
        end
    end

    // Stream ingest unused (per-lane protocol), ack valid
    assign in_s.ready = 1'b1;

    // Stream output multiplex
    logic [511:0] out_accum;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_s.valid <= 1'b0; out_s.data <= '0; out_s.sop <= 0; out_s.eop <= 0; out_s.keep <= '1;
            out_accum <= '0;
        end else begin
            out_s.valid <= aes_v | sha3_v | rsa_done | ecc_done;
            out_s.sop   <= 1'b1;
            out_s.eop   <= 1'b1;
            out_s.keep  <= '1;
            if (aes_v)       out_accum <= {384'h0, aes_ct};
            else if (sha3_v) out_accum <= {sha3_state_out[0], sha3_state_out[1], sha3_state_out[2],
                                           sha3_state_out[3], sha3_state_out[4], sha3_state_out[5],
                                           sha3_state_out[6], sha3_state_out[7]};
            else if (rsa_done) out_accum <= rsa_result[511:0];
            else if (ecc_done) out_accum <= {256'h0, ecc_rx};
            out_s.data <= out_accum;
        end
    end
endmodule : crypto_top
