//==============================================================================
// lsd_tests.sv  -  UVM test classes
//
// Phase 1 partition-friendly TB: the DUT drives itself (see
// rtl/common/lsd_self_traffic.sv), so tests are simple objection-only
// timers controlling how long the simulation runs.  Sequence-driven
// stimulus comes back in Phase 2 alongside per-subsystem agents.
//==============================================================================
`ifndef LSD_TESTS_SV
`define LSD_TESTS_SV

package lsd_tests;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import lsd_pkg::*;
    import lsd_uvm_pkg::*;

    class lsd_smoke_test extends lsd_base_test;
        `uvm_component_utils(lsd_smoke_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #5us;
            phase.drop_objection(this);
        endtask
    endclass

    class lsd_bmt_test extends lsd_base_test;
        `uvm_component_utils(lsd_bmt_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #2us;
            phase.drop_objection(this);
        endtask
    endclass

    class lsd_stress_test extends lsd_base_test;
        `uvm_component_utils(lsd_stress_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #100us;
            phase.drop_objection(this);
        endtask
    endclass
endpackage : lsd_tests

`endif // LSD_TESTS_SV
