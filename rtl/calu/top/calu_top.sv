//==============================================================================
// calu_top.sv
// Complex ALU subsystem top: FFT engine + matrix mul + matrix inverse + bank
// of scalar FP complex ops.
//==============================================================================
module calu_top (
    input  logic                clk,
    input  logic                rst_n,
    lsd_cmd_if.slave            cmd_if,
    lsd_stream_if.consumer      in_s,
    lsd_stream_if.producer      out_s
);
    import lsd_pkg::*;

    // Operand banks
    logic signed [31:0] x_re [0:63];
    logic signed [31:0] x_im [0:63];
    logic signed [31:0] y_re [0:63];
    logic signed [31:0] y_im [0:63];
    logic               fft_v;
    logic               fft_en;

    calu_fft64_pipeline u_fft (
        .clk(clk), .rst_n(rst_n), .en(fft_en),
        .x_re(x_re), .x_im(x_im),
        .y_re(y_re), .y_im(y_im),
        .valid(fft_v)
    );

    // 8x8 matrix mul and inv
    logic signed [31:0] A [0:7][0:7];
    logic signed [31:0] B [0:7][0:7];
    logic signed [31:0] C [0:7][0:7];
    logic signed [31:0] Ainv [0:7][0:7];
    logic               mm_v, inv_start, inv_done;
    logic               mm_en;

    calu_mat_mul_8x8 u_mm (
        .clk(clk), .rst_n(rst_n), .en(mm_en),
        .A(A), .B(B), .C(C), .valid(mm_v)
    );
    calu_mat_inv_8x8 u_inv (
        .clk(clk), .rst_n(rst_n), .start(inv_start),
        .A(A), .Ainv(Ainv), .done(inv_done)
    );

    // Bank of 16 independent scalar complex multipliers (for stress)
    logic signed [31:0] scal_ar [0:15], scal_ai [0:15];
    logic signed [31:0] scal_br [0:15], scal_bi [0:15];
    logic signed [31:0] scal_yr [0:15], scal_yi [0:15];
    logic               scal_v  [0:15];
    logic               scal_en;
    genvar m;
    generate
        for (m = 0; m < 16; m++) begin : g_sc
            calu_fp_mul u_sc (
                .clk(clk), .rst_n(rst_n), .en(scal_en),
                .ar(scal_ar[m]), .ai(scal_ai[m]),
                .br(scal_br[m]), .bi(scal_bi[m]),
                .yr(scal_yr[m]), .yi(scal_yi[m]),
                .valid(scal_v[m])
            );
        end
    endgenerate

    // Command decode & register writes
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
            fft_en <= 1'b0; mm_en <= 1'b0; inv_start <= 1'b0; scal_en <= 1'b0;
            for (int k = 0; k < 64; k++) begin x_re[k] <= '0; x_im[k] <= '0; end
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 8; j++) begin A[i][j] <= '0; B[i][j] <= '0; end
            for (int m2 = 0; m2 < 16; m2++) begin
                scal_ar[m2] <= '0; scal_ai[m2] <= '0;
                scal_br[m2] <= '0; scal_bi[m2] <= '0;
            end
        end else begin
            cmd_if.cmd_ready <= 1'b1;
            cmd_if.rsp_valid <= 1'b0;
            fft_en <= 1'b0; mm_en <= 1'b0; inv_start <= 1'b0; scal_en <= 1'b0;

            if (cmd_if.cmd_valid && cmd_if.cmd_ready) begin
                case (cmd_if.cmd.addr[11:8])
                    4'd0: begin
                        x_re[cmd_if.cmd.addr[5:0]] <= cmd_if.cmd.data[31:0];
                        x_im[cmd_if.cmd.addr[5:0]] <= cmd_if.cmd.data[63:32];
                    end
                    4'd1: A[cmd_if.cmd.addr[5:3]][cmd_if.cmd.addr[2:0]] <= cmd_if.cmd.data[31:0];
                    4'd2: B[cmd_if.cmd.addr[5:3]][cmd_if.cmd.addr[2:0]] <= cmd_if.cmd.data[31:0];
                    4'd3: begin
                        scal_ar[cmd_if.cmd.addr[3:0]] <= cmd_if.cmd.data[31:0];
                        scal_ai[cmd_if.cmd.addr[3:0]] <= cmd_if.cmd.data[63:32];
                    end
                    4'd4: begin
                        scal_br[cmd_if.cmd.addr[3:0]] <= cmd_if.cmd.data[31:0];
                        scal_bi[cmd_if.cmd.addr[3:0]] <= cmd_if.cmd.data[63:32];
                    end
                    4'd5: begin
                        case (cmd_if.cmd.addr[2:0])
                            3'd0: fft_en    <= (cmd_if.cmd.op == OP_KICK);
                            3'd1: mm_en     <= (cmd_if.cmd.op == OP_KICK);
                            3'd2: inv_start <= (cmd_if.cmd.op == OP_KICK);
                            3'd3: scal_en   <= (cmd_if.cmd.op == OP_KICK);
                            default: ;
                        endcase
                    end
                    default: ;
                endcase
                cmd_if.rsp_valid <= 1'b1;
                cmd_if.rsp       <= '{tag: cmd_if.cmd.tag, sub: SUB_CALU, err: 1'b0,
                                      data: {y_re[0], y_im[0]}};
            end
        end
    end

    assign in_s.ready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_s.valid <= 1'b0; out_s.data <= '0;
            out_s.sop <= 0; out_s.eop <= 0; out_s.keep <= '1;
        end else begin
            out_s.valid <= fft_v | mm_v | inv_done | scal_v[0];
            out_s.sop   <= 1'b1;
            out_s.eop   <= 1'b1;
            out_s.keep  <= '1;
            if (fft_v)
                out_s.data <= {y_re[0], y_im[0], y_re[1], y_im[1], y_re[2], y_im[2],
                               y_re[3], y_im[3], y_re[4], y_im[4], y_re[5], y_im[5],
                               y_re[6], y_im[6], y_re[7], y_im[7]};
            else if (mm_v)
                out_s.data <= {C[0][0], C[0][1], C[0][2], C[0][3],
                               C[0][4], C[0][5], C[0][6], C[0][7],
                               C[1][0], C[1][1], C[1][2], C[1][3],
                               C[1][4], C[1][5], C[1][6], C[1][7]};
            else if (inv_done)
                out_s.data <= {Ainv[0][0], Ainv[0][1], Ainv[0][2], Ainv[0][3],
                               Ainv[0][4], Ainv[0][5], Ainv[0][6], Ainv[0][7],
                               Ainv[1][0], Ainv[1][1], Ainv[1][2], Ainv[1][3],
                               Ainv[1][4], Ainv[1][5], Ainv[1][6], Ainv[1][7]};
            else
                out_s.data <= {scal_yr[0], scal_yi[0],
                               scal_yr[1], scal_yi[1],
                               scal_yr[2], scal_yi[2],
                               scal_yr[3], scal_yi[3],
                               448'h0};
        end
    end
endmodule : calu_top
