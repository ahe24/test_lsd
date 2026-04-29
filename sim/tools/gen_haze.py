#!/usr/bin/env python3
"""
gen_haze.py  -  Fifth-family bloat generator: pairwise fan-in.

Every leaf takes TWO distinct 32-bit inputs derived from the farm seed
(different rotations/mixes per port, per index) and runs a short 3-stage
pipeline. The 2-input port signature itself is the structural wedge:
family 1 (chain) and families 2/7 (islands) are 1-in; family 3 is
4-in broadcast; this one is strictly pairwise.

Emits:
    lsd_haze_u0000.sv .. lsd_haze_u<N-1>.sv
    lsd_haze_farm.sv
    gen_haze_filelist.f
"""
import argparse
import os
import random

from _heavy_tail import inject_heavy_tail


HAZE_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// haze unit #{idx}: pairwise fan-in mixer
//==============================================================================
module lsd_haze_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] in_a,
    input  logic [31:0] in_b,
    output logic [31:0] out_y
);
    logic [31:0] stg1, stg2, stg3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg1 <= 32'h{i1:08X};
            stg2 <= 32'h{i2:08X};
            stg3 <= 32'h{i3:08X};
        end else begin
            stg1 <= (in_a {op1} 32'h{m1:08X}) ^ (in_b {op2} 32'h{m2:08X});
            stg2 <= stg1 {op3} 32'h{m3:08X};
            stg3 <= (stg2 ^ in_a) {op4} (in_b ^ 32'h{m4:08X});
        end
    end

    assign out_y = stg3 ^ stg1;
endmodule : lsd_haze_u{idx:04d}
"""


def gen_unit(idx: int, rng: random.Random) -> str:
    return HAZE_TEMPLATE.format(
        idx=idx,
        i1=rng.randrange(1 << 32),
        i2=rng.randrange(1 << 32),
        i3=rng.randrange(1 << 32),
        m1=rng.randrange(1 << 32),
        m2=rng.randrange(1 << 32),
        m3=rng.randrange(1 << 32),
        m4=rng.randrange(1 << 32),
        op1=rng.choice(['+', '-', '^', '|']),
        op2=rng.choice(['+', '-', '^', '|']),
        op3=rng.choice(['+', '-', '^']),
        op4=rng.choice(['+', '^', '|']),
    )


def gen_farm(count: int) -> str:
    lines = [
        "//==============================================================================",
        "// lsd_haze_farm.sv  -  AUTO-GENERATED pairwise fan-in (family 5)",
        "//",
        "// Each leaf consumes two independent seed-derived signals on its",
        "// (in_a, in_b) ports and contributes to a global XOR reduction.",
        "//==============================================================================",
        "module lsd_haze_farm (",
        "    input  logic        clk,",
        "    input  logic        rst_n,",
        "    input  logic [31:0] seed",
        ");",
        "    localparam int N = {n};".format(n=count),
        "",
        "    logic [31:0] seed_a [0:N-1];",
        "    logic [31:0] seed_b [0:N-1];",
        "    logic [31:0] y      [0:N-1];",
        "",
        "    // Distinct port-A / port-B seed derivations per instance.",
        "    genvar gi;",
        "    generate",
        "        for (gi = 0; gi < N; gi++) begin : g_rot",
        "            assign seed_a[gi] = seed + (gi * 32'hE7C1FD03);",
        "            assign seed_b[gi] = (seed ^ 32'hAAAA5555)",
        "                              + (gi * 32'h9E3779B1);",
        "        end",
        "    endgenerate",
        "",
    ]
    for i in range(count):
        lines.append(f"    lsd_haze_u{i:04d} u5_{i:04d} (")
        lines.append( "        .clk   (clk),")
        lines.append( "        .rst_n (rst_n),")
        lines.append(f"        .in_a  (seed_a[{i}]),")
        lines.append(f"        .in_b  (seed_b[{i}]),")
        lines.append(f"        .out_y (y[{i}])")
        lines.append( "    );")
    lines.append("")
    lines.append("    logic [31:0] y_xor;")
    lines.append("    always_comb begin")
    lines.append("        y_xor = '0;")
    lines.append("        for (int k = 0; k < N; k++) y_xor = y_xor ^ y[k];")
    lines.append("    end")
    lines.append("endmodule : lsd_haze_farm")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True)
    p.add_argument('--count', type=int, default=2000)
    p.add_argument('--seed', type=int, default=0x48415A45)  # 'HAZE'
    p.add_argument('--work', type=int, default=0,
                   help='heavy MAC stages per unit (0 = baseline)')
    args = p.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    filelist = []
    for i in range(args.count):
        unit_sv = inject_heavy_tail(gen_unit(i, rng), args.work, rng)
        path = os.path.join(args.out, f"lsd_haze_u{i:04d}.sv")
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(unit_sv)
        filelist.append(os.path.relpath(path, args.out))

    farm_path = os.path.join(args.out, "lsd_haze_farm.sv")
    with open(farm_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(gen_farm(args.count))

    # Filelist entries are resolved by vlog relative to its cwd (sim/).
    # args.out is the family subdirectory path relative to sim/.
    fl_path = os.path.join(args.out, "filelist.f")
    out_rel = args.out.replace('\\', '/').rstrip('/')
    with open(fl_path, 'w', encoding='utf-8', newline='\n') as f:
        for p in filelist:
            f.write(out_rel + "/" + p + "\n")
        f.write(out_rel + "/lsd_haze_farm.sv\n")

    print(f"Wrote {args.count} haze modules to {args.out} (+farm +filelist)")


if __name__ == '__main__':
    main()
