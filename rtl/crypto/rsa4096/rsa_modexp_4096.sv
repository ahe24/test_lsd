//==============================================================================
// rsa_modexp_4096.sv
// Binary (left-to-right) modular exponentiation driving one rsa_montmul_4096.
// Caller supplies M, e, n, r^2 mod n, n0_inv. Produces r = M^e mod n.
//==============================================================================
module rsa_modexp_4096 (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [4095:0]      msg,
    input  logic [4095:0]      exp,
    input  logic [4095:0]      n,
    input  logic [4095:0]      r2,
    input  logic [63:0]        n0_inv,
    output logic [4095:0]      result,
    output logic               done
);
    typedef enum logic [3:0] {
        S_IDLE, S_TO_MON, S_WAIT_TOMON, S_SQR, S_WAIT_SQR,
        S_MUL, S_WAIT_MUL, S_FROM_MON, S_WAIT_FROMON, S_DONE
    } st_e;
    st_e st;

    logic [4095:0] base_mon, acc_mon;
    logic [4095:0] mm_a, mm_b, mm_out;
    logic          mm_start, mm_done;

    rsa_montmul_4096 u_mm (
        .clk(clk), .rst_n(rst_n),
        .start (mm_start),
        .a     (mm_a),
        .b     (mm_b),
        .n     (n),
        .n0_inv(n0_inv),
        .result(mm_out),
        .done  (mm_done)
    );

    logic [12:0] bit_idx;    // 4096 bits
    logic [4095:0] exp_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= S_IDLE;
            mm_start <= 1'b0;
            mm_a     <= '0;
            mm_b     <= '0;
            acc_mon  <= '0;
            base_mon <= '0;
            bit_idx  <= '0;
            done     <= 1'b0;
            exp_r    <= '0;
        end else begin
            mm_start <= 1'b0;
            done     <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    exp_r <= exp;
                    mm_a  <= msg;
                    mm_b  <= r2;
                    mm_start <= 1'b1;
                    st    <= S_WAIT_TOMON;
                end
                S_WAIT_TOMON: if (mm_done) begin
                    base_mon <= mm_out;
                    // acc = 1 in Montgomery form = r mod n. Compute via mm(1, r2) = r
                    mm_a     <= 4096'd1;
                    mm_b     <= r2;
                    mm_start <= 1'b1;
                    st       <= S_TO_MON;
                end
                S_TO_MON: if (mm_done) begin
                    acc_mon <= mm_out;
                    bit_idx <= 13'd4095;
                    st      <= S_SQR;
                end
                S_SQR: begin
                    mm_a     <= acc_mon;
                    mm_b     <= acc_mon;
                    mm_start <= 1'b1;
                    st       <= S_WAIT_SQR;
                end
                S_WAIT_SQR: if (mm_done) begin
                    acc_mon <= mm_out;
                    if (exp_r[bit_idx]) begin
                        mm_a     <= mm_out;
                        mm_b     <= base_mon;
                        mm_start <= 1'b1;
                        st       <= S_WAIT_MUL;
                    end else begin
                        st <= S_MUL; // fall-through
                    end
                end
                S_MUL: begin
                    if (bit_idx == 0) st <= S_FROM_MON;
                    else begin
                        bit_idx <= bit_idx - 1'b1;
                        st      <= S_SQR;
                    end
                end
                S_WAIT_MUL: if (mm_done) begin
                    acc_mon <= mm_out;
                    if (bit_idx == 0) st <= S_FROM_MON;
                    else begin
                        bit_idx <= bit_idx - 1'b1;
                        st      <= S_SQR;
                    end
                end
                S_FROM_MON: begin
                    mm_a     <= acc_mon;
                    mm_b     <= 4096'd1;
                    mm_start <= 1'b1;
                    st       <= S_WAIT_FROMON;
                end
                S_WAIT_FROMON: if (mm_done) begin
                    result <= mm_out;
                    done   <= 1'b1;
                    st     <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : rsa_modexp_4096
