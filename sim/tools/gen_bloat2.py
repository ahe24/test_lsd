#!/usr/bin/env python3
"""
gen_bloat2.py  -  Second-family bloat generator.

Produces a *parallel* farm of memory- and shift-ring-based modules that
run concurrently alongside the linear-chain farm emitted by gen_bloat.py.
Two families with different structural topologies make it far harder for
the simulator's optimizer to pattern-match and collapse the workload.

Each generated module has:
  - a distinct LFSR polynomial,
  - distinct mix constants / ops,
  - distinct internal size (mem depth or ring length),
  - distinct address step / tap positions,
so the elaborator cannot merge any two together.

Farm topology is intentionally *parallel*, not a chain: every instance
gets its own rotated seed and runs independently. Outputs XOR-reduce into
a single dead-end signal that keeps every tap observable (prevents -O5
from pruning any leaf instance).

Usage:
    python gen_bloat2.py --out ../../rtl/gen --count 2000

Emits:
    lsd_bloat2_u0000.sv .. lsd_bloat2_u<N-1>.sv
    lsd_bloat2_farm.sv
    gen2_filelist.f
"""
import argparse
import os
import random


MEM_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// bloat2 unit #{idx}: kind=mem-scan AW={aw} STEP={step} poly=0x{poly:08X}
//==============================================================================
module lsd_bloat2_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] seed,
    output logic [31:0] tap
);
    localparam int AW    = {aw};
    localparam int DEPTH = 1 << AW;

    logic [31:0]    mem [0:DEPTH-1];
    logic [AW-1:0]  wptr, rptr;
    logic [31:0]    lfsr;
    logic [31:0]    acc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 32'h{init:08X};
            wptr <= '0;
            rptr <= {aw}'d{roff};
            acc  <= 32'h{mix0:08X};
            for (int i = 0; i < DEPTH; i++)
                mem[i] <= (32'h{pat:08X} ^ (i * 32'h9E3779B1));
        end else begin
            lfsr      <= {{lfsr[30:0], ^(lfsr & 32'h{poly:08X})}};
            mem[wptr] <= (seed ^ lfsr) {op1} 32'h{mix1:08X};
            wptr      <= wptr + {aw}'d1;
            rptr      <= rptr + {aw}'d{step};
            acc       <= (acc {op2} mem[rptr]) ^ 32'h{mix2:08X};
        end
    end

    assign tap = acc ^ lfsr;
endmodule : lsd_bloat2_u{idx:04d}
"""


RING_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// bloat2 unit #{idx}: kind=ring-shift N={n} taps={t0}/{t1}/{t2}
//==============================================================================
module lsd_bloat2_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] seed,
    output logic [31:0] tap
);
    localparam int N = {n};

    logic [31:0] ring [0:N-1];
    logic [31:0] fb;

    assign fb = ring[{t0}] ^ ring[{t1}] ^ ring[{t2}] ^ seed;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < N; k++)
                ring[k] <= seed ^ (32'h{init:08X} + (k * 32'h{kmul:08X}));
        end else begin
            for (int k = N-1; k > 0; k--)
                ring[k] <= ring[k-1] {op1} 32'h{mix1:08X};
            ring[0] <= fb {op2} 32'h{mix2:08X};
        end
    end

    assign tap = ring[N-1] ^ ring[{t0}];
endmodule : lsd_bloat2_u{idx:04d}
"""


def gen_mem(idx: int, rng: random.Random) -> str:
    aw     = rng.choice([4, 5, 6, 7])
    depth  = 1 << aw
    # step coprime to depth so the read pointer walks every slot
    step   = rng.choice([3, 5, 7, 11, 13]) % depth
    if step == 0:
        step = 3
    poly   = rng.randint(1, 0xFFFFFFFF)
    init   = rng.randint(1, 0xFFFFFFFF)
    roff   = rng.randrange(depth)
    mix0   = rng.randrange(1 << 32)
    mix1   = rng.randrange(1 << 32)
    mix2   = rng.randrange(1 << 32)
    pat    = rng.randrange(1 << 32)
    op1    = rng.choice(['+', '-', '^', '|'])
    op2    = rng.choice(['+', '^', '|'])
    return MEM_TEMPLATE.format(
        idx=idx, aw=aw, step=step, poly=poly,
        init=init, roff=roff, mix0=mix0, mix1=mix1, mix2=mix2,
        pat=pat, op1=op1, op2=op2,
    )


def gen_ring(idx: int, rng: random.Random) -> str:
    n      = rng.choice([4, 6, 8, 10, 12])
    t0, t1, t2 = rng.sample(range(n), 3)
    init   = rng.randrange(1 << 32)
    kmul   = rng.randrange(1 << 32) | 1
    mix1   = rng.randrange(1 << 32)
    mix2   = rng.randrange(1 << 32)
    op1    = rng.choice(['+', '-', '^'])
    op2    = rng.choice(['+', '^', '|'])
    return RING_TEMPLATE.format(
        idx=idx, n=n, t0=t0, t1=t1, t2=t2,
        init=init, kmul=kmul, mix1=mix1, mix2=mix2,
        op1=op1, op2=op2,
    )


def gen_module(idx: int, rng: random.Random) -> str:
    kind = rng.choice(['mem', 'ring'])
    return gen_mem(idx, rng) if kind == 'mem' else gen_ring(idx, rng)


def gen_farm(count: int) -> str:
    lines = [
        "//==============================================================================",
        "// lsd_bloat2_farm.sv  -  AUTO-GENERATED parallel farm (second family)",
        "//",
        "// Every leaf instance runs independently off a rotated seed; there is no",
        "// data chain between instances. Outputs XOR-reduce into a single dead-end",
        "// node so the optimizer cannot prune any leaf.",
        "//==============================================================================",
        "module lsd_bloat2_farm (",
        "    input  logic        clk,",
        "    input  logic        rst_n,",
        "    input  logic [31:0] seed",
        ");",
        "    localparam int N = {n};".format(n=count),
        "",
        "    logic [31:0] taps     [0:N-1];",
        "    logic [31:0] seed_rot [0:N-1];",
        "",
        "    // Per-instance seed perturbation: distinct start state for every leaf.",
        "    genvar gi;",
        "    generate",
        "        for (gi = 0; gi < N; gi++) begin : g_rot",
        "            assign seed_rot[gi] = seed ^ (gi * 32'h9E3779B1);",
        "        end",
        "    endgenerate",
        "",
    ]
    for i in range(count):
        lines.append(f"    lsd_bloat2_u{i:04d} u2_{i:04d} (")
        lines.append( "        .clk   (clk),")
        lines.append( "        .rst_n (rst_n),")
        lines.append(f"        .seed  (seed_rot[{i}]),")
        lines.append(f"        .tap   (taps[{i}])")
        lines.append( "    );")
    lines.append("")
    lines.append("    // XOR reduction keeps every tap observable (defeats -O5 pruning).")
    lines.append("    logic [31:0] taps_xor;")
    lines.append("    always_comb begin")
    lines.append("        taps_xor = '0;")
    lines.append("        for (int k = 0; k < N; k++) taps_xor = taps_xor ^ taps[k];")
    lines.append("    end")
    lines.append("endmodule : lsd_bloat2_farm")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True, help='output directory')
    p.add_argument('--count', type=int, default=2000)
    # Distinct default seed from gen_bloat.py to avoid correlated constants.
    p.add_argument('--seed', type=int, default=0xBEEFCAFE)
    args = p.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    filelist = []
    for i in range(args.count):
        body = gen_module(i, rng)
        path = os.path.join(args.out, f"lsd_bloat2_u{i:04d}.sv")
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(body)
        filelist.append(os.path.relpath(path, args.out))

    farm_path = os.path.join(args.out, "lsd_bloat2_farm.sv")
    with open(farm_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(gen_farm(args.count))

    # Same -f resolution rule as gen_bloat.py: paths are relative to sim/.
    fl_path = os.path.join(args.out, "gen2_filelist.f")
    rel_prefix = "../rtl/gen/"
    with open(fl_path, 'w', encoding='utf-8', newline='\n') as f:
        for p in filelist:
            f.write(rel_prefix + p + "\n")
        f.write(rel_prefix + "lsd_bloat2_farm.sv\n")

    print(f"Wrote {args.count} bloat2 modules to {args.out} (+farm +filelist)")


if __name__ == '__main__':
    main()
