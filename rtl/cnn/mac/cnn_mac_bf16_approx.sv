//==============================================================================
// cnn_mac_bf16_approx.sv
// bfloat16 MAC with truncating mantissa multiplier (common in ML accelerators).
// Exponent handled with simple saturating arithmetic — distinct from the
// fully-rounded fp32 variant.
//==============================================================================
module cnn_mac_bf16_approx (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         en,
    input  logic [15:0]  a,
    input  logic [15:0]  b,
    input  logic [31:0]  acc_in,
    output logic [31:0]  acc_out,
    output logic         valid
);
    logic        sa, sb;
    logic [7:0]  ea, eb;
    logic [7:0]  ma, mb; // 8-bit significand incl. implicit 1
    assign sa = a[15]; assign ea = a[14:7]; assign ma = {|a[14:7], a[6:0]};
    assign sb = b[15]; assign eb = b[14:7]; assign mb = {|b[14:7], b[6:0]};

    logic        sab;
    logic [15:0] mab;
    logic [8:0]  eab;
    assign sab = sa ^ sb;
    assign mab = ma * mb;
    assign eab = ea + eb - 9'd127;

    logic [7:0]  mab_top;       // truncated top byte
    logic [8:0]  eab_n;
    always_comb begin
        if (mab[15]) begin
            mab_top = mab[14:7];
            eab_n   = eab + 9'd1;
        end else begin
            mab_top = mab[13:6];
            eab_n   = eab;
        end
    end

    // Convert product to fp32 internal, then add to fp32 accumulator
    logic [31:0] prod_fp32;
    assign prod_fp32 = (mab == 0) ? {sab, 31'h0}
                     : {sab, eab_n[7:0], mab_top, 15'h0};

    // fp32 add (simplified): align, add, normalise, truncate
    logic        s_acc, s_prd;
    logic [7:0]  e_acc, e_prd;
    logic [23:0] m_acc, m_prd;
    assign s_acc = acc_in[31]; assign e_acc = acc_in[30:23]; assign m_acc = {|acc_in[30:23], acc_in[22:0]};
    assign s_prd = prod_fp32[31]; assign e_prd = prod_fp32[30:23]; assign m_prd = {|prod_fp32[30:23], prod_fp32[22:0]};

    logic [7:0]  e_big;
    logic [24:0] m_big, m_sm;
    logic [7:0]  sh;
    logic        s_big, s_sm;
    always_comb begin
        if (e_acc >= e_prd) begin
            e_big = e_acc; m_big = {1'b0, m_acc}; s_big = s_acc;
            m_sm  = {1'b0, m_prd} >> (e_acc - e_prd);
            s_sm  = s_prd;
            sh    = e_acc - e_prd;
        end else begin
            e_big = e_prd; m_big = {1'b0, m_prd}; s_big = s_prd;
            m_sm  = {1'b0, m_acc} >> (e_prd - e_acc);
            s_sm  = s_acc;
            sh    = e_prd - e_acc;
        end
    end

    logic [25:0] m_r;
    logic        s_r;
    always_comb begin
        if (s_big == s_sm) begin
            m_r = {1'b0, m_big} + {1'b0, m_sm};
            s_r = s_big;
        end else if (m_big >= m_sm) begin
            m_r = {1'b0, m_big} - {1'b0, m_sm};
            s_r = s_big;
        end else begin
            m_r = {1'b0, m_sm} - {1'b0, m_big};
            s_r = s_sm;
        end
    end

    logic [7:0] e_n;
    logic [23:0] m_n;
    always_comb begin
        if (m_r[24]) begin
            m_n = m_r[24:1];
            e_n = e_big + 8'd1;
        end else begin
            // simple leading-zero shifting up to 8 positions
            m_n = m_r[23:0];
            e_n = e_big;
            for (int i = 0; i < 8; i++) begin
                if (!m_n[23] && e_n != 0) begin
                    m_n = m_n << 1;
                    e_n = e_n - 8'd1;
                end
            end
        end
    end

    logic [31:0] acc_nxt;
    assign acc_nxt = (m_r == 0) ? 32'h0 : {s_r, e_n, m_n[22:0]};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
            valid   <= 1'b0;
        end else begin
            valid <= en;
            if (en) acc_out <= acc_nxt;
        end
    end
endmodule : cnn_mac_bf16_approx
