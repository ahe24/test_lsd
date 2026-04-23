//==============================================================================
// cnn_act_tanh_cordic.sv
// tanh(x) via hyperbolic CORDIC. 10-stage fully unrolled pipeline.
// Each stage is a structurally distinct always_ff block so the elaborator sees
// 10 unique sub-stages rather than a generated loop.
//==============================================================================
module cnn_act_tanh_cordic (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [15:0]  x,      // Q3.13
    output logic signed [15:0]  y,      // Q1.15
    output logic                valid
);
    // Hyperbolic CORDIC: sinh, cosh, angle
    // arctanh(2^-i) table in Q2.14
    localparam logic signed [15:0] K_GAIN = 16'sd19896; // 1/0.80694 ≈ 1.2393 in Q2.14 → 19896

    logic signed [16:0] s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10;
    logic signed [16:0] c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10;
    logic signed [16:0] z0, z1, z2, z3, z4, z5, z6, z7, z8, z9, z10;
    logic        [10:0] v;

    // Atanh(2^-i) Q2.14 values for i=1..10
    localparam logic signed [15:0] ATH1  = 16'sd9001;
    localparam logic signed [15:0] ATH2  = 16'sd4115;
    localparam logic signed [15:0] ATH3  = 16'sd2037;
    localparam logic signed [15:0] ATH4  = 16'sd1017;
    localparam logic signed [15:0] ATH5  = 16'sd508;
    localparam logic signed [15:0] ATH6  = 16'sd254;
    localparam logic signed [15:0] ATH7  = 16'sd127;
    localparam logic signed [15:0] ATH8  = 16'sd63;
    localparam logic signed [15:0] ATH9  = 16'sd31;
    localparam logic signed [15:0] ATH10 = 16'sd15;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v  <= '0;
            s0 <= '0; c0 <= '0; z0 <= '0;
            s1 <= '0; c1 <= '0; z1 <= '0;
            s2 <= '0; c2 <= '0; z2 <= '0;
            s3 <= '0; c3 <= '0; z3 <= '0;
            s4 <= '0; c4 <= '0; z4 <= '0;
            s5 <= '0; c5 <= '0; z5 <= '0;
            s6 <= '0; c6 <= '0; z6 <= '0;
            s7 <= '0; c7 <= '0; z7 <= '0;
            s8 <= '0; c8 <= '0; z8 <= '0;
            s9 <= '0; c9 <= '0; z9 <= '0;
            s10 <= '0; c10 <= '0; z10 <= '0;
        end else begin
            v <= { v[9:0], en };
            // Initial stage
            s0 <= 17'sd0;
            c0 <= 17'sd16384; // 1.0 in Q2.14
            z0 <= {x[15], x};
            // i=1
            if (z1[16])  begin s1 <= s0 - (c0 >>> 1); c1 <= c0 - (s0 >>> 1); z1 <= z0 + ATH1; end
            else         begin s1 <= s0 + (c0 >>> 1); c1 <= c0 + (s0 >>> 1); z1 <= z0 - ATH1; end
            // i=2
            if (z1[16])  begin s2 <= s1 - (c1 >>> 2); c2 <= c1 - (s1 >>> 2); z2 <= z1 + ATH2; end
            else         begin s2 <= s1 + (c1 >>> 2); c2 <= c1 + (s1 >>> 2); z2 <= z1 - ATH2; end
            // i=3
            if (z2[16])  begin s3 <= s2 - (c2 >>> 3); c3 <= c2 - (s2 >>> 3); z3 <= z2 + ATH3; end
            else         begin s3 <= s2 + (c2 >>> 3); c3 <= c2 + (s2 >>> 3); z3 <= z2 - ATH3; end
            // i=4
            if (z3[16])  begin s4 <= s3 - (c3 >>> 4); c4 <= c3 - (s3 >>> 4); z4 <= z3 + ATH4; end
            else         begin s4 <= s3 + (c3 >>> 4); c4 <= c3 + (s3 >>> 4); z4 <= z3 - ATH4; end
            // i=5
            if (z4[16])  begin s5 <= s4 - (c4 >>> 5); c5 <= c4 - (s4 >>> 5); z5 <= z4 + ATH5; end
            else         begin s5 <= s4 + (c4 >>> 5); c5 <= c4 + (s4 >>> 5); z5 <= z4 - ATH5; end
            // i=6
            if (z5[16])  begin s6 <= s5 - (c5 >>> 6); c6 <= c5 - (s5 >>> 6); z6 <= z5 + ATH6; end
            else         begin s6 <= s5 + (c5 >>> 6); c6 <= c5 + (s5 >>> 6); z6 <= z5 - ATH6; end
            // i=7
            if (z6[16])  begin s7 <= s6 - (c6 >>> 7); c7 <= c6 - (s6 >>> 7); z7 <= z6 + ATH7; end
            else         begin s7 <= s6 + (c6 >>> 7); c7 <= c6 + (s6 >>> 7); z7 <= z6 - ATH7; end
            // i=8
            if (z7[16])  begin s8 <= s7 - (c7 >>> 8); c8 <= c7 - (s7 >>> 8); z8 <= z7 + ATH8; end
            else         begin s8 <= s7 + (c7 >>> 8); c8 <= c7 + (s7 >>> 8); z8 <= z7 - ATH8; end
            // i=9
            if (z8[16])  begin s9 <= s8 - (c8 >>> 9); c9 <= c8 - (s8 >>> 9); z9 <= z8 + ATH9; end
            else         begin s9 <= s8 + (c8 >>> 9); c9 <= c8 + (s8 >>> 9); z9 <= z8 - ATH9; end
            // i=10
            if (z9[16])  begin s10 <= s9 - (c9 >>> 10); c10 <= c9 - (s9 >>> 10); z10 <= z9 + ATH10; end
            else         begin s10 <= s9 + (c9 >>> 10); c10 <= c9 + (s9 >>> 10); z10 <= z9 - ATH10; end
        end
    end

    // Apply CORDIC gain then tanh = sinh / cosh via approximation (s * 1/c)
    logic signed [33:0] num;
    logic signed [33:0] den;
    logic signed [17:0] tanh_q;

    assign num = $signed(s10) * $signed(K_GAIN);
    assign den = $signed(c10) * $signed(K_GAIN);
    always_comb begin
        if (den == 0) tanh_q = '0;
        else          tanh_q = num[33:16] / den[33:16]; // crude truncating divide
    end

    assign valid = v[10];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      y <= '0;
        else if (v[9])   y <= tanh_q[15:0];
    end
endmodule : cnn_act_tanh_cordic
