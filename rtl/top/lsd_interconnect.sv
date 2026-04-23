//==============================================================================
// lsd_interconnect.sv
// 1-host, 5-slave crossbar. Decodes cmd.sub field to select which slave
// receives the command, then multiplexes responses back. Both direction
// streams also fan out/in to keep cross-module wiring dense.
//==============================================================================
module lsd_interconnect (
    input  logic       clk,
    input  logic       rst_n,

    // Host side
    lsd_cmd_if.slave   h_cmd,

    // Slave sides
    lsd_cmd_if.master  s_cnn,
    lsd_cmd_if.master  s_crypto,
    lsd_cmd_if.master  s_gfx,
    lsd_cmd_if.master  s_calu,
    lsd_cmd_if.master  s_eccd
);
    import lsd_pkg::*;

    // Forward commands to the addressed slave
    always_comb begin
        // default: nothing
        s_cnn.cmd_valid    = 1'b0;
        s_crypto.cmd_valid = 1'b0;
        s_gfx.cmd_valid    = 1'b0;
        s_calu.cmd_valid   = 1'b0;
        s_eccd.cmd_valid   = 1'b0;
        s_cnn.cmd    = h_cmd.cmd;
        s_crypto.cmd = h_cmd.cmd;
        s_gfx.cmd    = h_cmd.cmd;
        s_calu.cmd   = h_cmd.cmd;
        s_eccd.cmd   = h_cmd.cmd;
        s_cnn.rsp_ready    = 1'b1;
        s_crypto.rsp_ready = 1'b1;
        s_gfx.rsp_ready    = 1'b1;
        s_calu.rsp_ready   = 1'b1;
        s_eccd.rsp_ready   = 1'b1;

        h_cmd.cmd_ready = 1'b1;
        h_cmd.rsp_valid = 1'b0;
        // Packed struct zero-fill. Using '{default:'0} trips vopt because
        // the struct contains an enum (sub_e); assigning a bare '0 packs
        // the whole struct as zeros and lets the enum take its first member.
        h_cmd.rsp       = '0;

        if (h_cmd.cmd_valid) begin
            unique case (h_cmd.cmd.sub)
                SUB_CNN:    begin s_cnn.cmd_valid    = 1'b1; h_cmd.cmd_ready = s_cnn.cmd_ready;    end
                SUB_CRYPTO: begin s_crypto.cmd_valid = 1'b1; h_cmd.cmd_ready = s_crypto.cmd_ready; end
                SUB_GFX:    begin s_gfx.cmd_valid    = 1'b1; h_cmd.cmd_ready = s_gfx.cmd_ready;    end
                SUB_CALU:   begin s_calu.cmd_valid   = 1'b1; h_cmd.cmd_ready = s_calu.cmd_ready;   end
                SUB_ECCD:   begin s_eccd.cmd_valid   = 1'b1; h_cmd.cmd_ready = s_eccd.cmd_ready;   end
                default: ;
            endcase
        end

        // Priority-mux responses back to the host
        if (s_cnn.rsp_valid) begin
            h_cmd.rsp_valid = 1'b1; h_cmd.rsp = s_cnn.rsp;
        end else if (s_crypto.rsp_valid) begin
            h_cmd.rsp_valid = 1'b1; h_cmd.rsp = s_crypto.rsp;
        end else if (s_gfx.rsp_valid) begin
            h_cmd.rsp_valid = 1'b1; h_cmd.rsp = s_gfx.rsp;
        end else if (s_calu.rsp_valid) begin
            h_cmd.rsp_valid = 1'b1; h_cmd.rsp = s_calu.rsp;
        end else if (s_eccd.rsp_valid) begin
            h_cmd.rsp_valid = 1'b1; h_cmd.rsp = s_eccd.rsp;
        end
    end
endmodule : lsd_interconnect
