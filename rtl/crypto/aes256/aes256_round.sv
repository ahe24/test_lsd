//==============================================================================
// aes256_round.sv
// A single AES round = SubBytes → ShiftRows → MixColumns → AddRoundKey
// (MixColumns optional — bypassed for the final round via is_final).
//==============================================================================
module aes256_round (
    input  logic [127:0]  state_in,
    input  logic [127:0]  rk,
    input  logic          is_final,
    output logic [127:0]  state_out
);
    logic [127:0] s_sub, s_shift, s_mix;

    aes_subbytes   u_sb  (.state_in(state_in), .state_out(s_sub));
    aes_shiftrows  u_sr  (.state_in(s_sub),    .state_out(s_shift));
    aes_mixcolumns u_mc  (.state_in(s_shift),  .state_out(s_mix));

    assign state_out = (is_final ? s_shift : s_mix) ^ rk;
endmodule : aes256_round
