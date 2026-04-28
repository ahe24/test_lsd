//==============================================================================
// lsd_uvm_pkg.sv  -  UVM package for the LSD testbench
//==============================================================================
`ifndef LSD_UVM_PKG_SV
`define LSD_UVM_PKG_SV

package lsd_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import lsd_pkg::*;

    // Decorator macros that create uniquely-named write_<suffix> hooks for
    // each analysis_imp. Required when a single subscriber (the scoreboard)
    // wants to receive multiple analysis transactions of different types —
    // otherwise every imp tries to dispatch to a single write(T) method and
    // UVM fails type-checking at elaboration (vsim-8754).
    `uvm_analysis_imp_decl(_cmd)
    `uvm_analysis_imp_decl(_stream_in)
    `uvm_analysis_imp_decl(_stream_out)

    // ---------------- Transactions ----------------
    class lsd_cmd_tx extends uvm_sequence_item;
        rand tag_t      tag;
        rand sub_e      sub;
        rand op_e       op;
        rand addr_t     addr;
        rand data_t     data;
        rand len_t      len;
        rsp_t           rsp;
        bit             rsp_err;

        `uvm_object_utils_begin(lsd_cmd_tx)
            `uvm_field_int(tag,  UVM_ALL_ON)
            `uvm_field_enum(sub_e, sub, UVM_ALL_ON)
            `uvm_field_enum(op_e,  op,  UVM_ALL_ON)
            `uvm_field_int(addr, UVM_ALL_ON)
            `uvm_field_int(data, UVM_ALL_ON)
            `uvm_field_int(len,  UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "lsd_cmd_tx");
            super.new(name);
        endfunction
    endclass

    class lsd_stream_tx extends uvm_sequence_item;
        rand bit [511:0] data;
        rand bit         sop;
        rand bit         eop;
        rand bit [63:0]  keep;

        `uvm_object_utils_begin(lsd_stream_tx)
            `uvm_field_int(data, UVM_ALL_ON)
            `uvm_field_int(sop,  UVM_ALL_ON)
            `uvm_field_int(eop,  UVM_ALL_ON)
            `uvm_field_int(keep, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "lsd_stream_tx");
            super.new(name);
        endfunction
    endclass

    // ---------------- Config object ----------------
    class lsd_env_cfg extends uvm_object;
        virtual lsd_cmd_if    vif_cmd;
        virtual lsd_stream_if vif_in;
        virtual lsd_stream_if vif_out;

        bit enable_scoreboard = 1'b1;
        bit enable_coverage   = 1'b1;

        `uvm_object_utils(lsd_env_cfg)
        function new(string name = "lsd_env_cfg");
            super.new(name);
        endfunction
    endclass

    // ---------------- Driver ----------------
    class lsd_cmd_driver extends uvm_driver#(lsd_cmd_tx);
        virtual lsd_cmd_if vif;
        `uvm_component_utils(lsd_cmd_driver)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual task run_phase(uvm_phase phase);
            vif.cmd_valid <= 1'b0;
            vif.rsp_ready <= 1'b1;
            forever begin
                lsd_cmd_tx t;
                seq_item_port.get_next_item(t);
                @(posedge vif.clk);
                vif.cmd_valid <= 1'b1;
                vif.cmd.tag   <= t.tag;
                vif.cmd.sub   <= t.sub;
                vif.cmd.op    <= t.op;
                vif.cmd.addr  <= t.addr;
                vif.cmd.data  <= t.data;
                vif.cmd.len   <= t.len;
                do @(posedge vif.clk); while (!vif.cmd_ready);
                vif.cmd_valid <= 1'b0;
                seq_item_port.item_done();
            end
        endtask
    endclass

    class lsd_stream_driver extends uvm_driver#(lsd_stream_tx);
        virtual lsd_stream_if vif;
        `uvm_component_utils(lsd_stream_driver)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual task run_phase(uvm_phase phase);
            vif.valid <= 1'b0;
            forever begin
                lsd_stream_tx t;
                seq_item_port.get_next_item(t);
                @(posedge vif.clk);
                vif.valid <= 1'b1;
                vif.data  <= t.data;
                vif.sop   <= t.sop;
                vif.eop   <= t.eop;
                vif.keep  <= t.keep;
                do @(posedge vif.clk); while (!vif.ready);
                vif.valid <= 1'b0;
                seq_item_port.item_done();
            end
        endtask
    endclass

    // ---------------- Monitor ----------------
    class lsd_cmd_monitor extends uvm_monitor;
        virtual lsd_cmd_if vif;
        uvm_analysis_port#(lsd_cmd_tx) ap;
        `uvm_component_utils(lsd_cmd_monitor)

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        virtual task run_phase(uvm_phase phase);
            forever begin
                @(posedge vif.clk);
                if (vif.rsp_valid && vif.rsp_ready) begin
                    lsd_cmd_tx t = lsd_cmd_tx::type_id::create("t");
                    t.tag      = vif.rsp.tag;
                    t.sub      = vif.rsp.sub;
                    t.data     = vif.rsp.data;
                    t.rsp_err  = vif.rsp.err;
                    ap.write(t);
                end
            end
        endtask
    endclass

    class lsd_stream_monitor extends uvm_monitor;
        virtual lsd_stream_if vif;
        uvm_analysis_port#(lsd_stream_tx) ap;
        `uvm_component_utils(lsd_stream_monitor)
        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction
        virtual task run_phase(uvm_phase phase);
            forever begin
                @(posedge vif.clk);
                if (vif.valid && vif.ready) begin
                    lsd_stream_tx t = lsd_stream_tx::type_id::create("t");
                    t.data = vif.data;
                    t.sop  = vif.sop;
                    t.eop  = vif.eop;
                    t.keep = vif.keep;
                    ap.write(t);
                end
            end
        endtask
    endclass

    // ---------------- Agents ----------------
    class lsd_cmd_agent extends uvm_agent;
        uvm_sequencer#(lsd_cmd_tx) sqr;
        lsd_cmd_driver             drv;
        lsd_cmd_monitor            mon;
        virtual lsd_cmd_if         vif;

        `uvm_component_utils(lsd_cmd_agent)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            sqr = uvm_sequencer#(lsd_cmd_tx)::type_id::create("sqr", this);
            drv = lsd_cmd_driver ::type_id::create("drv", this);
            mon = lsd_cmd_monitor::type_id::create("mon", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
            drv.vif = vif;
            mon.vif = vif;
        endfunction
    endclass

    class lsd_stream_agent extends uvm_agent;
        uvm_sequencer#(lsd_stream_tx) sqr;
        lsd_stream_driver             drv;
        lsd_stream_monitor            mon;
        virtual lsd_stream_if         vif;

        `uvm_component_utils(lsd_stream_agent)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            sqr = uvm_sequencer#(lsd_stream_tx)::type_id::create("sqr", this);
            drv = lsd_stream_driver ::type_id::create("drv", this);
            mon = lsd_stream_monitor::type_id::create("mon", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
            drv.vif = vif;
            mon.vif = vif;
        endfunction
    endclass

    // ---------------- Scoreboard ----------------
    class lsd_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(lsd_scoreboard)
        // Each imp uses a different decorator so the three write_* methods
        // are distinct and each has its own typed signature.
        uvm_analysis_imp_cmd       #(lsd_cmd_tx,    lsd_scoreboard) cmd_ap;
        uvm_analysis_imp_stream_in #(lsd_stream_tx, lsd_scoreboard) stream_in_ap;
        uvm_analysis_imp_stream_out#(lsd_stream_tx, lsd_scoreboard) stream_out_ap;

        int unsigned n_cmds;
        int unsigned n_errs;
        int unsigned n_in_beats;
        int unsigned n_out_beats;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cmd_ap         = new("cmd_ap",        this);
            stream_in_ap   = new("stream_in_ap",  this);
            stream_out_ap  = new("stream_out_ap", this);
        endfunction

        function void write_cmd(lsd_cmd_tx t);
            n_cmds++;
            if (t.rsp_err) n_errs++;
        endfunction

        function void write_stream_in(lsd_stream_tx t);
            n_in_beats++;
        endfunction

        function void write_stream_out(lsd_stream_tx t);
            n_out_beats++;
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SCB", $sformatf("cmds=%0d errs=%0d in_beats=%0d out_beats=%0d",
                                       n_cmds, n_errs, n_in_beats, n_out_beats), UVM_LOW)
        endfunction
    endclass

    // ---------------- Environment ----------------
    class lsd_env extends uvm_env;
        lsd_env_cfg     cfg;
        lsd_cmd_agent   cmd_ag;
        lsd_stream_agent in_ag;
        lsd_stream_agent out_ag;
        lsd_scoreboard  scb;

        `uvm_component_utils(lsd_env)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(lsd_env_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("CFG", "env config missing")
            cmd_ag = lsd_cmd_agent ::type_id::create("cmd_ag", this);
            in_ag  = lsd_stream_agent::type_id::create("in_ag", this);
            out_ag = lsd_stream_agent::type_id::create("out_ag", this);
            scb    = lsd_scoreboard ::type_id::create("scb", this);
            cmd_ag.vif = cfg.vif_cmd;
            in_ag.vif  = cfg.vif_in;
            out_ag.vif = cfg.vif_out;
        endfunction

        function void connect_phase(uvm_phase phase);
            cmd_ag.mon.ap.connect(scb.cmd_ap);
            in_ag.mon.ap.connect(scb.stream_in_ap);
            out_ag.mon.ap.connect(scb.stream_out_ap);
        endfunction
    endclass

    // ---------------- Base test ----------------
    //
    // Phase 1 (partition-friendly RTL): the DUT generates its own traffic
    // internally, so the testbench owns no virtual interfaces and no env
    // is built.  The base test exists only as a UVM container so the
    // existing run flow (raise/drop_objection, reporting, factory) keeps
    // working — useful real per-subsystem agents will land in Phase 2.
    //
    // The lsd_env / agents / scoreboard classes above remain compiled (they
    // are cheap and inflate the build footprint the project deliberately
    // wants) but are not instantiated.
    class lsd_base_test extends uvm_test;
        `uvm_component_utils(lsd_base_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        // No build_phase override: nothing to wire when the DUT is self-driven.
    endclass

endpackage : lsd_uvm_pkg

`endif // LSD_UVM_PKG_SV
