//==============================================================================
// cnn_top.sv
// Top-level CNN accelerator: an array of CNN tiles plus a per-tile
// normalisation block. Each tile is uniquely parameterised by TILE_ID so
// that downstream passes (elaboration, optimisation) see distinct instances.
//==============================================================================
module cnn_top #(parameter int NUM_TILES = 16) (
    input  logic         clk,
    input  logic         rst_n,
    lsd_cmd_if.slave     cmd_if,
    lsd_stream_if.consumer in_s,
    lsd_stream_if.producer out_s
);
    import lsd_pkg::*;

    // Simple command decode: we accept OP_KICK to load weights from command
    // data; otherwise we acknowledge with no-op.
    logic              start_r;
    logic              load_w;
    logic [7:0]        kick_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_r <= 1'b0;
            load_w  <= 1'b0;
            kick_cnt<= '0;
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
        end else begin
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
            start_r          <= 1'b0;
            load_w           <= 1'b0;
            if (cmd_if.cmd_valid && cmd_if.cmd_ready) begin
                case (cmd_if.cmd.op)
                    OP_KICK: begin
                        start_r          <= 1'b1;
                        load_w           <= 1'b1;
                        kick_cnt         <= kick_cnt + 1'b1;
                        cmd_if.rsp_valid <= 1'b1;
                        cmd_if.rsp       <= '{tag: cmd_if.cmd.tag, sub: SUB_CNN, err: 1'b0,
                                              data: {56'h0, kick_cnt}};
                    end
                    default: begin
                        cmd_if.rsp_valid <= 1'b1;
                        cmd_if.rsp       <= '{tag: cmd_if.cmd.tag, sub: SUB_CNN, err: 1'b0,
                                              data: 64'hC0FFEE00_CAFEBABE};
                    end
                endcase
            end
        end
    end

    // Fabricate simple stimulus for each tile from the stream interface.
    logic signed [15:0] w_bank  [0:NUM_TILES-1][0:63];
    logic signed [15:0] a_bank  [0:NUM_TILES-1][0:7];
    logic signed [47:0] ps_bank [0:NUM_TILES-1][0:7];
    logic signed [15:0] tile_act  [0:NUM_TILES-1][0:7];
    logic signed [15:0] tile_pool [0:NUM_TILES-1];
    logic               tile_v    [0:NUM_TILES-1];

    // Stream ingest populates weight banks by rotation.
    logic [$clog2(NUM_TILES*64)-1:0] ing_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ing_cnt <= '0;
            in_s.ready <= 1'b1;
            for (int t = 0; t < NUM_TILES; t++) begin
                for (int i = 0; i < 64; i++) w_bank[t][i] <= '0;
                for (int i = 0; i < 8;  i++) a_bank[t][i] <= '0;
                for (int i = 0; i < 8;  i++) ps_bank[t][i] <= '0;
            end
        end else begin
            in_s.ready <= 1'b1;
            if (in_s.valid && in_s.ready) begin
                automatic int tid = int'(ing_cnt / 64) % NUM_TILES;
                automatic int wid = int'(ing_cnt % 64);
                w_bank[tid][wid] <= in_s.data[15:0];
                // scatter remaining bits into inputs
                a_bank[tid][wid[2:0]] <= in_s.data[31:16] ^ 16'hA5A5;
                ps_bank[tid][wid[2:0]] <= {16'h0, in_s.data[63:32]};
                ing_cnt <= ing_cnt + 1'b1;
            end
        end
    end

    // Unrolled tile instantiation — each tile is a uniquely elaborated module
    // by virtue of parameter TILE_ID + distinct instance name.
    genvar t;
    generate
        for (t = 0; t < NUM_TILES; t++) begin : g_tile
            cnn_tile_engine #(.TILE_ID(t)) u_tile (
                .clk      (clk),
                .rst_n    (rst_n),
                .en       (start_r),
                .load_w   (load_w),
                .w_flat   (w_bank[t]),
                .a_west   (a_bank[t]),
                .ps_north (ps_bank[t]),
                .act_out  (tile_act[t]),
                .pool_out (tile_pool[t]),
                .valid    (tile_v[t])
            );
        end
    endgenerate

    // Stream output: emit concatenated pool results.
    logic [15:0] out_cnt;
    logic        any_tile_v;
    always_comb begin
        any_tile_v = 1'b0;
        for (int ti = 0; ti < NUM_TILES; ti++) any_tile_v |= tile_v[ti];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_s.valid <= 1'b0;
            out_s.data  <= '0;
            out_s.sop   <= 1'b0;
            out_s.eop   <= 1'b0;
            out_s.keep  <= '1;
            out_cnt     <= '0;
        end else begin
            out_s.valid <= any_tile_v;
            out_s.sop   <= (out_cnt == 0);
            out_s.eop   <= (out_cnt == NUM_TILES-1);
            out_s.keep  <= '1;
            if (any_tile_v) begin
                out_s.data <= { {(512-16*NUM_TILES){1'b0}}, {tile_pool[NUM_TILES-1], tile_pool[0]} };
                out_cnt    <= out_cnt + 1'b1;
            end
        end
    end
endmodule : cnn_top
