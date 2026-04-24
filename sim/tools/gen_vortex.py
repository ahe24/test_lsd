#!/usr/bin/env python3
"""
gen_vortex.py  -  Eighth-family bloat generator: tick-driven counter banks.

The farm generates a 1-bit tick that pulses at a fixed cadence; every
leaf subscribes to the tick plus its own seed rotation. Each leaf holds
three 16-bit counters with per-instance increments -- some gated by the
tick, some not -- plus an accumulator that mixes them with the seed.

Distinct wedge vs family 3 (churn): churn broadcasts 4x32-bit dense
signals; vortex broadcasts exactly one 1-bit signal, so the resulting
fan-out topology and per-clock activity profile are very different.

Emits:
    lsd_vortex_u0000.sv .. lsd_vortex_u<N-1>.sv
    lsd_vortex_farm.sv
    gen_vortex_filelist.f
"""
import argparse
import os
import random


VORTEX_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED - DO NOT EDIT BY HAND
// vortex unit #{idx}: tick-gated counter bank
//==============================================================================
module lsd_vortex_u{idx:04d} (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        tick,
    input  logic [31:0] seed,
    output logic [31:0] out_y
);
    logic [15:0] cnt_a, cnt_b, cnt_c;
    logic [31:0] acc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_a <= 16'h{ia:04X};
            cnt_b <= 16'h{ib:04X};
            cnt_c <= 16'h{ic:04X};
            acc   <= 32'h{init:08X};
        end else begin
            cnt_a <= tick ? (cnt_a + 16'd{sa}) : cnt_a;
            cnt_b <= cnt_b + 16'd{sb};
            cnt_c <= cnt_c + 16'd{sc} + (tick ? 16'd1 : 16'd0);
            acc   <= (acc {op1} {{cnt_a, cnt_b}}) ^ (seed {op2} {{16'h0, cnt_c}});
        end
    end

    assign out_y = acc ^ {{cnt_a, 16'h0}} ^ {{16'h0, cnt_c}};
endmodule : lsd_vortex_u{idx:04d}
"""


def gen_unit(idx: int, rng: random.Random) -> str:
    # Per-instance increments; must be odd or small to keep counters lively.
    return VORTEX_TEMPLATE.format(
        idx=idx,
        ia=rng.randrange(1 << 16),
        ib=rng.randrange(1 << 16),
        ic=rng.randrange(1 << 16),
        init=rng.randrange(1 << 32),
        sa=rng.choice([1, 3, 5, 7, 11, 13, 17, 19, 23]),
        sb=rng.choice([1, 2, 3, 5, 7, 11, 13]),
        sc=rng.choice([1, 3, 5, 7, 9, 11]),
        op1=rng.choice(['+', '-', '^', '|']),
        op2=rng.choice(['+', '^', '|']),
    )


def gen_farm(count: int) -> str:
    lines = [
        "//==============================================================================",
        "// lsd_vortex_farm.sv  -  AUTO-GENERATED counter bank farm (family 8)",
        "//",
        "// One 1-bit tick is fanned out to every leaf; leaves also receive",
        "// a per-instance seed rotation. Sparse broadcast signature is a",
        "// structural wedge distinct from the dense 4x32-bit churn farm.",
        "//==============================================================================",
        "module lsd_vortex_farm (",
        "    input  logic        clk,",
        "    input  logic        rst_n,",
        "    input  logic [31:0] seed",
        ");",
        "    localparam int N = {n};".format(n=count),
        "",
        "    logic [7:0] tick_cnt;",
        "    logic       tick;",
        "",
        "    always_ff @(posedge clk or negedge rst_n) begin",
        "        if (!rst_n) begin",
        "            tick_cnt <= 8'h0;",
        "            tick     <= 1'b0;",
        "        end else begin",
        "            tick_cnt <= tick_cnt + 8'd1;",
        "            tick     <= (tick_cnt[2:0] == 3'h7);  // every 8 clocks",
        "        end",
        "    end",
        "",
        "    logic [31:0] seed_var [0:N-1];",
        "    logic [31:0] y        [0:N-1];",
        "",
        "    genvar gi;",
        "    generate",
        "        for (gi = 0; gi < N; gi++) begin : g_rot",
        "            assign seed_var[gi] = seed ^ (gi * 32'hD6B5F341);",
        "        end",
        "    endgenerate",
        "",
    ]
    for i in range(count):
        lines.append(f"    lsd_vortex_u{i:04d} u8_{i:04d} (")
        lines.append( "        .clk   (clk),")
        lines.append( "        .rst_n (rst_n),")
        lines.append( "        .tick  (tick),")
        lines.append(f"        .seed  (seed_var[{i}]),")
        lines.append(f"        .out_y (y[{i}])")
        lines.append( "    );")
    lines.append("")
    lines.append("    logic [31:0] y_xor;")
    lines.append("    always_comb begin")
    lines.append("        y_xor = '0;")
    lines.append("        for (int k = 0; k < N; k++) y_xor = y_xor ^ y[k];")
    lines.append("    end")
    lines.append("endmodule : lsd_vortex_farm")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True)
    p.add_argument('--count', type=int, default=2000)
    p.add_argument('--seed', type=int, default=0x564F5254)  # 'VORT'
    args = p.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    filelist = []
    for i in range(args.count):
        path = os.path.join(args.out, f"lsd_vortex_u{i:04d}.sv")
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(gen_unit(i, rng))
        filelist.append(os.path.relpath(path, args.out))

    farm_path = os.path.join(args.out, "lsd_vortex_farm.sv")
    with open(farm_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(gen_farm(args.count))

    # Filelist entries are resolved by vlog relative to its cwd (sim/).
    # args.out is the family subdirectory path relative to sim/.
    fl_path = os.path.join(args.out, "filelist.f")
    out_rel = args.out.replace('\\', '/').rstrip('/')
    with open(fl_path, 'w', encoding='utf-8', newline='\n') as f:
        for p in filelist:
            f.write(out_rel + "/" + p + "\n")
        f.write(out_rel + "/lsd_vortex_farm.sv\n")

    print(f"Wrote {args.count} vortex modules to {args.out} (+farm +filelist)")


if __name__ == '__main__':
    main()
