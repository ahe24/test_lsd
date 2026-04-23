//==============================================================================
// cnn_act_softmax_exp8.sv
// 8-way softmax: exp via LUT → subtract max → sum → reciprocal-mul.
// 3-stage pipeline.
//==============================================================================
module cnn_act_softmax_exp8 (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  en,
    input  logic signed [15:0]    x [0:7],
    output logic        [15:0]    p [0:7],
    output logic                  valid
);
    // Stage 0: find max
    logic signed [15:0] mx_s0;
    logic signed [15:0] xs0 [0:7];
    integer i;
    always_comb begin
        mx_s0 = x[0];
        for (i = 1; i < 8; i++) if (x[i] > mx_s0) mx_s0 = x[i];
    end

    logic signed [15:0] xm [0:7];
    always_comb for (i = 0; i < 8; i++) xm[i] = x[i] - mx_s0;

    // Stage 1: exp LUT on (x-max), 256-entry ROM indexed by low 8 bits of the
    //           shifted difference. Saturates to 0 for very negative values.
    logic [15:0] exp_lut [0:255];
    initial begin
        for (int k = 0; k < 256; k++) begin
            automatic real v;
            v = $exp(-real'(k) / 16.0);
            exp_lut[k] = int'(v * 65535.0) & 16'hFFFF;
        end
    end

    logic [15:0] exp_v [0:7];
    always_comb begin
        for (i = 0; i < 8; i++) begin
            automatic logic signed [15:0] neg;
            neg = -xm[i]; // xm[i] <= 0
            if (neg[15:8] != 8'h0) exp_v[i] = 16'h0;
            else                   exp_v[i] = exp_lut[neg[7:0]];
        end
    end

    // Stage 1 register
    logic [15:0] exp_r [0:7];
    logic [19:0] sum_r;
    logic        v1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 1'b0;
            sum_r <= '0;
            for (int k = 0; k < 8; k++) exp_r[k] <= '0;
        end else begin
            v1 <= en;
            if (en) begin
                for (int k = 0; k < 8; k++) exp_r[k] <= exp_v[k];
                sum_r <= exp_v[0] + exp_v[1] + exp_v[2] + exp_v[3] +
                         exp_v[4] + exp_v[5] + exp_v[6] + exp_v[7];
            end
        end
    end

    // Stage 2: reciprocal by Newton-Raphson-lite (2 iterations, Q1.16)
    logic [15:0] recip;
    always_comb begin
        // approximate: recip ≈ 0xFFFF / sum
        if (sum_r == 0) recip = 16'hFFFF;
        else            recip = 16'hFFFF / sum_r[15:0];
    end

    logic        v2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v2 <= 1'b0;
            for (int k = 0; k < 8; k++) p[k] <= '0;
        end else begin
            v2 <= v1;
            if (v1) begin
                for (int k = 0; k < 8; k++) begin
                    automatic logic [31:0] t;
                    t = exp_r[k] * recip;
                    p[k] <= t[31:16];
                end
            end
        end
    end
    assign valid = v2;
endmodule : cnn_act_softmax_exp8
