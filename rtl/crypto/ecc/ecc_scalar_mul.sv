//==============================================================================
// ecc_scalar_mul.sv
// Double-and-add scalar multiplication: R = k·P. Uses one ecc_point_double and
// one ecc_point_add sequentially.
//==============================================================================
module ecc_scalar_mul (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [255:0]       k,
    input  logic [255:0]       px, py,
    input  logic [255:0]       a_curve,
    input  logic [255:0]       p,
    output logic [255:0]       rx, ry,
    output logic               done
);
    typedef enum logic [2:0] {S_IDLE, S_DBL, S_WAIT_DBL, S_ADD, S_WAIT_ADD, S_DONE} st_e;
    st_e st;

    logic [255:0] acc_x, acc_y;
    logic [7:0]   bit_i;

    logic          dbl_start, dbl_done;
    logic [255:0]  dbl_rx, dbl_ry;
    ecc_point_double u_dbl (
        .clk(clk), .rst_n(rst_n), .start(dbl_start),
        .px(acc_x), .py(acc_y), .a_curve(a_curve), .p(p),
        .rx(dbl_rx), .ry(dbl_ry), .done(dbl_done)
    );

    logic          add_start, add_done;
    logic [255:0]  add_rx, add_ry;
    ecc_point_add u_add (
        .clk(clk), .rst_n(rst_n), .start(add_start),
        .px(acc_x), .py(acc_y), .qx(px), .qy(py), .p(p),
        .rx(add_rx), .ry(add_ry), .done(add_done)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            acc_x <= '0; acc_y <= '0;
            bit_i <= '0;
            dbl_start <= 1'b0; add_start <= 1'b0;
            rx <= '0; ry <= '0;
            done <= 1'b0;
        end else begin
            dbl_start <= 1'b0;
            add_start <= 1'b0;
            done      <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    acc_x <= '0; acc_y <= '0;
                    bit_i <= 8'd255;
                    st    <= S_DBL;
                end
                S_DBL: begin
                    dbl_start <= 1'b1;
                    st        <= S_WAIT_DBL;
                end
                S_WAIT_DBL: if (dbl_done) begin
                    acc_x <= dbl_rx; acc_y <= dbl_ry;
                    if (k[bit_i]) begin
                        add_start <= 1'b1;
                        st        <= S_WAIT_ADD;
                    end else begin
                        st <= S_ADD;
                    end
                end
                S_ADD: begin
                    if (bit_i == 0) st <= S_DONE;
                    else begin
                        bit_i <= bit_i - 1'b1;
                        st    <= S_DBL;
                    end
                end
                S_WAIT_ADD: if (add_done) begin
                    acc_x <= add_rx; acc_y <= add_ry;
                    if (bit_i == 0) st <= S_DONE;
                    else begin
                        bit_i <= bit_i - 1'b1;
                        st    <= S_DBL;
                    end
                end
                S_DONE: begin
                    rx <= acc_x; ry <= acc_y;
                    done <= 1'b1;
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : ecc_scalar_mul
