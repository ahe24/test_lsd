//==============================================================================
// sha3_round.sv  -  One Keccak-f round
//==============================================================================
module sha3_round (
    input  logic [4:0]  round_idx,
    input  logic [63:0] state_in  [0:24],
    output logic [63:0] state_out [0:24]
);
    logic [63:0] s_theta [0:24];
    logic [63:0] s_rp    [0:24];
    logic [63:0] s_chi   [0:24];

    sha3_theta  u_theta (.state_in(state_in),  .state_out(s_theta));
    sha3_rho_pi u_rhopi (.state_in(s_theta),   .state_out(s_rp));
    sha3_chi    u_chi   (.state_in(s_rp),      .state_out(s_chi));
    sha3_iota   u_iota  (.round_idx(round_idx),.state_in(s_chi), .state_out(state_out));
endmodule : sha3_round
