//==============================================================================
// ecc_fp_mul256.sv
// Iterative 256x256 → 256 bit modular multiplier using simple shift-and-add,
// reducing with a conditional subtract of p each cycle (interleaved modular
// multiplication). Fully synthesisable, 256 cycles per op.
//==============================================================================
module ecc_fp_mul256 (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [255:0]       a,
    input  logic [255:0]       b,
    input  logic [255:0]       p,
    output logic [255:0]       r,
    output logic               done
);
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} st_e;
    st_e st;
    logic [255:0] acc, a_r, b_r, p_r;
    logic [8:0]   cnt;
    logic [256:0] shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st   <= S_IDLE;
            acc  <= '0;
            a_r  <= '0;
            b_r  <= '0;
            p_r  <= '0;
            cnt  <= '0;
            done <= 1'b0;
            r    <= '0;
        end else begin
            done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    acc <= '0;
                    a_r <= a;
                    b_r <= b;
                    p_r <= p;
                    cnt <= '0;
                    st  <= S_RUN;
                end
                S_RUN: begin
                    // shift acc left 1, reduce mod p
                    shift = {acc, 1'b0};
                    if (shift >= {1'b0, p_r}) shift = shift - {1'b0, p_r};
                    if (b_r[255]) begin
                        shift = shift + {1'b0, a_r};
                        if (shift >= {1'b0, p_r}) shift = shift - {1'b0, p_r};
                    end
                    acc <= shift[255:0];
                    b_r <= {b_r[254:0], 1'b0};
                    cnt <= cnt + 1'b1;
                    if (cnt == 9'd255) begin
                        r  <= shift[255:0];
                        st <= S_DONE;
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
            endcase
        end
    end
endmodule : ecc_fp_mul256
