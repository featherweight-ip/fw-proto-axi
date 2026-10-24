// Scripted L1 endpoints, one per link side. Each holds its side's
// socket/mirror (`axi`), sends by calling `axi.t.<ch>(beat)` and queues every
// inbound beat in a per-channel inbox. One inbox per channel, filled from
// that channel's imp alone, so the endpoint never couples channels.
//
// They are what L1 tests drive, and a starting point for anything that
// wants to script an AXI4 manager or subordinate beat by beat.

// A manager at L1: holds the link's socket.
class axi4_l1_mgr_ep extends fw_component;
    `FW_AXI4_MGR_SOCKET_IMP(axi4_l1_mgr_ep, axi);
    axi4_l1_inbox #(axi4_b_beat_t) b_in = new;
    axi4_l1_inbox #(axi4_r_beat_t) r_in = new;

    function new(string name, fw_component parent); super.new(name, parent); endfunction
    function void build(); axi = new(this); endfunction

    task axi_b(input axi4_b_beat_t f); b_in.put(f); endtask
    task axi_r(input axi4_r_beat_t f); r_in.put(f); endtask

    function void clear(); b_in.clear(); r_in.clear(); endfunction
    function bit idle(); return b_in.size() == 0 && r_in.size() == 0; endfunction
endclass

// A subordinate at L1: holds the link's mirror.
class axi4_l1_sub_ep extends fw_component;
    `FW_AXI4_SUB_MIRROR_IMP(axi4_l1_sub_ep, axi);
    axi4_l1_inbox #(axi4_aw_beat_t) aw_in = new;
    axi4_l1_inbox #(axi4_w_beat_t)  w_in  = new;
    axi4_l1_inbox #(axi4_ar_beat_t) ar_in = new;

    function new(string name, fw_component parent); super.new(name, parent); endfunction
    function void build(); axi = new(this); endfunction

    task axi_aw(input axi4_aw_beat_t f); aw_in.put(f); endtask
    task axi_w(input axi4_w_beat_t f);   w_in.put(f);  endtask
    task axi_ar(input axi4_ar_beat_t f); ar_in.put(f); endtask

    function void clear(); aw_in.clear(); w_in.clear(); ar_in.clear(); endfunction
    function bit idle(); return aw_in.size() == 0 && w_in.size() == 0 && ar_in.size() == 0; endfunction
endclass
