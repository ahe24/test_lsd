//==============================================================================
// cnn_mac_int8_booth4.sv
// Signed 8-bit MAC, radix-4 modified-Booth multiplier, 32-bit accumulator.
// Combinational Booth recoding producing 4 partial products which are then
// tree-summed — structurally distinct from the radix-2 serial version.
//==============================================================================
module cnn_mac_int8_booth4 (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               en,
    input  logic signed [7:0]  a,
    input  logic signed [7:0]  b,
    input  logic signed [31:0] acc_in,
    output logic signed [31:0] acc_out,
    output logic               valid
);
    // Extended multiplier: b' = {b[7], b, 1'b0} → 4 groups of 3 bits
    logic [9:0] b_ext;
    logic signed [15:0] pp [0:3];
    logic signed [15:0] a_ext;
    logic signed [15:0] ax2;
    logic signed [15:0] sum_ab, sum_cd, sum_total;

    assign b_ext = { b[7], b, 1'b0 };
    assign a_ext = { {8{a[7]}}, a };
    assign ax2   = a_ext <<< 1;

    // 4 Booth digits
    function automatic logic signed [15:0] booth_pp
        (input logic [2:0] d, input logic signed [15:0] a1x, input logic signed [15:0] a2x);
        unique case (d)
            3'b000, 3'b111: booth_pp = 16'sd0;
            3'b001, 3'b010: booth_pp =  a1x;
            3'b011:         booth_pp =  a2x;
            3'b100:         booth_pp = -a2x;
            3'b101, 3'b110: booth_pp = -a1x;
            default:        booth_pp = 16'sd0;
        endcase
    endfunction

    always_comb begin
        pp[0] = booth_pp(b_ext[2:0], a_ext, ax2);
        pp[1] = booth_pp(b_ext[4:2], a_ext, ax2) <<< 2;
        pp[2] = booth_pp(b_ext[6:4], a_ext, ax2) <<< 4;
        pp[3] = booth_pp(b_ext[8:6], a_ext, ax2) <<< 6;
        sum_ab    = pp[0] + pp[1];
        sum_cd    = pp[2] + pp[3];
        sum_total = sum_ab + sum_cd;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
            valid   <= 1'b0;
        end else begin
            valid <= en;
            if (en) acc_out <= acc_in + {{16{sum_total[15]}}, sum_total};
        end
    end
endmodule : cnn_mac_int8_booth4
