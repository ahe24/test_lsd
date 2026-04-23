//==============================================================================
// cnn_mac_bitserial.sv
// Bit-serial MAC, weight width parameterised. Processes one activation bit
// per cycle. Used to populate the accelerator with huge numbers of small
// low-area compute cells, contrasting with the parallel MACs.
//==============================================================================
module cnn_mac_bitserial #(parameter int unsigned AW = 8,
                           parameter int unsigned WW = 8,
                           parameter int unsigned ACC = 32) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 start,
    input  logic signed [WW-1:0] w,
    input  logic signed [AW-1:0] a,
    input  logic signed [ACC-1:0] acc_in,
    output logic signed [ACC-1:0] acc_out,
    output logic                 done
);
    typedef enum logic [1:0] {S_IDLE, S_SHIFT, S_FIN} st_e;
    st_e              st;
    logic [$clog2(AW+1)-1:0] cnt;
    logic signed [AW-1:0]    a_r;
    logic signed [WW+AW-1:0] partial;
    logic signed [ACC-1:0]   acc_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= S_IDLE;
            partial <= '0;
            acc_r   <= '0;
            cnt     <= '0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    a_r     <= a;
                    partial <= '0;
                    cnt     <= '0;
                    acc_r   <= acc_in;
                    st      <= S_SHIFT;
                end
                S_SHIFT: begin
                    if (a_r[0]) begin
                        partial <= partial + ($signed({ {WW{w[WW-1]}}, w }) <<< cnt);
                    end
                    a_r <= { a_r[AW-1], a_r[AW-1:1] }; // arithmetic shift
                    cnt <= cnt + 1'b1;
                    if (cnt == AW-1) st <= S_FIN;
                end
                S_FIN: begin
                    acc_out <= acc_r + { {(ACC-(WW+AW)){partial[WW+AW-1]}}, partial };
                    done    <= 1'b1;
                    st      <= S_IDLE;
                end
            endcase
        end
    end
endmodule : cnn_mac_bitserial
