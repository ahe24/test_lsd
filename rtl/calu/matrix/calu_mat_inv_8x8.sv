//==============================================================================
// calu_mat_inv_8x8.sv
// Gauss-Jordan inversion of an 8x8 Q16.16 real matrix. Serial over rows;
// the column elimination within a row is parallel.
// This is deliberately heavy — used to stress the simulator with arithmetic
// dependencies rather than for throughput.
//==============================================================================
module calu_mat_inv_8x8 (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 start,
    input  logic signed [31:0]   A [0:7][0:7],
    output logic signed [31:0]   Ainv [0:7][0:7],
    output logic                 done
);
    typedef enum logic [2:0] {
        S_IDLE, S_LOAD, S_PIVOT, S_NORMALISE, S_ELIM, S_NEXT, S_DONE
    } st_e;
    st_e st;

    logic signed [31:0] M [0:7][0:15]; // augmented [A | I]
    logic [2:0]         row;
    logic signed [31:0] piv, piv_inv;

    // Reciprocal seed LUT (Q16.16)
    logic [31:0] rec_lut [0:255];
    initial begin
        for (int k = 1; k < 256; k++) rec_lut[k] = int'(real'(1 << 16) / real'(k));
        rec_lut[0] = 32'hFFFFFFFF;
    end

    logic [7:0] piv_top;
    assign piv_top = piv[23:16];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st  <= S_IDLE; row <= '0;
            piv <= '0; piv_inv <= '0;
            done <= 1'b0;
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 16; j++)
                    M[i][j] <= '0;
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 8; j++)
                    Ainv[i][j] <= '0;
        end else begin
            done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) st <= S_LOAD;
                S_LOAD: begin
                    for (int i = 0; i < 8; i++)
                        for (int j = 0; j < 8; j++) begin
                            M[i][j]   <= A[i][j];
                            M[i][j+8] <= (i == j) ? 32'sh0001_0000 : 32'sh0;
                        end
                    row <= 0;
                    st  <= S_PIVOT;
                end
                S_PIVOT: begin
                    piv     <= M[row][row];
                    st      <= S_NORMALISE;
                end
                S_NORMALISE: begin
                    // Approximate reciprocal by seed LUT + one NR step
                    automatic logic signed [31:0] seed = $signed(rec_lut[piv_top]);
                    automatic logic signed [63:0] nr   = ($signed(piv) * $signed(seed)) >>> 16;
                    piv_inv <= ($signed(seed) * ($signed(64'sd131072) - nr)) >>> 16;
                    st      <= S_ELIM;
                end
                S_ELIM: begin
                    // Divide pivot row by piv
                    for (int j = 0; j < 16; j++) begin
                        automatic logic signed [63:0] t;
                        t = $signed(M[row][j]) * $signed(piv_inv);
                        M[row][j] <= t >>> 16;
                    end
                    // Subtract scaled pivot row from all others
                    for (int i = 0; i < 8; i++) begin
                        if (i != row) begin
                            automatic logic signed [31:0] fac = M[i][row];
                            for (int j = 0; j < 16; j++) begin
                                automatic logic signed [63:0] t2;
                                t2 = $signed(fac) * $signed(M[row][j]);
                                M[i][j] <= M[i][j] - (t2 >>> 16);
                            end
                        end
                    end
                    st <= S_NEXT;
                end
                S_NEXT: begin
                    if (row == 3'd7) st <= S_DONE;
                    else begin
                        row <= row + 1'b1;
                        st  <= S_PIVOT;
                    end
                end
                S_DONE: begin
                    for (int i = 0; i < 8; i++)
                        for (int j = 0; j < 8; j++)
                            Ainv[i][j] <= M[i][j+8];
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule : calu_mat_inv_8x8
