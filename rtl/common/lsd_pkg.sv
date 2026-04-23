//==============================================================================
// lsd_pkg.sv
// Massive-Scale Verilog Design: project-wide parameters and types
//==============================================================================
`ifndef LSD_PKG_SV
`define LSD_PKG_SV

package lsd_pkg;

    // ---------------------------------------------------------------- Globals
    parameter int unsigned LSD_DATA_W       = 64;
    parameter int unsigned LSD_ADDR_W       = 32;
    parameter int unsigned LSD_ID_W         = 8;
    parameter int unsigned LSD_LEN_W        = 16;
    parameter int unsigned LSD_TAG_W        = 12;

    // CNN
    parameter int unsigned CNN_MAC_LANES    = 64;
    parameter int unsigned CNN_ACC_W        = 48;
    parameter int unsigned CNN_INT_W        = 16;
    parameter int unsigned CNN_FP_W         = 32;
    parameter int unsigned CNN_TILE_ROWS    = 16;
    parameter int unsigned CNN_TILE_COLS    = 16;

    // Crypto
    parameter int unsigned CR_AES_KEY_W     = 256;
    parameter int unsigned CR_AES_BLK_W     = 128;
    parameter int unsigned CR_SHA3_STATE_W  = 1600;
    parameter int unsigned CR_SHA3_LANE_W   = 64;
    parameter int unsigned CR_RSA_W         = 4096;
    parameter int unsigned CR_ECC_FIELD_W   = 256;

    // Graphics
    parameter int unsigned GFX_VTX_COORD_W  = 32;
    parameter int unsigned GFX_PIX_COMP_W   = 10;
    parameter int unsigned GFX_TILE_W       = 16;
    parameter int unsigned GFX_TILE_H       = 16;

    // Complex ALU
    parameter int unsigned CA_FP_W          = 32;
    parameter int unsigned CA_FFT_PTS       = 1024;
    parameter int unsigned CA_MAT_N         = 8;

    // ECC codecs
    parameter int unsigned ECC_LDPC_N       = 648;
    parameter int unsigned ECC_LDPC_K       = 540;
    parameter int unsigned ECC_TURBO_K      = 1024;
    parameter int unsigned ECC_TURBO_ITER   = 8;

    // ---------------------------------------------------------------- Types
    typedef logic [LSD_ADDR_W-1:0]  addr_t;
    typedef logic [LSD_DATA_W-1:0]  data_t;
    typedef logic [LSD_ID_W-1:0]    id_t;
    typedef logic [LSD_LEN_W-1:0]   len_t;
    typedef logic [LSD_TAG_W-1:0]   tag_t;

    // Subsystem enumeration for interconnect tagging
    typedef enum logic [2:0] {
        SUB_CNN    = 3'd0,
        SUB_CRYPTO = 3'd1,
        SUB_GFX    = 3'd2,
        SUB_CALU   = 3'd3,
        SUB_ECCD   = 3'd4,
        SUB_DBG    = 3'd5
    } sub_e;

    typedef enum logic [2:0] {
        OP_NOP   = 3'd0,
        OP_READ  = 3'd1,
        OP_WRITE = 3'd2,
        OP_KICK  = 3'd3,
        OP_POLL  = 3'd4,
        OP_RST   = 3'd5
    } op_e;

    typedef struct packed {
        tag_t   tag;
        sub_e   sub;
        op_e    op;
        addr_t  addr;
        data_t  data;
        len_t   len;
    } cmd_t;

    typedef struct packed {
        tag_t   tag;
        sub_e   sub;
        logic   err;
        data_t  data;
    } rsp_t;

    // ---------------------------------------------------------------- Helpers
    function automatic logic [31:0] lsd_crc32_step (input logic [31:0] crc,
                                                    input logic [7:0]  byte_i);
        logic [31:0] c;
        c = crc ^ {24'h0, byte_i};
        for (int i = 0; i < 8; i++) begin
            c = (c[0]) ? (c >> 1) ^ 32'hEDB8_8320 : (c >> 1);
        end
        return c;
    endfunction

    // Galois field multiply for AES (GF(2^8), polynomial 0x11B)
    function automatic logic [7:0] lsd_gf8_mul (input logic [7:0] a,
                                                input logic [7:0] b);
        logic [7:0] p;
        logic [7:0] x;
        logic [7:0] y;
        p = 8'h0;
        x = a;
        y = b;
        for (int i = 0; i < 8; i++) begin
            if (y[0]) p ^= x;
            x = (x[7]) ? ((x << 1) ^ 8'h1B) : (x << 1);
            y = y >> 1;
        end
        return p;
    endfunction

    // Simple LFSR advance (Fibonacci polynomial)
    function automatic logic [31:0] lsd_lfsr32 (input logic [31:0] s);
        logic fb;
        fb = s[31] ^ s[21] ^ s[1] ^ s[0];
        return {s[30:0], fb};
    endfunction

endpackage : lsd_pkg

`endif // LSD_PKG_SV
