#!/usr/bin/env python3
"""
gen_grind.py  -  Fourth-family bloat generator: crosscouple ring.

Topology: leaves are arranged in a logical ring; every leaf's output feeds
both of its neighbors' next-cycle inputs (in_prev, in_next). Seed is XORed
into one ring edge so the loop never settles to a steady state.

Distinct from families 1-3: not a chain (1), not fully independent (2),
not a 1-to-N broadcast (3) -- bidirectional neighbor coupling forms a
ring dependency that ripples both clockwise and counter-clockwise.

Emits:
    lsd_grind_u0000.sv .. lsd_grind_u<N-1>.sv
    lsd_grind_farm.sv
    gen_grind_filelist.f
"""
import argparse
import os
import random


GRIND_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// grind unit #{idx}: crosscouple mixer
//==============================================================================
module lsd_grind_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] in_prev,
    input  logic [31:0] in_next,
    output logic [31:0] out_y
);
    logic [31:0] state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= 32'h{init:08X};
        else        state <= ((in_prev {op1} 32'h{m1:08X})
                              {op2} (in_next {op3} 32'h{m2:08X}))
                             {op4} (state {op5} 32'h{m3:08X});
    end

    assign out_y = state ^ 32'h{mx:08X};
endmodule : lsd_grind_u{idx:04d}
"""


def gen_unit(idx: int, rng: random.Random) -> str:
    return GRIND_TEMPLATE.format(
        idx=idx,
        init=rng.randrange(1 << 32),
        m1=rng.randrange(1 << 32),
        m2=rng.randrange(1 << 32),
        m3=rng.randrange(1 << 32),
        mx=rng.randrange(1 << 32),
        op1=rng.choice(['+', '-', '^', '|']),
        op2=rng.choice(['+', '^', '|']),
        op3=rng.choice(['+', '-', '^', '|']),
        op4=rng.choice(['+', '^', '|']),
        op5=rng.choice(['+', '-', '^']),
    )


def gen_farm(count: int) -> str:
    lines = [
        "//==============================================================================",
        "// lsd_grind_farm.sv  -  AUTO-GENERATED crosscouple ring (family 4)",
        "//",
        "// Units are arranged in a ring; each unit sees both neighbors'",
        "// previous-cycle outputs. Seed XORed into one ring edge keeps the",
        "// loop from settling.",
        "//==============================================================================",
        "module lsd_grind_farm (",
        "    input  logic        clk,",
        "    input  logic        rst_n,",
        "    input  logic [31:0] seed",
        ");",
        "    localparam int N = {n};".format(n=count),
        "",
        "    logic [31:0] y [0:N-1];",
        "    logic [31:0] prev_injected;",
        "",
        "    // Seed injection at ring edge for unit 0 (prevents quiescent state).",
        "    assign prev_injected = y[N-1] ^ seed;",
        "",
    ]
    for i in range(count):
        prev_expr = "prev_injected" if i == 0 else f"y[{i-1}]"
        next_expr = f"y[{(i+1) % count}]"
        lines.append(f"    lsd_grind_u{i:04d} u4_{i:04d} (")
        lines.append( "        .clk     (clk),")
        lines.append( "        .rst_n   (rst_n),")
        lines.append(f"        .in_prev ({prev_expr}),")
        lines.append(f"        .in_next ({next_expr}),")
        lines.append(f"        .out_y   (y[{i}])")
        lines.append( "    );")
    lines.append("")
    lines.append("    // XOR reduction keeps every leaf observable (defeats -O5 pruning).")
    lines.append("    logic [31:0] y_xor;")
    lines.append("    always_comb begin")
    lines.append("        y_xor = '0;")
    lines.append("        for (int k = 0; k < N; k++) y_xor = y_xor ^ y[k];")
    lines.append("    end")
    lines.append("endmodule : lsd_grind_farm")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True)
    p.add_argument('--count', type=int, default=2000)
    p.add_argument('--seed', type=int, default=0x47524E44)  # 'GRND'
    args = p.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    filelist = []
    for i in range(args.count):
        path = os.path.join(args.out, f"lsd_grind_u{i:04d}.sv")
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(gen_unit(i, rng))
        filelist.append(os.path.relpath(path, args.out))

    farm_path = os.path.join(args.out, "lsd_grind_farm.sv")
    with open(farm_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(gen_farm(args.count))

    # Filelist entries are resolved by vlog relative to its cwd (sim/).
    # args.out is the family subdirectory path relative to sim/.
    fl_path = os.path.join(args.out, "filelist.f")
    out_rel = args.out.replace('\\', '/').rstrip('/')
    with open(fl_path, 'w', encoding='utf-8', newline='\n') as f:
        for p in filelist:
            f.write(out_rel + "/" + p + "\n")
        f.write(out_rel + "/lsd_grind_farm.sv\n")

    print(f"Wrote {args.count} grind modules to {args.out} (+farm +filelist)")


if __name__ == '__main__':
    main()
