//==============================================================================
// lsd_stream_fanout.sv
// 1-producer → 5-consumer broadcast for input streaming.
//==============================================================================
module lsd_stream_fanout (
    input  logic       clk,
    input  logic       rst_n,

    lsd_stream_if.consumer src,
    lsd_stream_if.producer cnn_s,
    lsd_stream_if.producer crypto_s,
    lsd_stream_if.producer gfx_s,
    lsd_stream_if.producer calu_s,
    lsd_stream_if.producer eccd_s
);
    logic all_ready;
    assign all_ready = cnn_s.ready & crypto_s.ready & gfx_s.ready
                     & calu_s.ready & eccd_s.ready;

    assign src.ready = all_ready;

    assign cnn_s.valid    = src.valid & all_ready;
    assign crypto_s.valid = src.valid & all_ready;
    assign gfx_s.valid    = src.valid & all_ready;
    assign calu_s.valid   = src.valid & all_ready;
    assign eccd_s.valid   = src.valid & all_ready;

    assign cnn_s.data    = src.data; assign cnn_s.sop    = src.sop;
    assign cnn_s.eop     = src.eop;  assign cnn_s.keep   = src.keep;
    assign crypto_s.data = src.data; assign crypto_s.sop = src.sop;
    assign crypto_s.eop  = src.eop;  assign crypto_s.keep= src.keep;
    assign gfx_s.data    = src.data; assign gfx_s.sop    = src.sop;
    assign gfx_s.eop     = src.eop;  assign gfx_s.keep   = src.keep;
    assign calu_s.data   = src.data; assign calu_s.sop   = src.sop;
    assign calu_s.eop    = src.eop;  assign calu_s.keep  = src.keep;
    assign eccd_s.data   = src.data; assign eccd_s.sop   = src.sop;
    assign eccd_s.eop    = src.eop;  assign eccd_s.keep  = src.keep;
endmodule : lsd_stream_fanout
