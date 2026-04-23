//==============================================================================
// ldpc_decoder_648.sv
// Iterative LDPC decoder for a rate-5/6 (648,540) code.
// 324 check nodes of degree 8 and 648 variable nodes of degree 4. Both banks
// fully unrolled — each node is its own instance, so elaboration sees a
// massive flat hierarchy on top of the top-level decoder FSM.
//==============================================================================
module ldpc_decoder_648 #(parameter int ITER = 8) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 start,
    input  logic signed [7:0]    ch_llr [0:647],
    output logic                 out_bit [0:539],
    output logic                 done
);
    localparam int NV = 648;
    localparam int NC = 324;
    localparam int DV = 4;
    localparam int DC = 8;

    // Two message banks that we ping-pong each half iteration.
    logic signed [7:0]  msg_c2v [0:NC-1][0:DC-1];
    logic signed [7:0]  msg_v2c [0:NV-1][0:DV-1];

    // Flat connectivity: edge e connects v-node (e%NV) slot (e%DV) to c-node
    // ((e/DV) % NC) slot (e % DC). This is a synthetic mapping which happens
    // to produce a regular bipartite graph — correctness for a *real* code
    // requires a proper H matrix, but for simulator-stress this is sufficient.
    function automatic int v_of_edge (input int e);
        return (e * 13 + 17) % NV;
    endfunction
    function automatic int c_of_edge (input int e);
        return (e * 7 + 3) % NC;
    endfunction
    function automatic int vslot_of_edge (input int e);
        return e % DV;
    endfunction
    function automatic int cslot_of_edge (input int e);
        return (e / DV) % DC;
    endfunction

    localparam int NE = NV * DV; // = 2592

    typedef enum logic [2:0] {S_IDLE, S_INIT, S_C2V, S_V2C, S_DONE} st_e;
    st_e st;
    int   iter;

    // Static glue wires
    logic signed [7:0] c_in  [0:NC-1][0:DC-1];
    logic signed [7:0] c_out [0:NC-1][0:DC-1];
    logic              c_en;
    logic              c_v   [0:NC-1];

    logic signed [7:0]  v_ch   [0:NV-1];
    logic signed [7:0]  v_in   [0:NV-1][0:DV-1];
    logic signed [7:0]  v_out  [0:NV-1][0:DV-1];
    logic signed [10:0] v_post [0:NV-1];
    logic               v_en;
    logic               v_v    [0:NV-1];

    genvar cn;
    generate
        for (cn = 0; cn < NC; cn++) begin : g_cn
            ldpc_cnode_minsum #(.DEG(DC), .W(8)) u_cn (
                .clk(clk), .rst_n(rst_n), .en(c_en),
                .in_llr(c_in[cn]), .out_llr(c_out[cn]), .valid(c_v[cn])
            );
        end
    endgenerate

    genvar vn;
    generate
        for (vn = 0; vn < NV; vn++) begin : g_vn
            ldpc_vnode #(.DEG(DV), .W(8)) u_vn (
                .clk(clk), .rst_n(rst_n), .en(v_en),
                .ch_llr(v_ch[vn]), .in_llr(v_in[vn]),
                .out_llr(v_out[vn]), .post_llr(v_post[vn]),
                .valid(v_v[vn])
            );
        end
    endgenerate

    // Route v->c messages into c-node inputs and c->v messages into v-node inputs
    always_comb begin
        for (int cc = 0; cc < NC; cc++)
            for (int ss = 0; ss < DC; ss++)
                c_in[cc][ss] = 8'sh0;
        for (int vv = 0; vv < NV; vv++)
            for (int ss = 0; ss < DV; ss++)
                v_in[vv][ss] = 8'sh0;

        for (int e = 0; e < NE; e++) begin
            automatic int v_i = v_of_edge(e);
            automatic int c_i = c_of_edge(e);
            automatic int v_s = vslot_of_edge(e);
            automatic int c_s = cslot_of_edge(e);
            c_in[c_i][c_s] = msg_v2c[v_i][v_s];
            v_in[v_i][v_s] = msg_c2v[c_i][c_s];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; iter <= 0;
            c_en <= 0; v_en <= 0;
            done <= 1'b0;
            for (int k = 0; k < NV; k++) v_ch[k] <= '0;
            for (int k = 0; k < NV; k++) for (int s = 0; s < DV; s++) msg_v2c[k][s] <= '0;
            for (int k = 0; k < NC; k++) for (int s = 0; s < DC; s++) msg_c2v[k][s] <= '0;
            for (int k = 0; k < 540; k++) out_bit[k] <= 1'b0;
        end else begin
            c_en <= 0; v_en <= 0; done <= 0;
            unique case (st)
                S_IDLE: if (start) begin
                    for (int k = 0; k < NV; k++) v_ch[k] <= ch_llr[k];
                    // initialise v->c messages to channel LLRs
                    for (int k = 0; k < NV; k++)
                        for (int s = 0; s < DV; s++)
                            msg_v2c[k][s] <= ch_llr[k];
                    iter <= 0;
                    st   <= S_C2V;
                end
                S_C2V: begin
                    c_en <= 1'b1;
                    for (int cc = 0; cc < NC; cc++)
                        for (int ss = 0; ss < DC; ss++)
                            msg_c2v[cc][ss] <= c_out[cc][ss];
                    st <= S_V2C;
                end
                S_V2C: begin
                    v_en <= 1'b1;
                    for (int vv = 0; vv < NV; vv++)
                        for (int ss = 0; ss < DV; ss++)
                            msg_v2c[vv][ss] <= v_out[vv][ss];
                    iter <= iter + 1;
                    if (iter + 1 == ITER) st <= S_DONE;
                    else                  st <= S_C2V;
                end
                S_DONE: begin
                    for (int k = 0; k < 540; k++) out_bit[k] <= v_post[k][10];
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : ldpc_decoder_648
