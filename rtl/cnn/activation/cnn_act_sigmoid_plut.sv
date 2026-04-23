//==============================================================================
// cnn_act_sigmoid_plut.sv
// Sigmoid via piece-wise linear LUT (8 segments, symmetric around 0).
// Q8.8 fixed-point input/output. Uses a dedicated segment decoder — different
// from the PLA-like structure used by tanh.
//==============================================================================
module cnn_act_sigmoid_plut (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [15:0]  x,      // Q8.8
    output logic        [15:0]  y,      // Q1.15 unsigned (range 0..1)
    output logic                valid
);
    // Break abs(x) into 8 segments covering 0..5 in Q8.8 steps
    logic signed [15:0] ax;
    logic        [2:0]  seg;
    logic signed [15:0] slope [0:7];
    logic        [15:0] inter [0:7];

    assign ax = (x[15]) ? -x : x;

    initial begin
        // Rough first-order coefficients fitting sigmoid
        slope[0] = 16'sd64;  inter[0] = 16'h8000;  // ~0.25·Δ + 0.5
        slope[1] = 16'sd56;  inter[1] = 16'h8200;
        slope[2] = 16'sd42;  inter[2] = 16'h8C00;
        slope[3] = 16'sd28;  inter[3] = 16'h9A00;
        slope[4] = 16'sd16;  inter[4] = 16'hA800;
        slope[5] = 16'sd8;   inter[5] = 16'hB800;
        slope[6] = 16'sd4;   inter[6] = 16'hC800;
        slope[7] = 16'sd1;   inter[7] = 16'hE000;
    end

    always_comb begin
        case (ax[15:12])
            4'h0:       seg = 3'd0;
            4'h1:       seg = 3'd1;
            4'h2:       seg = 3'd2;
            4'h3:       seg = 3'd3;
            4'h4:       seg = 3'd4;
            4'h5,4'h6:  seg = 3'd5;
            4'h7,4'h8:  seg = 3'd6;
            default:    seg = 3'd7;
        endcase
    end

    logic [31:0] prod;
    logic [15:0] y_pos, y_neg;
    assign prod  = $signed(ax) * $signed(slope[seg]);
    assign y_pos = inter[seg] + prod[23:8];
    assign y_neg = 16'hFFFF - y_pos;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) y <= (x[15]) ? y_neg : y_pos;
        end
    end
endmodule : cnn_act_sigmoid_plut
