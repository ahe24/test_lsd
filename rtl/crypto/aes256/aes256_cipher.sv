//==============================================================================
// aes256_cipher.sv
// Fully unrolled AES-256 encipher (14 rounds + initial AddRoundKey).
// Each round is its own instance so the simulator sees 14 distinct
// datapath hierarchies — good fuel for elaboration load.
//==============================================================================
module aes256_cipher (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          en,
    input  logic [127:0]  plaintext,
    input  logic [255:0]  key,
    output logic [127:0]  ciphertext,
    output logic          valid
);
    logic [127:0] rk [0:14];
    aes_key_expand256 u_ke (.key(key), .rk(rk));

    logic [127:0] st [0:14];
    assign st[0] = plaintext ^ rk[0];

    genvar i;
    generate
        for (i = 1; i < 14; i++) begin : g_rnd
            aes256_round u_rnd (
                .state_in (st[i-1]),
                .rk       (rk[i]),
                .is_final (1'b0),
                .state_out(st[i])
            );
        end
    endgenerate

    aes256_round u_fin (
        .state_in (st[13]),
        .rk       (rk[14]),
        .is_final (1'b1),
        .state_out(st[14])
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ciphertext <= '0;
            valid      <= 1'b0;
        end else begin
            valid <= en;
            if (en) ciphertext <= st[14];
        end
    end
endmodule : aes256_cipher
