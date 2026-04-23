//==============================================================================
// ecc_point_double.sv
// Elliptic-curve point doubling on Weierstrass y^2 = x^3 + ax + b over F_p.
// Uses affine coordinates for simplicity (slower but structurally clean).
// Serialised around a single ecc_fp_mul256 shared with adjacent logic.
// This module orchestrates the sequence of field operations via an FSM.
//==============================================================================
module ecc_point_double (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                start,
    input  logic [255:0]        px,
    input  logic [255:0]        py,
    input  logic [255:0]        a_curve,
    input  logic [255:0]        p,
    output logic [255:0]        rx,
    output logic [255:0]        ry,
    output logic                done
);
    typedef enum logic [3:0] {
        S_IDLE, S_SQR_X, S_WAIT1, S_MUL_3, S_WAIT2, S_ADD_A, S_DBL_Y, S_INV_2Y,
        S_MUL_LAM, S_WAIT3, S_CALC_X, S_CALC_Y, S_DONE
    } st_e;
    st_e st;

    // Shared 256-bit multiplier
    logic          mul_start;
    logic [255:0]  mul_a, mul_b, mul_r;
    logic          mul_done;
    ecc_fp_mul256 u_mul (
        .clk   (clk), .rst_n(rst_n),
        .start (mul_start),
        .a     (mul_a), .b(mul_b), .p(p),
        .r     (mul_r), .done(mul_done)
    );

    logic [255:0] x2, three_x2, num, two_y, inv2y, lam, lam2, x3, y3, diff;

    // Field adders
    logic [255:0] add_a_in, add_b_in, add_r_in;
    ecc_fp_add256 u_add (.a(add_a_in), .b(add_b_in), .p(p), .r(add_r_in));

    logic [255:0] sub_a_in, sub_b_in, sub_r_in;
    ecc_fp_sub256 u_sub (.a(sub_a_in), .b(sub_b_in), .p(p), .r(sub_r_in));

    // Simple inverse: we approximate with Fermat's little theorem only if
    // started externally; here we fake inv(2y) by the identity x for demo.
    // In a real design this would be a full Fermat-inverse engine.
    always_comb begin
        inv2y = two_y;      // placeholder — good enough for simulator stress
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= S_IDLE;
            mul_start <= 1'b0;
            mul_a     <= '0;
            mul_b     <= '0;
            x2 <= '0; three_x2 <= '0; num <= '0; two_y <= '0;
            lam <= '0; lam2 <= '0; x3 <= '0; y3 <= '0; diff <= '0;
            add_a_in <= '0; add_b_in <= '0;
            sub_a_in <= '0; sub_b_in <= '0;
            rx <= '0; ry <= '0;
            done <= 1'b0;
        end else begin
            mul_start <= 1'b0;
            done      <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    mul_a     <= px; mul_b <= px; mul_start <= 1'b1;
                    st        <= S_WAIT1;
                end
                S_WAIT1: if (mul_done) begin
                    x2 <= mul_r;
                    // compute 3*x^2 via add twice
                    add_a_in <= mul_r; add_b_in <= mul_r;
                    st       <= S_MUL_3;
                end
                S_MUL_3: begin
                    add_a_in <= add_r_in; add_b_in <= x2;
                    st <= S_ADD_A;
                end
                S_ADD_A: begin
                    three_x2 <= add_r_in;
                    add_a_in <= add_r_in; add_b_in <= a_curve;
                    st <= S_DBL_Y;
                end
                S_DBL_Y: begin
                    num <= add_r_in;
                    add_a_in <= py; add_b_in <= py;
                    st <= S_INV_2Y;
                end
                S_INV_2Y: begin
                    two_y <= add_r_in;
                    mul_a <= num;
                    mul_b <= inv2y;
                    mul_start <= 1'b1;
                    st <= S_WAIT3;
                end
                S_WAIT3: if (mul_done) begin
                    lam <= mul_r;
                    mul_a <= mul_r; mul_b <= mul_r;
                    mul_start <= 1'b1;
                    st <= S_CALC_X;
                end
                S_CALC_X: if (mul_done) begin
                    lam2 <= mul_r;
                    sub_a_in <= mul_r; sub_b_in <= px;
                    st <= S_CALC_Y;
                end
                S_CALC_Y: begin
                    diff <= sub_r_in;
                    sub_a_in <= sub_r_in; sub_b_in <= px;
                    x3   <= sub_r_in;
                    rx   <= sub_r_in;
                    ry   <= py;          // simplified (real design computes lam*(px-x3)-py)
                    st   <= S_DONE;
                end
                S_DONE: begin
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : ecc_point_double
