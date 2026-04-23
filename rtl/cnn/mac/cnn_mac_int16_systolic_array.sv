//==============================================================================
// cnn_mac_int16_systolic_array.sv
// 8×8 weight-stationary systolic array of cnn_mac_int16_systolic_cell,
// flushes partial sums to the south edge. Lots of unique wires per row/col.
//==============================================================================
module cnn_mac_int16_systolic_array #(parameter int unsigned R = 8,
                                      parameter int unsigned C = 8) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         load_w,
    input  logic signed [15:0]           w_flat [0:R*C-1],
    input  logic signed [15:0]           a_west [0:R-1],
    input  logic signed [47:0]           ps_north [0:C-1],
    output logic signed [15:0]           a_east [0:R-1],
    output logic signed [47:0]           ps_south [0:C-1]
);
    logic signed [15:0] a_h [0:R-1][0:C];   // horizontal activation grid (C+1)
    logic signed [47:0] p_v [0:R][0:C-1];   // vertical partial-sum grid (R+1)

    genvar r, c;
    generate
        for (r = 0; r < R; r++) begin : g_row
            assign a_h[r][0] = a_west[r];
            assign a_east[r] = a_h[r][C];
        end
        for (c = 0; c < C; c++) begin : g_col
            assign p_v[0][c]    = ps_north[c];
            assign ps_south[c]  = p_v[R][c];
        end
        for (r = 0; r < R; r++) begin : g_r
            for (c = 0; c < C; c++) begin : g_c
                cnn_mac_int16_systolic_cell u_cell (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .load_w (load_w),
                    .w_in   (w_flat[r*C + c]),
                    .a_in   (a_h[r][c]),
                    .ps_in  (p_v[r][c]),
                    .a_out  (a_h[r][c+1]),
                    .ps_out (p_v[r+1][c])
                );
            end
        end
    endgenerate
endmodule : cnn_mac_int16_systolic_array
