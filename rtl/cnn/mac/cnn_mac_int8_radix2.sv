//==============================================================================
// cnn_mac_int8_radix2.sv
// Signed 8-bit MAC, radix-2 shift/add multiplier, 32-bit accumulator.
// Explicitly rolled as a serial radix-2 booth-less multiplier so it is
// structurally distinct from the tree/array/Wallace variants.
//==============================================================================
module cnn_mac_int8_radix2 (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic signed [7:0]  a,
    input  logic signed [7:0]  b,
    input  logic signed [31:0] acc_in,
    output logic signed [31:0] acc_out,
    output logic               done
);
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_ADD, S_DONE} st_e;
    st_e st;
    logic [3:0]  cnt;
    logic signed [15:0] prod_r;
    logic signed [7:0]  b_r;
    logic signed [15:0] a_ext;

    assign a_ext = { {8{a[7]}}, a };

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= S_IDLE;
            cnt      <= '0;
            prod_r   <= '0;
            b_r      <= '0;
            acc_out  <= '0;
            done     <= 1'b0;
        end else begin
            done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    prod_r <= '0;
                    b_r    <= b;
                    cnt    <= 4'd0;
                    st     <= S_RUN;
                end
                S_RUN: begin
                    if (b_r[0]) prod_r <= prod_r + (a_ext <<< cnt);
                    b_r    <= { b_r[7], b_r[7:1] }; // arithmetic shift
                    cnt    <= cnt + 1'b1;
                    if (cnt == 4'd7) st <= S_ADD;
                end
                S_ADD: begin
                    acc_out <= acc_in + {{16{prod_r[15]}}, prod_r};
                    st      <= S_DONE;
                end
                S_DONE: begin
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
            endcase
        end
    end
endmodule : cnn_mac_int8_radix2
