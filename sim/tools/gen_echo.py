#!/usr/bin/env python3
"""
gen_echo.py  -  Seventh-family bloat generator: deep shift-register
delay lines.

Each leaf is a forward-only shift register of depth D (16..32 per unit)
with an LFSR-mixed input and two internal taps. Unlike the feedback ring
of family 2, the shift register is strictly forward-propagating, giving
long simulator fan-out chains with no cycle.

Emits:
    lsd_echo_u0000.sv .. lsd_echo_u<N-1>.sv
    lsd_echo_farm.sv
    gen_echo_filelist.f
"""
import argparse
import os
import random

from _heavy_tail import inject_heavy_tail


ECHO_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// echo unit #{idx}: delay-line D={d} taps={t1}/{t2}
//==============================================================================
module lsd_echo_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] seed,
    output logic [31:0] tap
);
    localparam int D = {d};

    logic [31:0] delay [0:D-1];
    logic [31:0] lfsr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 32'h{init:08X};
            for (int k = 0; k < D; k++)
                delay[k] <= 32'h{kinit:08X} + (k * 32'h{kmul:08X});
        end else begin
            lfsr     <= {{lfsr[30:0], ^(lfsr & 32'h{poly:08X})}};
            delay[0] <= seed {op1} lfsr;
            for (int k = 1; k < D; k++)
                delay[k] <= delay[k-1] {op2} (delay[{t1}] ^ 32'h{mix:08X});
        end
    end

    assign tap = delay[D-1] ^ delay[{t2}] ^ lfsr;
endmodule : lsd_echo_u{idx:04d}
"""


def gen_unit(idx: int, rng: random.Random) -> str:
    d  = rng.choice([16, 20, 24, 28, 32])
    t1 = rng.randrange(1, d)          # avoid 0 so it's always "an internal" tap
    t2 = rng.randrange(0, d)
    return ECHO_TEMPLATE.format(
        idx=idx, d=d, t1=t1, t2=t2,
        init=rng.randint(1, 0xFFFFFFFF),
        kinit=rng.randrange(1 << 32),
        kmul=rng.randrange(1 << 32) | 1,
        poly=rng.randint(1, 0xFFFFFFFF),
        mix=rng.randrange(1 << 32),
        op1=rng.choice(['+', '-', '^', '|']),
        op2=rng.choice(['+', '-', '^']),
    )


def gen_farm(count: int) -> str:
    lines = [
        "//==============================================================================",
        "// lsd_echo_farm.sv  -  AUTO-GENERATED delay-line bank (family 7)",
        "//",
        "// Parallel leaves, each a 16..32-deep forward shift register fed",
        "// by a seed-derived input. Internal taps mix the shift state so",
        "// every stage does real work.",
        "//==============================================================================",
        "module lsd_echo_farm (",
        "    input  logic        clk,",
        "    input  logic        rst_n,",
        "    input  logic [31:0] seed",
        ");",
        "    localparam int N = {n};".format(n=count),
        "",
        "    logic [31:0] seed_var [0:N-1];",
        "    logic [31:0] taps     [0:N-1];",
        "",
        "    genvar gi;",
        "    generate",
        "        for (gi = 0; gi < N; gi++) begin : g_rot",
        "            assign seed_var[gi] = seed ^ (gi * 32'hBC9F1D34);",
        "        end",
        "    endgenerate",
        "",
    ]
    for i in range(count):
        lines.append(f"    lsd_echo_u{i:04d} u7_{i:04d} (")
        lines.append( "        .clk   (clk),")
        lines.append( "        .rst_n (rst_n),")
        lines.append(f"        .seed  (seed_var[{i}]),")
        lines.append(f"        .tap   (taps[{i}])")
        lines.append( "    );")
    lines.append("")
    lines.append("    logic [31:0] taps_xor;")
    lines.append("    always_comb begin")
    lines.append("        taps_xor = '0;")
    lines.append("        for (int k = 0; k < N; k++) taps_xor = taps_xor ^ taps[k];")
    lines.append("    end")
    lines.append("endmodule : lsd_echo_farm")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True)
    p.add_argument('--count', type=int, default=2000)
    p.add_argument('--seed', type=int, default=0x4543484F)  # 'ECHO'
    p.add_argument('--work', type=int, default=0,
                   help='heavy MAC stages per unit (0 = baseline)')
    args = p.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    filelist = []
    for i in range(args.count):
        unit_sv = inject_heavy_tail(gen_unit(i, rng), args.work, rng)
        path = os.path.join(args.out, f"lsd_echo_u{i:04d}.sv")
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(unit_sv)
        filelist.append(os.path.relpath(path, args.out))

    farm_path = os.path.join(args.out, "lsd_echo_farm.sv")
    with open(farm_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(gen_farm(args.count))

    # Filelist entries are resolved by vlog relative to its cwd (sim/).
    # args.out is the family subdirectory path relative to sim/.
    fl_path = os.path.join(args.out, "filelist.f")
    out_rel = args.out.replace('\\', '/').rstrip('/')
    with open(fl_path, 'w', encoding='utf-8', newline='\n') as f:
        for p in filelist:
            f.write(out_rel + "/" + p + "\n")
        f.write(out_rel + "/lsd_echo_farm.sv\n")

    print(f"Wrote {args.count} echo modules to {args.out} (+farm +filelist)")


if __name__ == '__main__':
    main()
