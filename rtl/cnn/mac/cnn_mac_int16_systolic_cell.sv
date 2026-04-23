//==============================================================================
// cnn_mac_int16_systolic_cell.sv
// Classic systolic-array cell: weight stationary, activation propagates
// horizontally, partial sum propagates vertically.
//==============================================================================
module cnn_mac_int16_systolic_cell (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                load_w,
    input  logic signed [15:0]  w_in,
    input  logic signed [15:0]  a_in,
    input  logic signed [47:0]  ps_in,
    output logic signed [15:0]  a_out,
    output logic signed [47:0]  ps_out
);
    logic signed [15:0] w_r;
    logic signed [15:0] a_r;
    logic signed [47:0] ps_r;
    logic signed [31:0] prod;

    assign prod   = $signed(w_r) * $signed(a_r);
    assign a_out  = a_r;
    assign ps_out = ps_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_r  <= '0;
            a_r  <= '0;
            ps_r <= '0;
        end else begin
            if (load_w) w_r <= w_in;
            a_r  <= a_in;
            ps_r <= ps_in + {{16{prod[31]}}, prod};
        end
    end
endmodule : cnn_mac_int16_systolic_cell
