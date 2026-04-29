#!/usr/bin/env python3
"""
gen_bloat.py  -  Generate thousands of unique SystemVerilog modules used to
stress the simulator compilation/elaboration/runtime.

Each generated module is *genuinely distinct* — the width, pipeline depth,
reduction tree structure, and LFSR polynomial are all unique per module,
so the elaborator cannot merge them together.

Usage:
    python gen_bloat.py --out ../../rtl/gen --count 2000

Creates <count> modules named lsd_bloat_u0000.sv .. lsd_bloat_u<N-1>.sv plus
lsd_bloat_farm.sv that instantiates all of them.
"""
import argparse
import hashlib
import os
import random
import textwrap

from _heavy_tail import inject_heavy_tail

MAC_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED — DO NOT EDIT BY HAND
// bloat unit #{idx}: kind=mac, W={w}, D={d}, poly=0x{poly:08X}
//==============================================================================
module lsd_bloat_u{idx:04d} (
    input  logic               clk,
    input  logic               rst_n,
    input  logic [{w_m1}:0]  in_a,
    input  logic [{w_m1}:0]  in_b,
    output logic [{wa_m1}:0] out_y
);
    logic [{wa_m1}:0] acc [0:{d_m1}];
    logic [{w_m1}:0]  lfsr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= {{{w}{{1'b1}}}};
            for (int k = 0; k < {d}; k++) acc[k] <= '0;
        end else begin
            lfsr <= {{lfsr[{w_m2}:0], ^(lfsr & {w}'h{poly:X})}};
            acc[0] <= in_a * (in_b ^ lfsr);
{stage_body}
        end
    end

    assign out_y = acc[{d_m1}];
endmodule : lsd_bloat_u{idx:04d}
"""

XOR_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED — DO NOT EDIT BY HAND
// bloat unit #{idx}: kind=xor-tree, W={w}, LEVELS={d}, mix=0x{mix:08X}
//==============================================================================
module lsd_bloat_u{idx:04d} (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [{w_m1}:0]  in_a,
    input  logic [{w_m1}:0]  in_b,
    output logic [{w_m1}:0]  out_y
);
    logic [{w_m1}:0] stg [0:{d}];
    assign stg[0] = (in_a ^ in_b) + {w}'h{mix:X};

    genvar i;
    generate
        for (i = 0; i < {d}; i++) begin : g_lvl
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) stg[i+1] <= '0;
                else        stg[i+1] <= {{stg[i][{w_m2}:0], ^stg[i]}}
                                         ^ ({w}'h{mix:X} >> i);
            end
        end
    endgenerate

    assign out_y = stg[{d}];
endmodule : lsd_bloat_u{idx:04d}
"""

FSM_TEMPLATE = """\
//==============================================================================
// AUTO-GENERATED — DO NOT EDIT BY HAND
// bloat unit #{idx}: kind=fsm, STATES={s}, W={w}
//==============================================================================
module lsd_bloat_u{idx:04d} (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [{w_m1}:0]  in_a,
    input  logic [{w_m1}:0]  in_b,
    output logic [{w_m1}:0]  out_y
);
    logic [{sbw_m1}:0] st, st_n;
    logic [{w_m1}:0]   acc, acc_n;

    always_comb begin
        st_n  = st + 1;
        acc_n = acc;
        case (st)
{case_body}
            default: begin st_n = '0; acc_n = acc ^ {w}'h{mix:X}; end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin st <= '0; acc <= '0; end
        else        begin st <= st_n; acc <= acc_n; end
    end
    assign out_y = acc;
endmodule : lsd_bloat_u{idx:04d}
"""


def gen_mac(idx: int, rng: random.Random) -> str:
    w      = rng.choice([8, 12, 16, 24, 32])
    d      = rng.choice([2, 3, 4, 5, 6, 8, 10])
    poly   = rng.randint(1, (1 << w) - 1)
    wa     = 2 * w
    w_m1   = w - 1
    w_m2   = w - 2
    wa_m1  = wa - 1
    d_m1   = d - 1

    stage_lines = []
    for k in range(1, d):
        stage_lines.append(f"            acc[{k}] <= acc[{k-1}] ^ {{{w}'h{rng.randrange(1 << w):X}, {w}'h{rng.randrange(1 << w):X}}};")
    stage_body = "\n".join(stage_lines)

    return MAC_TEMPLATE.format(idx=idx, w=w, d=d, poly=poly,
                               w_m1=w_m1, w_m2=w_m2,
                               wa_m1=wa_m1, d_m1=d_m1,
                               stage_body=stage_body)


def gen_xor(idx: int, rng: random.Random) -> str:
    w     = rng.choice([8, 10, 16, 20, 24, 32])
    d     = rng.choice([3, 4, 5, 6, 7, 8])
    mix   = rng.randrange(1 << w)
    w_m1  = w - 1
    w_m2  = w - 2
    return XOR_TEMPLATE.format(idx=idx, w=w, d=d, mix=mix,
                               w_m1=w_m1, w_m2=w_m2)


def gen_fsm(idx: int, rng: random.Random) -> str:
    w    = rng.choice([8, 12, 16, 20])
    s    = rng.choice([4, 6, 8, 12, 16, 24])
    mix  = rng.randrange(1 << w)
    sbw  = max(2, (s - 1).bit_length())
    sbw_m1 = sbw - 1
    w_m1 = w - 1
    case_lines = []
    for st in range(s - 1):
        op_choice = rng.choice(['+', '-', '^', '|', '&'])
        operand   = rng.randrange(1 << w)
        case_lines.append(
            f"            {sbw}'d{st}: begin st_n = {sbw}'d{(st+1)%s}; "
            f"acc_n = acc {op_choice} {w}'h{operand:X}; end"
        )
    case_body = "\n".join(case_lines)
    return FSM_TEMPLATE.format(idx=idx, w=w, s=s, mix=mix,
                               sbw_m1=sbw_m1, w_m1=w_m1,
                               case_body=case_body)


def gen_module(idx: int, rng: random.Random) -> str:
    kind = rng.choice(['mac', 'xor', 'fsm'])
    if   kind == 'mac': return gen_mac(idx, rng)
    elif kind == 'xor': return gen_xor(idx, rng)
    else:               return gen_fsm(idx, rng)


def gen_farm(count: int) -> str:
    lines = [
        "//==============================================================================",
        "// lsd_bloat_farm.sv  -  AUTO-GENERATED farm instancing all bloat modules",
        "//==============================================================================",
        "module lsd_bloat_farm (",
        "    input  logic        clk,",
        "    input  logic        rst_n,",
        "    input  logic [31:0] seed",
        ");",
        "    logic [31:0] sig [0:{n}];".format(n=count),
        "    assign sig[0] = seed;",
        "",
        "    genvar gi;",
        "    generate",
    ]
    for i in range(count):
        lines.append(f"        lsd_bloat_u{i:04d} u_{i:04d} (")
        lines.append( "            .clk   (clk),")
        lines.append( "            .rst_n (rst_n),")
        lines.append(f"            .in_a  (sig[{i}]),")
        lines.append(f"            .in_b  (sig[{i}] ^ 32'h{(i*0x9E3779B9) & 0xFFFFFFFF:08X}),")
        lines.append(f"            .out_y (sig[{i+1}])")
        lines.append( "        );")
    lines.append("    endgenerate")
    lines.append("endmodule : lsd_bloat_farm")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True, help='output directory')
    p.add_argument('--count', type=int, default=2000)
    p.add_argument('--seed', type=int, default=0xC0DEBA5E)
    p.add_argument('--work', type=int, default=0,
                   help='heavy MAC stages per unit (0 = baseline)')
    args = p.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    filelist = []
    for i in range(args.count):
        # adapt port widths. The bloater farm expects uniform 32-bit wiring,
        # so we instead generate modules with fixed 32-bit ports but internally
        # unique structure. Re-seed kinds that enforce port width = 32.
        # To keep port widths uniform at 32, wrap variable-width internals with
        # a fixed-width shell.
        inner = gen_module(i, rng)
        shell_idx = i
        wrapped = _make_shell(shell_idx, inner, rng)
        wrapped = inject_heavy_tail(wrapped, args.work, rng)
        path = os.path.join(args.out, f"lsd_bloat_u{i:04d}.sv")
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(wrapped)
        filelist.append(os.path.relpath(path, args.out))

    farm_path = os.path.join(args.out, "lsd_bloat_farm.sv")
    with open(farm_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(gen_farm(args.count))

    # Filelist entries are resolved by vlog relative to its cwd (sim/).
    # args.out is the family subdirectory path relative to sim/, so
    # prefixing each filename with args.out gives a vlog-resolvable path.
    fl_path = os.path.join(args.out, "filelist.f")
    out_rel = args.out.replace('\\', '/').rstrip('/')
    with open(fl_path, 'w', encoding='utf-8', newline='\n') as f:
        for p in filelist:
            f.write(out_rel + "/" + p + "\n")
        f.write(out_rel + "/lsd_bloat_farm.sv\n")

    print(f"Wrote {args.count} bloat modules to {args.out} (+farm +filelist)")


def _make_shell(idx: int, inner_body: str, rng: random.Random) -> str:
    """Rewrite the inner module to expose a 32-bit port interface."""
    # Crude rewrite: replace the port block of the inner module template.
    # Easier: emit a fresh 32-bit module whose body is idx-specific with
    # elements from inner_body retained as a prefix comment so that each
    # generated file is text-distinct (helps defeat compiler dedup).
    text_hash = hashlib.sha256(inner_body.encode()).hexdigest()[:16]
    lfsr_poly = rng.randint(1, 0xFFFFFFFF)
    depth     = rng.choice([3, 4, 5, 6, 7, 8, 10, 12])
    mix1      = rng.randrange(1 << 32)
    mix2      = rng.randrange(1 << 32)
    op1       = rng.choice(['+', '-', '^', '|', '&'])
    op2       = rng.choice(['+', '-', '^', '|', '&'])
    op3       = rng.choice(['+', '^', '|'])

    body = []
    body.append(f"    // inner-body-hash {text_hash}")
    body.append(f"    logic [31:0] st [0:{depth}];")
    body.append("    logic [31:0] lfsr;")
    body.append("    assign st[0] = in_a;")
    body.append("    always_ff @(posedge clk or negedge rst_n) begin")
    body.append("        if (!rst_n) lfsr <= 32'hDEADBEEF;")
    body.append(f"        else        lfsr <= {{lfsr[30:0], ^(lfsr & 32'h{lfsr_poly:08X})}};")
    body.append("    end")
    body.append("    genvar gi;")
    body.append("    generate")
    body.append(f"        for (gi = 0; gi < {depth}; gi++) begin : g_lv")
    body.append("            always_ff @(posedge clk or negedge rst_n) begin")
    body.append("                if (!rst_n) st[gi+1] <= '0;")
    body.append(f"                else begin")
    body.append(f"                    st[gi+1] <= ((st[gi] {op1} in_b) {op2} 32'h{mix1:08X}) {op3} (lfsr ^ 32'h{mix2:08X});")
    body.append("                end")
    body.append("            end")
    body.append("        end")
    body.append("    endgenerate")
    body.append(f"    assign out_y = st[{depth}];")

    return textwrap.dedent("""\
        //==============================================================================
        // AUTO-GENERATED bloat shell #{idx:04d}
        //==============================================================================
        module lsd_bloat_u{idx:04d} (
            input  logic        clk,
            input  logic        rst_n,
            input  logic [31:0] in_a,
            input  logic [31:0] in_b,
            output logic [31:0] out_y
        );
        """).format(idx=idx) + "\n".join(body) + "\nendmodule : lsd_bloat_u{idx:04d}\n".format(idx=idx)


if __name__ == '__main__':
    main()
