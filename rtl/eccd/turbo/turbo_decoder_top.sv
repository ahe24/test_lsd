//==============================================================================
// turbo_decoder_top.sv
// Iterative turbo decoder: alternates two SISO decoders with an interleaver.
// 8 global iterations. Uses two concrete turbo_siso_decoder instances.
//==============================================================================
module turbo_decoder_top #(parameter int K = 1024,
                           parameter int ITER = 8) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 start,
    input  logic signed [7:0]    sys_llr [0:K-1],
    input  logic signed [7:0]    par1_llr[0:K-1],
    input  logic signed [7:0]    par2_llr[0:K-1],
    output logic                 out_bit [0:K-1],
    output logic                 done
);
    // Interleaver lookup array
    logic [$clog2(K)-1:0] pi [0:K-1];
    genvar i;
    generate
        for (i = 0; i < K; i++) begin : g_pi
            turbo_interleaver #(.K(K)) u_pi (.i(i[$clog2(K)-1:0]), .pi(pi[i]));
        end
    endgenerate

    // Storage for extrinsic info
    logic signed [7:0] ext_a [0:K-1];
    logic signed [7:0] ext_b [0:K-1];

    logic                siso1_start, siso1_done;
    logic signed [9:0]   siso1_ext [0:K-1];
    logic signed [7:0]   siso1_ap  [0:K-1];
    turbo_siso_decoder #(.K(K)) u_s1 (
        .clk(clk), .rst_n(rst_n), .start(siso1_start),
        .sys_llr(sys_llr), .par_llr(par1_llr), .a_priori(siso1_ap),
        .ext_llr(siso1_ext), .done(siso1_done)
    );

    logic                siso2_start, siso2_done;
    logic signed [9:0]   siso2_ext [0:K-1];
    logic signed [7:0]   siso2_ap  [0:K-1];
    logic signed [7:0]   sys_int   [0:K-1];
    turbo_siso_decoder #(.K(K)) u_s2 (
        .clk(clk), .rst_n(rst_n), .start(siso2_start),
        .sys_llr(sys_int), .par_llr(par2_llr), .a_priori(siso2_ap),
        .ext_llr(siso2_ext), .done(siso2_done)
    );

    typedef enum logic [2:0] {S_IDLE, S_R1, S_W1, S_R2, S_W2, S_NEXT, S_DONE} st_e;
    st_e st;
    int  it;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; it <= 0;
            siso1_start <= 0; siso2_start <= 0; done <= 0;
            for (int k = 0; k < K; k++) begin
                ext_a[k] <= '0; ext_b[k] <= '0;
                siso1_ap[k] <= '0; siso2_ap[k] <= '0;
                sys_int[k] <= '0; out_bit[k] <= 1'b0;
            end
        end else begin
            siso1_start <= 0; siso2_start <= 0; done <= 0;
            unique case (st)
                S_IDLE: if (start) begin
                    for (int k = 0; k < K; k++) begin
                        ext_a[k] <= '0; ext_b[k] <= '0;
                        siso1_ap[k] <= '0;
                    end
                    it <= 0;
                    st <= S_R1;
                end
                S_R1: begin
                    for (int k = 0; k < K; k++) siso1_ap[k] <= ext_b[k];
                    siso1_start <= 1'b1;
                    st <= S_W1;
                end
                S_W1: if (siso1_done) begin
                    for (int k = 0; k < K; k++) ext_a[k] <= siso1_ext[k][7:0];
                    // Interleave sys_llr and ext_a into siso2 inputs
                    for (int k = 0; k < K; k++) begin
                        sys_int[k]    <= sys_llr[pi[k]];
                        siso2_ap[k]   <= siso1_ext[pi[k]][7:0];
                    end
                    st <= S_R2;
                end
                S_R2: begin
                    siso2_start <= 1'b1;
                    st <= S_W2;
                end
                S_W2: if (siso2_done) begin
                    for (int k = 0; k < K; k++) ext_b[pi[k]] <= siso2_ext[k][7:0];
                    it <= it + 1;
                    if (it + 1 == ITER) st <= S_DONE;
                    else                st <= S_R1;
                end
                S_DONE: begin
                    for (int k = 0; k < K; k++)
                        out_bit[k] <= ext_a[k][7]; // sign of posterior
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : turbo_decoder_top
