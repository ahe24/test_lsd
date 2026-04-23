//==============================================================================
// lsd_sequences.sv  -  Stimulus sequences for the UVM environment
//==============================================================================
`ifndef LSD_SEQUENCES_SV
`define LSD_SEQUENCES_SV

package lsd_sequences;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import lsd_pkg::*;
    import lsd_uvm_pkg::*;

    // --------------- Smoke sequence ---------------
    class smoke_cmd_seq extends uvm_sequence#(lsd_cmd_tx);
        `uvm_object_utils(smoke_cmd_seq)
        function new(string name = "smoke_cmd_seq"); super.new(name); endfunction

        virtual task body();
            for (int k = 0; k < 16; k++) begin
                lsd_cmd_tx t = lsd_cmd_tx::type_id::create("t");
                start_item(t);
                if (!t.randomize() with {
                    sub inside {SUB_CNN, SUB_CRYPTO, SUB_GFX, SUB_CALU, SUB_ECCD};
                    op  inside {OP_WRITE, OP_KICK, OP_POLL};
                }) `uvm_error("RAND", "smoke randomize failed")
                finish_item(t);
            end
        endtask
    endclass

    // --------------- Heavy traffic sequence ---------------
    class heavy_cmd_seq extends uvm_sequence#(lsd_cmd_tx);
        rand int n_ops = 10000;
        `uvm_object_utils(heavy_cmd_seq)
        function new(string name = "heavy_cmd_seq"); super.new(name); endfunction

        virtual task body();
            int step;
            step = (n_ops >= 50) ? (n_ops / 20) : 1; // ~5% granularity
            `uvm_info("HEAVY", $sformatf("starting %0d random commands", n_ops), UVM_LOW)
            for (int k = 0; k < n_ops; k++) begin
                lsd_cmd_tx t = lsd_cmd_tx::type_id::create("t");
                start_item(t);
                if (!t.randomize()) `uvm_error("RAND", "heavy randomize failed")
                finish_item(t);
                if ((k % step) == 0 && k != 0) begin
                    `uvm_info("HEAVY", $sformatf("progress %0d/%0d (%0d%%)",
                              k, n_ops, (k*100)/n_ops), UVM_LOW)
                end
            end
            `uvm_info("HEAVY", $sformatf("completed %0d commands", n_ops), UVM_LOW)
        endtask
    endclass

    // --------------- Base block test (bmt) ---------------
    class bmt_cmd_seq extends uvm_sequence#(lsd_cmd_tx);
        `uvm_object_utils(bmt_cmd_seq)
        function new(string name = "bmt_cmd_seq"); super.new(name); endfunction

        virtual task body();
            // Drive a compact legality walk through each subsystem
            sub_e subs [5] = '{SUB_CNN, SUB_CRYPTO, SUB_GFX, SUB_CALU, SUB_ECCD};
            foreach (subs[i]) begin
                lsd_cmd_tx t = lsd_cmd_tx::type_id::create("t");
                start_item(t);
                if (!t.randomize() with {sub == subs[i]; op == OP_WRITE; addr < 32'h100;})
                    `uvm_error("RAND", "bmt write")
                finish_item(t);

                t = lsd_cmd_tx::type_id::create("t");
                start_item(t);
                if (!t.randomize() with {sub == subs[i]; op == OP_KICK;})
                    `uvm_error("RAND", "bmt kick")
                finish_item(t);
            end
        endtask
    endclass

    // --------------- Stream sequences ---------------
    class bulk_stream_seq extends uvm_sequence#(lsd_stream_tx);
        rand int n_beats = 1024;
        `uvm_object_utils(bulk_stream_seq)
        function new(string name = "bulk_stream_seq"); super.new(name); endfunction

        virtual task body();
            int step;
            step = (n_beats >= 50) ? (n_beats / 20) : 1;
            `uvm_info("STREAM", $sformatf("starting %0d stream beats", n_beats), UVM_LOW)
            for (int k = 0; k < n_beats; k++) begin
                lsd_stream_tx t = lsd_stream_tx::type_id::create("t");
                start_item(t);
                if (!t.randomize() with {sop == (k == 0); eop == (k == n_beats-1);})
                    `uvm_error("RAND", "bulk stream")
                finish_item(t);
                if ((k % step) == 0 && k != 0) begin
                    `uvm_info("STREAM", $sformatf("beat %0d/%0d (%0d%%)",
                              k, n_beats, (k*100)/n_beats), UVM_LOW)
                end
            end
            `uvm_info("STREAM", $sformatf("completed %0d beats", n_beats), UVM_LOW)
        endtask
    endclass
endpackage : lsd_sequences

`endif // LSD_SEQUENCES_SV
