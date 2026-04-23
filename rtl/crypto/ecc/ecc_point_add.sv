//==============================================================================
// ecc_point_add.sv
// Affine-coordinate point addition P + Q over F_p (no doubling case).
// Shares a modular multiplier with surrounding logic via the port interface.
//==============================================================================
module ecc_point_add (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                start,
    input  logic [255:0]        px, py,
    input  logic [255:0]        qx, qy,
    input  logic [255:0]        p,
    output logic [255:0]        rx, ry,
    output logic                done
);
    typedef enum logic [3:0] {
        S_IDLE, S_SUB_X, S_SUB_Y, S_INV, S_MUL_LAM, S_W1,
        S_SQR_LAM, S_W2, S_SUB_X1, S_SUB_X2, S_MUL_DX, S_W3, S_SUB_Y1, S_DONE
    } st_e;
    st_e st;

    // Shared modules
    logic [255:0] mul_a_i, mul_b_i, mul_r_i;
    logic mul_s_i, mul_d_i;
    ecc_fp_mul256 u_mul (.clk(clk), .rst_n(rst_n), .start(mul_s_i),
                         .a(mul_a_i), .b(mul_b_i), .p(p), .r(mul_r_i), .done(mul_d_i));
    logic [255:0] sa_a, sa_b, sa_r;
    ecc_fp_sub256 u_sub (.a(sa_a), .b(sa_b), .p(p), .r(sa_r));

    logic [255:0] dx, dy, inv_dx, lam, lam2, x_r, y_r, t1;

    always_comb inv_dx = dx; // placeholder for Fermat-inverse engine

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            mul_s_i <= 1'b0; mul_a_i <= '0; mul_b_i <= '0;
            sa_a <= '0; sa_b <= '0;
            dx <= '0; dy <= '0; lam <= '0; lam2 <= '0;
            x_r <= '0; y_r <= '0; t1 <= '0;
            rx <= '0; ry <= '0;
            done <= 1'b0;
        end else begin
            mul_s_i <= 1'b0;
            done    <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    sa_a <= qx; sa_b <= px;
                    st   <= S_SUB_X;
                end
                S_SUB_X: begin
                    dx   <= sa_r;
                    sa_a <= qy; sa_b <= py;
                    st   <= S_SUB_Y;
                end
                S_SUB_Y: begin
                    dy      <= sa_r;
                    mul_a_i <= sa_r;
                    mul_b_i <= inv_dx;
                    mul_s_i <= 1'b1;
                    st      <= S_W1;
                end
                S_W1: if (mul_d_i) begin
                    lam     <= mul_r_i;
                    mul_a_i <= mul_r_i; mul_b_i <= mul_r_i;
                    mul_s_i <= 1'b1;
                    st      <= S_W2;
                end
                S_W2: if (mul_d_i) begin
                    lam2 <= mul_r_i;
                    sa_a <= mul_r_i; sa_b <= px;
                    st   <= S_SUB_X1;
                end
                S_SUB_X1: begin
                    t1 <= sa_r;
                    sa_a <= sa_r; sa_b <= qx;
                    st   <= S_SUB_X2;
                end
                S_SUB_X2: begin
                    x_r <= sa_r;
                    rx  <= sa_r;
                    sa_a <= px; sa_b <= sa_r;
                    st   <= S_MUL_DX;
                end
                S_MUL_DX: begin
                    mul_a_i <= lam; mul_b_i <= sa_r; mul_s_i <= 1'b1;
                    st <= S_W3;
                end
                S_W3: if (mul_d_i) begin
                    sa_a <= mul_r_i; sa_b <= py;
                    st   <= S_SUB_Y1;
                end
                S_SUB_Y1: begin
                    y_r <= sa_r; ry <= sa_r;
                    st  <= S_DONE;
                end
                S_DONE: begin
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : ecc_point_add
