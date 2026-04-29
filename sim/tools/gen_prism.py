#!/usr/bin/env python3
"""
gen_prism.py  -  Sixth-family bloat generator: 64-bit MAC chain.

Topology matches family 1's linear chain but everything widens to 64-bit
plus a real 32x32->64 multiplier per stage. Wider data widths stress the
simulator's bit-blasting and event propagation paths differently from the
32-bit families.

Emits:
    lsd_prism_u0000.sv .. lsd_prism_u<N-1>.sv
    lsd_prism_farm.sv
    gen_prism_filelist.f
"""
import argparse
import os
import random

from _heavy_tail import inject_heavy_tail


PRISM_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// prism unit #{idx}: 64-bit MAC chain D={d}
//==============================================================================
module lsd_prism_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [63:0] in_x,
    output logic [63:0] out_y
);
    localparam int D = {d};

    logic [63:0] stg [0:D];
    logic [63:0] lfsr;
    logic [63:0] prod;

    // 32x32 -> 64 widening multiply (zero-extend both sides).
    assign prod = 64'(in_x[31:0]) * 64'(in_x[63:32]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 64'h{init:016X};
            for (int k = 0; k <= D; k++)
                stg[k] <= 64'h{kinit:016X} + (k * 64'h{kmul:016X});
        end else begin
            lfsr   <= {{lfsr[62:0], ^(lfsr & 64'h{poly:016X})}};
            stg[0] <= prod {op1} (in_x ^ lfsr);
            for (int k = 1; k <= D; k++)
                stg[k] <= (stg[k-1] {op2} 64'h{mix1:016X})
                        ^ (lfsr {op3} 64'h{mix2:016X});
        end
    end

    assign out_y = stg[D] ^ lfsr;
endmodule : lsd_prism_u{idx:04d}
"""


def gen_unit(idx: int, rng: random.Random) -> str:
    return PRISM_TEMPLATE.format(
        idx=idx,
        d=rng.choice([2, 3, 4, 5, 6]),
        init=rng.randrange(1 << 64) | 1,
        kinit=rng.randrange(1 << 64),
        kmul=rng.randrange(1 << 64) | 1,
        poly=rng.randrange(1, 1 << 64),
        mix1=rng.randrange(1 << 64),
        mix2=rng.randrange(1 << 64),
        op1=rng.choice(['+', '-', '^', '|']),
        op2=rng.choice(['+', '-', '^']),
        op3=rng.choice(['+', '^', '|']),
    )


def gen_farm(count: int) -> str:
    lines = [
        "//==============================================================================",
        "// lsd_prism_farm.sv  -  AUTO-GENERATED 64-bit MAC chain (family 6)",
        "//",
        "// Linear chain of 64-bit units with a real 32x32->64 multiplier per",
        "// stage. Wider data path stresses simulator paths the 32-bit",
        "// families do not exercise.",
        "//==============================================================================",
        "module lsd_prism_farm (",
        "    input  logic        clk,",
        "    input  logic        rst_n,",
        "    input  logic [31:0] seed",
        ");",
        "    localparam int N = {n};".format(n=count),
        "",
        "    logic [63:0] sig [0:N];",
        "    assign sig[0] = {seed ^ 32'hFACE0000, seed ^ 32'h0000FEED};",
        "",
    ]
    for i in range(count):
        lines.append(f"    lsd_prism_u{i:04d} u6_{i:04d} (")
        lines.append( "        .clk   (clk),")
        lines.append( "        .rst_n (rst_n),")
        lines.append(f"        .in_x  (sig[{i}]),")
        lines.append(f"        .out_y (sig[{i+1}])")
        lines.append( "    );")
    lines.append("endmodule : lsd_prism_farm")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True)
    p.add_argument('--count', type=int, default=2000)
    p.add_argument('--seed', type=int, default=0x5052534D)  # 'PRSM'
    p.add_argument('--work', type=int, default=0,
                   help='heavy MAC stages per unit (0 = baseline)')
    args = p.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    filelist = []
    for i in range(args.count):
        unit_sv = inject_heavy_tail(gen_unit(i, rng), args.work, rng)
        path = os.path.join(args.out, f"lsd_prism_u{i:04d}.sv")
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(unit_sv)
        filelist.append(os.path.relpath(path, args.out))

    farm_path = os.path.join(args.out, "lsd_prism_farm.sv")
    with open(farm_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(gen_farm(args.count))

    # Filelist entries are resolved by vlog relative to its cwd (sim/).
    # args.out is the family subdirectory path relative to sim/.
    fl_path = os.path.join(args.out, "filelist.f")
    out_rel = args.out.replace('\\', '/').rstrip('/')
    with open(fl_path, 'w', encoding='utf-8', newline='\n') as f:
        for p in filelist:
            f.write(out_rel + "/" + p + "\n")
        f.write(out_rel + "/lsd_prism_farm.sv\n")

    print(f"Wrote {args.count} prism modules to {args.out} (+farm +filelist)")


if __name__ == '__main__':
    main()
