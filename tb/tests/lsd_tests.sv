//==============================================================================
// lsd_tests.sv  -  UVM test classes
//==============================================================================
`ifndef LSD_TESTS_SV
`define LSD_TESTS_SV

package lsd_tests;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import lsd_pkg::*;
    import lsd_uvm_pkg::*;
    import lsd_sequences::*;

    class lsd_smoke_test extends lsd_base_test;
        `uvm_component_utils(lsd_smoke_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual task run_phase(uvm_phase phase);
            smoke_cmd_seq     cs;
            bulk_stream_seq   ss;
            phase.raise_objection(this);
            cs = smoke_cmd_seq  ::type_id::create("cs");
            ss = bulk_stream_seq::type_id::create("ss");
            fork
                cs.start(env.cmd_ag.sqr);
                ss.start(env.in_ag.sqr);
            join
            #1us;
            phase.drop_objection(this);
        endtask
    endclass

    class lsd_bmt_test extends lsd_base_test;
        `uvm_component_utils(lsd_bmt_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        virtual task run_phase(uvm_phase phase);
            bmt_cmd_seq cs;
            phase.raise_objection(this);
            cs = bmt_cmd_seq::type_id::create("cs");
            cs.start(env.cmd_ag.sqr);
            #500ns;
            phase.drop_objection(this);
        endtask
    endclass

    class lsd_stress_test extends lsd_base_test;
        `uvm_component_utils(lsd_stress_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        virtual task run_phase(uvm_phase phase);
            heavy_cmd_seq   cs;
            bulk_stream_seq ss;
            phase.raise_objection(this);
            cs = heavy_cmd_seq  ::type_id::create("cs");
            ss = bulk_stream_seq::type_id::create("ss");
            ss.n_beats = 16384;
            fork
                cs.start(env.cmd_ag.sqr);
                ss.start(env.in_ag.sqr);
            join
            #10us;
            phase.drop_objection(this);
        endtask
    endclass
endpackage : lsd_tests

`endif // LSD_TESTS_SV
