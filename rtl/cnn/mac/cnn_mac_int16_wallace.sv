//==============================================================================
// cnn_mac_int16_wallace.sv
// Signed 16×16 MAC with a 4-level Wallace tree of carry-save adders,
// 48-bit accumulator. Explicit half/full adders so the tree survives
// aggressive optimisation into something still structurally distinct.
//==============================================================================
module cnn_mac_int16_wallace (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [15:0]  a,
    input  logic signed [15:0]  b,
    input  logic signed [47:0]  acc_in,
    output logic signed [47:0]  acc_out,
    output logic                valid
);
    logic signed [31:0] partial [0:15];
    logic signed [31:0] l1 [0:10]; // first reduction layer
    logic signed [31:0] l2 [0:6];
    logic signed [31:0] l3 [0:4];
    logic signed [31:0] l4 [0:3];
    logic signed [31:0] s_out, c_out;
    logic signed [31:0] sum;

    // Generate signed partial products (Baugh-Wooley style via sign-extension)
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi++) begin : g_pp
            always_comb begin
                logic signed [31:0] t;
                t = b[gi] ? { {16{a[15]}}, a } : 32'sd0;
                partial[gi] = t <<< gi;
            end
        end
    endgenerate

    // Manual CSA reduction: 16 → 11 → 7 → 5 → 4 → 2 → 1
    // Layer 1 : 5 CSAs consume 15 of 16, 1 pass-through
    // Each CSA(x,y,z) → (sum, 2*carry)
    function automatic logic signed [31:0] csa_s (input logic signed [31:0] x,
                                                  input logic signed [31:0] y,
                                                  input logic signed [31:0] z);
        return x ^ y ^ z;
    endfunction
    function automatic logic signed [31:0] csa_c (input logic signed [31:0] x,
                                                  input logic signed [31:0] y,
                                                  input logic signed [31:0] z);
        return ((x & y) | (x & z) | (y & z)) <<< 1;
    endfunction

    always_comb begin
        // Layer 1
        l1[0]  = csa_s(partial[0],  partial[1],  partial[2]);
        l1[1]  = csa_c(partial[0],  partial[1],  partial[2]);
        l1[2]  = csa_s(partial[3],  partial[4],  partial[5]);
        l1[3]  = csa_c(partial[3],  partial[4],  partial[5]);
        l1[4]  = csa_s(partial[6],  partial[7],  partial[8]);
        l1[5]  = csa_c(partial[6],  partial[7],  partial[8]);
        l1[6]  = csa_s(partial[9],  partial[10], partial[11]);
        l1[7]  = csa_c(partial[9],  partial[10], partial[11]);
        l1[8]  = csa_s(partial[12], partial[13], partial[14]);
        l1[9]  = csa_c(partial[12], partial[13], partial[14]);
        l1[10] = partial[15];
        // Layer 2
        l2[0] = csa_s(l1[0], l1[1], l1[2]);
        l2[1] = csa_c(l1[0], l1[1], l1[2]);
        l2[2] = csa_s(l1[3], l1[4], l1[5]);
        l2[3] = csa_c(l1[3], l1[4], l1[5]);
        l2[4] = csa_s(l1[6], l1[7], l1[8]);
        l2[5] = csa_c(l1[6], l1[7], l1[8]);
        l2[6] = l1[9] + l1[10];
        // Layer 3
        l3[0] = csa_s(l2[0], l2[1], l2[2]);
        l3[1] = csa_c(l2[0], l2[1], l2[2]);
        l3[2] = csa_s(l2[3], l2[4], l2[5]);
        l3[3] = csa_c(l2[3], l2[4], l2[5]);
        l3[4] = l2[6];
        // Layer 4
        l4[0] = csa_s(l3[0], l3[1], l3[2]);
        l4[1] = csa_c(l3[0], l3[1], l3[2]);
        l4[2] = l3[3];
        l4[3] = l3[4];
        // Final CPA
        s_out = l4[0] + l4[1];
        c_out = l4[2] + l4[3];
        sum   = s_out + c_out;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
            valid   <= 1'b0;
        end else begin
            valid <= en;
            if (en) acc_out <= acc_in + {{16{sum[31]}}, sum};
        end
    end
endmodule : cnn_mac_int16_wallace
