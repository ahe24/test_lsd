#!/usr/bin/env python3
"""
gen_churn.py  -  Third-family bloat generator (the "churn" farm).

Naming is intentionally distinct from lsd_bloat / lsd_bloat2 so you can
tell at a glance which family a regenerated file belongs to:
    family 1   lsd_bloat_u####    linear arithmetic chain
    family 2   lsd_bloat2_u####   parallel mem/ring kernels
    family 3   lsd_churn_u####    broadcast-fanout kernels   <-- this script

Topology (structurally different from families 1 and 2):
  The farm maintains 4 internal broadcast signals driven by a free-running
  counter and two LFSRs. Every churn unit subscribes to ALL 4 broadcasts,
  so activity fans out one-to-many instead of chaining (family 1) or
  island-style (family 2). Each unit mixes the broadcasts through its own
  unique internal state, and all taps XOR-reduce to a dead-end node.

Within-family variety comes from two kinds ('mix' and 'roll') and per-
instance unique constants, so the elaborator cannot merge any two units.

Usage:
    python gen_churn.py --out ../../rtl/gen --count 2000

Emits:
    lsd_churn_u0000.sv .. lsd_churn_u<N-1>.sv
    lsd_churn_farm.sv
    gen_churn_filelist.f
"""
import argparse
import os
import random

from _heavy_tail import inject_heavy_tail


MIX_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// churn unit #{idx}: kind=mix D={d}
//==============================================================================
module lsd_churn_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] bcast0,
    input  logic [31:0] bcast1,
    input  logic [31:0] bcast2,
    input  logic [31:0] bcast3,
    output logic [31:0] tap
);
    localparam int D = {d};

    logic [31:0] state [0:D];
    logic [31:0] mixed;

    assign mixed = (bcast0 {op1} 32'h{m1:08X})
                 ^ (bcast1 {op2} 32'h{m2:08X})
                 ^ (bcast3 {op3} 32'h{m3:08X})
                 ^ state[D];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k <= D; k++)
                state[k] <= 32'h{init:08X} + (k * 32'h{kmul:08X});
        end else begin
            state[0] <= mixed {op4} bcast2;
            for (int k = 1; k <= D; k++)
                state[k] <= state[k-1] {op5} 32'h{m5:08X};
        end
    end

    assign tap = state[D] ^ state[0];
endmodule : lsd_churn_u{idx:04d}
"""


ROLL_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// churn unit #{idx}: kind=roll R={r1}/{r2}/{r3}
//==============================================================================
module lsd_churn_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] bcast0,
    input  logic [31:0] bcast1,
    input  logic [31:0] bcast2,
    input  logic [31:0] bcast3,
    output logic [31:0] tap
);
    // Constant rotates per instance: R = {r1}/{r2}/{r3}
    logic [31:0] roll_a, roll_b, roll_c;
    logic [31:0] sum;
    logic [31:0] acc;

    assign roll_a = {{bcast0[{r1a}:0], bcast0[31:{r1b}]}};
    assign roll_b = {{bcast1[{r2a}:0], bcast1[31:{r2b}]}};
    assign roll_c = {{bcast2[{r3a}:0], bcast2[31:{r3b}]}};

    assign sum    = (roll_a {op1} roll_b) {op2} (roll_c ^ bcast3);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) acc <= 32'h{init:08X};
        else        acc <= (acc {op3} sum) ^ 32'h{m1:08X};
    end

    assign tap = acc ^ roll_a;
endmodule : lsd_churn_u{idx:04d}
"""


def gen_mix(idx: int, rng: random.Random) -> str:
    d     = rng.choice([2, 3, 4, 5, 6, 8])
    m1    = rng.randrange(1 << 32)
    m2    = rng.randrange(1 << 32)
    m3    = rng.randrange(1 << 32)
    m5    = rng.randrange(1 << 32)
    init  = rng.randrange(1 << 32)
    kmul  = rng.randrange(1 << 32) | 1
    op1   = rng.choice(['+', '-', '^', '|'])
    op2   = rng.choice(['+', '-', '^', '|'])
    op3   = rng.choice(['+', '-', '^'])
    op4   = rng.choice(['+', '^', '|'])
    op5   = rng.choice(['+', '-', '^'])
    return MIX_TEMPLATE.format(
        idx=idx, d=d, m1=m1, m2=m2, m3=m3, m5=m5,
        init=init, kmul=kmul,
        op1=op1, op2=op2, op3=op3, op4=op4, op5=op5,
    )


def gen_roll(idx: int, rng: random.Random) -> str:
    # Rotates must stay in [1, 31] so the bit-select ranges are legal.
    r1 = rng.randint(1, 31)
    r2 = rng.randint(1, 31)
    r3 = rng.randint(1, 31)
    m1   = rng.randrange(1 << 32)
    init = rng.randrange(1 << 32)
    op1  = rng.choice(['+', '-', '^', '|'])
    op2  = rng.choice(['+', '^', '|'])
    op3  = rng.choice(['+', '-', '^'])
    return ROLL_TEMPLATE.format(
        idx=idx,
        r1=r1, r2=r2, r3=r3,
        r1a=31 - r1, r1b=32 - r1,
        r2a=31 - r2, r2b=32 - r2,
        r3a=31 - r3, r3b=32 - r3,
        m1=m1, init=init,
        op1=op1, op2=op2, op3=op3,
    )


def gen_module(idx: int, rng: random.Random) -> str:
    kind = rng.choice(['mix', 'roll'])
    return gen_mix(idx, rng) if kind == 'mix' else gen_roll(idx, rng)


def gen_farm(count: int) -> str:
    lines = [
        "//==============================================================================",
        "// lsd_churn_farm.sv  -  AUTO-GENERATED broadcast-fanout farm (third family)",
        "//",
        "// Four internal broadcast signals (counter + two LFSRs) are fanned out to",
        "// every leaf. Units are independent but share the broadcast drivers, so",
        "// activity pattern is one-to-many (distinct from the linear chain of",
        "// family 1 and the independent islands of family 2).",
        "//==============================================================================",
        "module lsd_churn_farm (",
        "    input  logic        clk,",
        "    input  logic        rst_n,",
        "    input  logic [31:0] seed",
        ");",
        "    localparam int N = {n};".format(n=count),
        "",
        "    logic [31:0] counter;",
        "    logic [31:0] lfsr0, lfsr1;",
        "    logic [31:0] bcast0, bcast1, bcast2, bcast3;",
        "",
        "    always_ff @(posedge clk or negedge rst_n) begin",
        "        if (!rst_n) begin",
        "            counter <= seed;",
        "            lfsr0   <= 32'hCAFEBABE;",
        "            lfsr1   <= 32'hDEADF00D;",
        "        end else begin",
        "            counter <= counter + 32'h01234567;",
        "            lfsr0   <= {lfsr0[30:0], ^(lfsr0 & 32'hEDB88320)};",
        "            lfsr1   <= {lfsr1[30:0], ^(lfsr1 & 32'h04C11DB7)};",
        "        end",
        "    end",
        "",
        "    assign bcast0 = seed  ^ counter;",
        "    assign bcast1 = lfsr0 + counter;",
        "    assign bcast2 = lfsr1 ^ counter;",
        "    assign bcast3 = lfsr0 ^ lfsr1 ^ seed;",
        "",
        "    logic [31:0] taps [0:N-1];",
        "",
    ]
    for i in range(count):
        lines.append(f"    lsd_churn_u{i:04d} u3_{i:04d} (")
        lines.append( "        .clk    (clk),")
        lines.append( "        .rst_n  (rst_n),")
        lines.append( "        .bcast0 (bcast0),")
        lines.append( "        .bcast1 (bcast1),")
        lines.append( "        .bcast2 (bcast2),")
        lines.append( "        .bcast3 (bcast3),")
        lines.append(f"        .tap    (taps[{i}])")
        lines.append( "    );")
    lines.append("")
    lines.append("    // XOR reduction keeps every tap observable (defeats -O5 pruning).")
    lines.append("    logic [31:0] taps_xor;")
    lines.append("    always_comb begin")
    lines.append("        taps_xor = '0;")
    lines.append("        for (int k = 0; k < N; k++) taps_xor = taps_xor ^ taps[k];")
    lines.append("    end")
    lines.append("endmodule : lsd_churn_farm")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True, help='output directory')
    p.add_argument('--count', type=int, default=2000)
    # Distinct seed from gen_bloat.py / gen_bloat2.py so constants don't correlate.
    p.add_argument('--seed', type=int, default=0x1337D00D)
    p.add_argument('--work', type=int, default=0,
                   help='heavy MAC stages per unit (0 = baseline)')
    args = p.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    filelist = []
    for i in range(args.count):
        body = gen_module(i, rng)
        body = inject_heavy_tail(body, args.work, rng)
        path = os.path.join(args.out, f"lsd_churn_u{i:04d}.sv")
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(body)
        filelist.append(os.path.relpath(path, args.out))

    farm_path = os.path.join(args.out, "lsd_churn_farm.sv")
    with open(farm_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(gen_farm(args.count))

    # Filelist entries are resolved by vlog relative to its cwd (sim/).
    # args.out is the family subdirectory path relative to sim/.
    fl_path = os.path.join(args.out, "filelist.f")
    out_rel = args.out.replace('\\', '/').rstrip('/')
    with open(fl_path, 'w', encoding='utf-8', newline='\n') as f:
        for p in filelist:
            f.write(out_rel + "/" + p + "\n")
        f.write(out_rel + "/lsd_churn_farm.sv\n")

    print(f"Wrote {args.count} churn modules to {args.out} (+farm +filelist)")


if __name__ == '__main__':
    main()
