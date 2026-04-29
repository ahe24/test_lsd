"""
_heavy_tail.py  -  Shared utility for inflating per-unit cycle work in the
generated bloat farms (gen_*.py).

The "heavy tail" is an N-stage pipelined 64-bit multiply-accumulate chain
appended to each generated unit.  Each stage burns substantially more
simulation time per cycle than a 32-bit XOR/ADD because event-based
SystemVerilog simulators model wide multiplications as many internal
operations.  All constants are unique per stage and per unit, so the
optimiser cannot dedup the new work across modules.

Use:
    from _heavy_tail import inject_heavy_tail

    unit_sv = TEMPLATE.format(...)
    unit_sv = inject_heavy_tail(unit_sv, args.work, rng)
    f.write(unit_sv)

When work <= 0 the utility is a no-op and the unit is left untouched.

The injection does two things:
  1. Inserts a multi-line SV decl block (LFSR seed + N MAC stages) before
     the unit's `endmodule`.
  2. XORs the final 32-bit fold of hw_state[N] into the unit's existing
     output assignment (assign out_y = ... ;  /  assign tap = ... ;).

The XOR mix is what keeps qopt -O5 from dead-code-eliminating the new
state — it makes the heavy state structurally observable through the
existing module port.
"""
from __future__ import annotations

import random
import re
from typing import Tuple


def heavy_tail(work: int, rng: random.Random) -> Tuple[str, str]:
    """Return (decl_block, mix_expr).

    Each "stage" of the tail is a 128-bit pipelined squarer + barrel
    rotate that depends on its own previous output.  Squaring a runtime
    value defeats qopt's strength-reduction (the multiplicand is not a
    constant), and the rotate ensures wide cross-bit dependencies so the
    simulator materialises each register update as real work.

    Empirically (Questa 2026.1, Windows): each work=+1 increment adds
    roughly +5 % to qsim wall time on a stress profile.  A few units of
    work give a meaningful but bounded uplift; if you need to grow runs
    further, combine BLOAT_WORK with longer +run_ns or larger
    BLOAT_COUNT.

    decl_block is SV code inserted *before* the unit's existing
    `assign out_y/tap = ...;` line.  mix_expr is a 32-bit XOR-fold of
    the final stage's state, ORed into the output assignment so qopt
    cannot DCE the chain.

    For work <= 0, both strings are empty.
    """
    if work <= 0:
        return ("", "")

    seed_init = rng.randrange(1, 1 << 128)
    seed_poly = rng.randrange(1, 1 << 64)

    lines = [
        "",
        f"    // -- Heavy work tail (work={work}): {work} pipelined 128-bit squarer stages",
        f"    //    Each stage:  hw_state[i+1] = hw_state[i]*hw_state[i] ^ rotate(hw_state[i])",
        f"    //    Squaring a runtime value blocks qopt strength-reduction.",
        f"    logic [127:0] hw_state [0:{work}];",
        f"",
        f"    always_ff @(posedge clk or negedge rst_n) begin",
        f"        if (!rst_n) hw_state[0] <= 128'h{seed_init:032X};",
        f"        else        hw_state[0] <= {{hw_state[0][126:0],"
        f" ^(hw_state[0][63:0] & 64'h{seed_poly:016X})}};",
        f"    end",
    ]

    for i in range(work):
        m2   = rng.randrange(1, 1 << 128)
        init = rng.randrange(1, 1 << 128)
        rot  = 1 + (i * 7) % 31
        lines.append("")
        lines.append("    always_ff @(posedge clk or negedge rst_n) begin")
        lines.append(f"        if (!rst_n) hw_state[{i+1}] <= 128'h{init:032X};")
        lines.append(
            f"        else        hw_state[{i+1}] <= "
            f"(hw_state[{i}] * hw_state[{i}])"
            f" ^ {{hw_state[{i}][{31-rot}:0], hw_state[{i}][127:{128-rot}]}}"
            f" ^ 128'h{m2:032X};"
        )
        lines.append("    end")

    decl_block = "\n".join(lines)
    mix_expr   = (
        f"(hw_state[{work}][31:0] ^ hw_state[{work}][63:32]"
        f" ^ hw_state[{work}][95:64] ^ hw_state[{work}][127:96])"
    )
    return decl_block, mix_expr


# Match `assign <port> = <expr>;` for either of the two output port names
# the generators use today (out_y for most families, tap for bloat2 / churn
# / echo).  Captures the LHS prefix, the RHS expression, and the trailing
# semicolon so we can rebuild the line with an XOR-mix.
_OUT_RE = re.compile(
    r"(assign\s+(?:out_y|tap)\s*=\s*)([^;]+?)(\s*;)"
)


def inject_heavy_tail(unit_sv: str, work: int, rng: random.Random) -> str:
    """Patch a unit's SV text to include `work` heavy MAC stages.

    The decl block is inserted *before* the `assign out_y/tap = ...`
    line, so the assign that XORs in `hw_state[work]` always sees the
    variable already declared.  Falls back to inserting before
    `endmodule` if no matching assign is found (in which case the new
    state may DCE — a defensive path that shouldn't hit any current
    template).

    No-op when work <= 0.
    """
    if work <= 0:
        return unit_sv

    decl, mix = heavy_tail(work, rng)

    m = _OUT_RE.search(unit_sv)
    if m is None:
        # No matching assign — degrade gracefully and just append the
        # decl before endmodule.  qopt may DCE the unused state, but at
        # least the file still compiles.
        em = unit_sv.rfind("endmodule")
        if em == -1:
            return unit_sv
        return unit_sv[:em] + decl + "\n" + unit_sv[em:]

    start = m.start()
    end   = m.end()
    new_assign = f"{m.group(1)}({m.group(2)}) ^ {mix}{m.group(3)}"
    return unit_sv[:start] + decl + "\n" + new_assign + unit_sv[end:]
