//==============================================================================
// cnn_act_mish_approx.sv
// Mish(x) ≈ x * tanh( softplus(x) ).  softplus(x) is approximated with a
// piecewise linear (5 segments) in Q4.12.
//==============================================================================
module cnn_act_mish_approx (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [15:0]  x,     // Q4.12
    output logic signed [15:0]  y,     // Q4.12
    output logic                valid
);
    logic signed [15:0] sp;
    always_comb begin
        if      (x < -16'sd8192)  sp = 16'sd0;
        else if (x < -16'sd4096)  sp = ((x + 16'sd8192) >>> 3);
        else if (x <  16'sd0)     sp = (16'sd512 + ((x + 16'sd4096) >>> 2));
        else if (x <  16'sd4096)  sp = (x + 16'sd2048 - (x >>> 3));
        else                      sp = x; // softplus ~= x for large x
    end

    // tanh(sp) via PWL same as gelu style
    logic signed [15:0] asp, tpos, tval;
    assign asp = sp[15] ? -sp : sp;
    always_comb begin
        if      (asp > 16'sd8192) tpos = 16'sd4095;
        else if (asp > 16'sd4096) tpos = 16'sd3686 + ((asp - 16'sd4096) >>> 3);
        else if (asp > 16'sd2048) tpos = 16'sd3072 + ((asp - 16'sd2048) >>> 2);
        else                      tpos = asp - (asp >>> 3);
    end
    assign tval = sp[15] ? -tpos : tpos;

    logic signed [31:0] prod;
    assign prod = $signed(x) * $signed(tval);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) y <= prod[27:12];
        end
    end
endmodule : cnn_act_mish_approx
