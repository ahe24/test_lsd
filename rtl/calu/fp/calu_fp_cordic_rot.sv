//==============================================================================
// calu_fp_cordic_rot.sv
// 16-stage circular-rotation CORDIC. Rotates input (x,y) by angle z.
//==============================================================================
module calu_fp_cordic_rot (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en,
    input  logic signed [31:0]  x_in,
    input  logic signed [31:0]  y_in,
    input  logic signed [31:0]  z_in,
    output logic signed [31:0]  x_out,
    output logic signed [31:0]  y_out,
    output logic                valid
);
    // Atan(2^-i) in Q2.30
    localparam logic signed [31:0] ATAN [0:15] = '{
        32'sd843314856, 32'sd497837829, 32'sd263043837, 32'sd133525159,
        32'sd67021687,  32'sd33543515,  32'sd16775851,  32'sd8388437,
        32'sd4194282,   32'sd2097149,   32'sd1048576,   32'sd524288,
        32'sd262144,    32'sd131072,    32'sd65536,     32'sd32768
    };

    logic signed [31:0] x_reg [0:16];
    logic signed [31:0] y_reg [0:16];
    logic signed [31:0] z_reg [0:16];
    logic [16:0]        v_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 17; k++) begin
                x_reg[k] <= '0; y_reg[k] <= '0; z_reg[k] <= '0;
            end
            v_reg <= '0;
        end else begin
            v_reg <= {v_reg[15:0], en};
            x_reg[0] <= x_in; y_reg[0] <= y_in; z_reg[0] <= z_in;
            for (int k = 0; k < 16; k++) begin
                if (z_reg[k] >= 0) begin
                    x_reg[k+1] <= x_reg[k] - (y_reg[k] >>> k);
                    y_reg[k+1] <= y_reg[k] + (x_reg[k] >>> k);
                    z_reg[k+1] <= z_reg[k] - ATAN[k];
                end else begin
                    x_reg[k+1] <= x_reg[k] + (y_reg[k] >>> k);
                    y_reg[k+1] <= y_reg[k] - (x_reg[k] >>> k);
                    z_reg[k+1] <= z_reg[k] + ATAN[k];
                end
            end
        end
    end

    assign x_out = x_reg[16];
    assign y_out = y_reg[16];
    assign valid = v_reg[16];
endmodule : calu_fp_cordic_rot
