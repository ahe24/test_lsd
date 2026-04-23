//==============================================================================
// lsd_stream_merge.sv
// 5-producer → 1-consumer merge with round-robin arbitration.
//==============================================================================
module lsd_stream_merge (
    input  logic       clk,
    input  logic       rst_n,

    lsd_stream_if.consumer cnn_s,
    lsd_stream_if.consumer crypto_s,
    lsd_stream_if.consumer gfx_s,
    lsd_stream_if.consumer calu_s,
    lsd_stream_if.consumer eccd_s,
    lsd_stream_if.producer dst
);
    logic [4:0] req, gnt;
    logic [2:0] gnt_idx;
    logic       any;
    assign req = {eccd_s.valid, calu_s.valid, gfx_s.valid, crypto_s.valid, cnn_s.valid};

    lsd_rr_arbiter #(.N(5)) u_arb (
        .clk(clk), .rst_n(rst_n),
        .req(req), .gnt(gnt), .any_gnt(any), .gnt_idx(gnt_idx)
    );

    always_comb begin
        cnn_s.ready    = 1'b0;
        crypto_s.ready = 1'b0;
        gfx_s.ready    = 1'b0;
        calu_s.ready   = 1'b0;
        eccd_s.ready   = 1'b0;
        dst.valid      = 1'b0;
        dst.data       = '0;
        dst.sop        = 0;
        dst.eop        = 0;
        dst.keep       = '0;

        case (gnt)
            5'b00001: begin dst.valid = cnn_s.valid;    dst.data = cnn_s.data;    dst.sop = cnn_s.sop;    dst.eop = cnn_s.eop;    dst.keep = cnn_s.keep;    cnn_s.ready    = dst.ready; end
            5'b00010: begin dst.valid = crypto_s.valid; dst.data = crypto_s.data; dst.sop = crypto_s.sop; dst.eop = crypto_s.eop; dst.keep = crypto_s.keep; crypto_s.ready = dst.ready; end
            5'b00100: begin dst.valid = gfx_s.valid;    dst.data = gfx_s.data;    dst.sop = gfx_s.sop;    dst.eop = gfx_s.eop;    dst.keep = gfx_s.keep;    gfx_s.ready    = dst.ready; end
            5'b01000: begin dst.valid = calu_s.valid;   dst.data = calu_s.data;   dst.sop = calu_s.sop;   dst.eop = calu_s.eop;   dst.keep = calu_s.keep;   calu_s.ready   = dst.ready; end
            5'b10000: begin dst.valid = eccd_s.valid;   dst.data = eccd_s.data;   dst.sop = eccd_s.sop;   dst.eop = eccd_s.eop;   dst.keep = eccd_s.keep;   eccd_s.ready   = dst.ready; end
            default: ;
        endcase
    end
endmodule : lsd_stream_merge
