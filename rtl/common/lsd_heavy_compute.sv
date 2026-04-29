//==============================================================================
// lsd_heavy_compute.sv
// Memory + wide-MAC compute engine designed to defeat qopt -O5 strength
// reduction.  The previous bloat-farm approach generated thousands of unique
// modules but each was so small that qopt could optimise them down to ~0%
// profiler weight, starving ParallelSim of distributable work.
//
// This module instead does *real* per-cycle compute that is hard to
// optimise:
//
//   - A large memory bank (MEM_DEPTH x MEM_WIDTH) that is read AND written
//     every cycle through N_PORTS independent address streams.  qopt has to
//     materialise the memory and the indexed reads/writes — it cannot prove
//     the memory is dead.
//
//   - Per-cycle data-dependent address chains: addr_r[p] depends on the
//     previous cycle's rdata[(p-1) % N_PORTS], so the addresses are not
//     statically predictable and cannot be precomputed at qopt time.
//
//   - N_PORTS wide multiplications per cycle (MEM_WIDTH x MEM_WIDTH ->
//     MEM_WIDTH truncated).  Two runtime-varying multiplicands defeat
//     mul-by-constant strength reduction.  Wider widths force the host
//     CPU to chain multiple native 64-bit multiplications, multiplying
//     simulator wall time per op.
//
//   - A 32-bit XOR-fold of all rdata is presented on `tap` so the chain
//     is structurally observable to the parent (preventing DCE).
//
// External interface is just (clk, rst_n) plus a `tap` output; the parent
// island wraps this with itself + cmd/stream interfaces and exposes only
// (clk, rst_n) so the partitioner sees an atomic island.
//==============================================================================
`ifndef LSD_HEAVY_COMPUTE_SV
`define LSD_HEAVY_COMPUTE_SV

module lsd_heavy_compute #(
    parameter int unsigned       MEM_DEPTH = 2048,    // memory entries
    parameter int unsigned       MEM_WIDTH = 256,     // bits per entry
    parameter int unsigned       N_PORTS   = 8,       // R/W ports per cycle
    parameter logic [63:0]       SEED      = 64'h0123_4567_89AB_CDEF
) (
    input  logic                clk,
    input  logic                rst_n,
    output logic [31:0]         tap
);
    localparam int unsigned AW = $clog2(MEM_DEPTH);

    // -------------------------------------------------------------------------
    // Memory bank — large enough that qopt cannot inline the array contents
    // into the surrounding logic.  Initial values seeded from the parameter
    // so each instance has a structurally distinct dataset.  qopt insists
    // on a single driver, so init runs inside the reset branch of the
    // single mem-update always_ff (further down).
    // -------------------------------------------------------------------------
    logic [MEM_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // -------------------------------------------------------------------------
    // Per-port address generators + read data registers.  Addresses chain on
    // previous read data so qopt cannot statically schedule them.
    // -------------------------------------------------------------------------
    logic [AW-1:0]        addr_r [0:N_PORTS-1];
    logic [AW-1:0]        addr_w [0:N_PORTS-1];
    logic [MEM_WIDTH-1:0] rdata  [0:N_PORTS-1];
    logic [MEM_WIDTH-1:0] wdata  [0:N_PORTS-1];

    // Free-running mixer — independent entropy that perturbs every port's
    // address on top of the read-data feedback.
    logic [63:0] state;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= SEED;
        else        state <= {state[62:0],
                              ^(state & 64'hEDB8_8320_0000_0001)};
    end

    // -------------------------------------------------------------------------
    // Read phase — each port reads at addr_r[p].
    // The synchronous-read style is what Questa's fast simulator turns into
    // an indexed array load each cycle.  N_PORTS reads = N_PORTS events.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int p = 0; p < N_PORTS; p++) begin
                rdata[p] <= MEM_WIDTH'(SEED) ^ MEM_WIDTH'(p * 64'h517C_C1B7_2722_0A95);
            end
        end else begin
            for (int p = 0; p < N_PORTS; p++) begin
                rdata[p] <= mem[addr_r[p]];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read-address generator — chains on previous neighbour's read data so
    // qopt cannot precompute the address sequence.  AW-bit wraparound.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int p = 0; p < N_PORTS; p++) begin
                addr_r[p] <= AW'(SEED >> (p * 5));
            end
        end else begin
            for (int p = 0; p < N_PORTS; p++) begin
                addr_r[p] <= addr_r[p]
                           + AW'(rdata[p][AW-1:0])
                           + AW'(rdata[(p + N_PORTS - 1) % N_PORTS][2*AW-1:AW])
                           ^ AW'(state >> (p * 3));
            end
        end
    end

    // -------------------------------------------------------------------------
    // Write data — wide multiplication of two runtime-varying read values
    // (rdata[p] * rdata[(p+1) % N_PORTS]) plus a halfword swap.  The runtime
    // multiplicand defeats mul-by-constant strength reduction — qopt has to
    // emit a real multi-precision multiply each cycle.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int p = 0; p < N_PORTS; p++) begin
                wdata[p]  <= MEM_WIDTH'(SEED ^ p);
                addr_w[p] <= AW'(SEED >> (p * 7));
            end
        end else begin
            for (int p = 0; p < N_PORTS; p++) begin
                wdata[p]  <= MEM_WIDTH'(rdata[p] * rdata[(p+1) % N_PORTS])
                           ^ {rdata[p][MEM_WIDTH/2-1:0],
                              rdata[p][MEM_WIDTH-1:MEM_WIDTH/2]}
                           ^ MEM_WIDTH'(state);
                addr_w[p] <= AW'(rdata[p][AW-1:0]
                              ^ rdata[(p+2) % N_PORTS][2*AW-1:AW])
                           + AW'(state >> (p * 11));
            end
        end
    end

    // -------------------------------------------------------------------------
    // Memory updater — both reset-time init and per-cycle writes live here
    // so `mem` has exactly one driver (qopt rejects multi-driver arrays).
    // Reset seeds the bank with a per-instance pattern.  Steady state writes
    // wdata[p] into mem[addr_w[p]] for each of the N_PORTS write ports —
    // when ports collide, last-assignment-wins per always_ff scheduling,
    // which is fine because the goal is event volume.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MEM_DEPTH; i++) begin
                mem[i] <= {{(MEM_WIDTH/64){SEED}}}
                        ^ MEM_WIDTH'(i * 64'h9E37_79B9_7F4A_7C15);
            end
        end else begin
            for (int p = 0; p < N_PORTS; p++) begin
                mem[addr_w[p]] <= wdata[p];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Tap — XOR-fold all read & write data into a 32-bit signal so the
    // entire chain has a path to a structurally observable output.  This is
    // what prevents qopt from decimating the rest of the engine.
    // -------------------------------------------------------------------------
    logic [31:0] tap_next;
    always_comb begin
        logic [31:0] t;
        t = '0;
        for (int p = 0; p < N_PORTS; p++) begin
            t = t ^ rdata[p][31:0]
                  ^ rdata[p][63:32]
                  ^ wdata[p][31:0];
        end
        tap_next = t;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) tap <= '0;
        else        tap <= tap_next;
    end
endmodule : lsd_heavy_compute

`endif // LSD_HEAVY_COMPUTE_SV
