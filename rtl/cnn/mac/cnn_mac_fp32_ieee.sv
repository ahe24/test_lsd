//==============================================================================
// cnn_mac_fp32_ieee.sv
// Single-precision (binary32) fused multiply-add. Does rounding-to-nearest-even
// on the final result only. Not fully IEEE compliant for NaN/Inf propagation
// (kept intentionally "good enough" to exercise simulator arithmetic and to be
// distinct from the bfloat16 variant).
//==============================================================================
module cnn_mac_fp32_ieee (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         en,
    input  logic [31:0]  a,
    input  logic [31:0]  b,
    input  logic [31:0]  c,
    output logic [31:0]  y,
    output logic         valid
);
    // ---- Unpack operands
    logic        sa, sb, sc;
    logic [7:0]  ea, eb, ec;
    logic [23:0] ma, mb, mc;
    logic        za, zb, zc;

    assign sa = a[31]; assign ea = a[30:23]; assign ma = {|a[30:23], a[22:0]};
    assign sb = b[31]; assign eb = b[30:23]; assign mb = {|b[30:23], b[22:0]};
    assign sc = c[31]; assign ec = c[30:23]; assign mc = {|c[30:23], c[22:0]};
    assign za = (ea == 8'd0);
    assign zb = (eb == 8'd0);
    assign zc = (ec == 8'd0);

    // ---- Multiply a*b
    logic [47:0] mab;
    logic [9:0]  eab;      // biased exponent sum before normalisation
    logic        sab;

    assign sab = sa ^ sb;
    assign mab = za|zb ? 48'h0 : ma * mb;
    assign eab = ea + eb - 10'd127;

    // Normalise multiplication result
    logic [47:0] mab_n;
    logic [9:0]  eab_n;
    always_comb begin
        if (mab[47]) begin
            mab_n = mab;
            eab_n = eab + 10'd1;
        end else begin
            mab_n = mab <<< 1;
            eab_n = eab;
        end
    end

    // ---- Align addend c to mab_n
    logic [9:0]  exp_diff;
    logic [71:0] m_add;
    logic [71:0] m_prod;
    logic        s_add, s_prod;

    assign s_prod = sab;
    assign s_add  = sc;
    assign m_prod = {24'h0, mab_n}; // 72 bits

    always_comb begin
        if (zc) begin
            m_add = '0;
            exp_diff = '0;
        end else if (eab_n >= {2'b0, ec}) begin
            exp_diff = eab_n - {2'b0, ec};
            m_add    = {mc, 48'h0} >> (exp_diff > 10'd72 ? 10'd72 : exp_diff);
        end else begin
            exp_diff = {2'b0, ec} - eab_n;
            m_add    = {mc, 48'h0};
        end
    end

    logic        big_prod;
    logic [9:0]  e_big;
    assign big_prod = (eab_n >= {2'b0, ec});
    assign e_big    = big_prod ? eab_n : {2'b0, ec};

    // Add or subtract
    logic [72:0] m_sum;
    logic        s_res;
    always_comb begin
        if (s_prod == s_add) begin
            m_sum = big_prod ? (m_prod + m_add) : (m_add + m_prod);
            s_res = s_prod;
        end else begin
            if (big_prod) begin
                m_sum = (m_prod >= m_add) ? (m_prod - m_add) : (m_add - m_prod);
                s_res = (m_prod >= m_add) ? s_prod : s_add;
            end else begin
                m_sum = (m_add >= m_prod) ? (m_add - m_prod) : (m_prod - m_add);
                s_res = (m_add >= m_prod) ? s_add : s_prod;
            end
        end
    end

    // Normalise & round
    logic [9:0]  e_norm;
    logic [72:0] m_norm;
    logic [6:0]  lz;
    always_comb begin
        m_norm = m_sum;
        e_norm = e_big;
        lz     = '0;
        if (m_norm != '0) begin
            // left-shift until bit 48 is set
            for (int i = 0; i < 72; i++) begin
                if (!m_norm[48]) begin
                    m_norm = m_norm << 1;
                    lz     = lz + 7'd1;
                end
            end
            e_norm = e_big - {3'b0, lz};
        end
    end

    logic [22:0] frac_r;
    logic        round_bit, sticky;
    always_comb begin
        frac_r    = m_norm[47:25];
        round_bit = m_norm[24];
        sticky    = |m_norm[23:0];
    end

    logic [23:0] frac_rnd;
    logic [9:0]  e_rnd;
    always_comb begin
        frac_rnd = {1'b0, frac_r} + ((round_bit & (sticky | frac_r[0])) ? 24'd1 : 24'd0);
        if (frac_rnd[23]) e_rnd = e_norm + 10'd1;
        else              e_rnd = e_norm;
    end

    logic [31:0] y_nxt;
    always_comb begin
        if (m_sum == '0)              y_nxt = {s_res, 31'h0};
        else if ($signed(e_rnd) <= 0) y_nxt = {s_res, 31'h0};
        else if (e_rnd >= 10'd255)    y_nxt = {s_res, 8'hFF, 23'h0};
        else                          y_nxt = {s_res, e_rnd[7:0], frac_rnd[22:0]};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (en) y <= y_nxt;
        end
    end
endmodule : cnn_mac_fp32_ieee
