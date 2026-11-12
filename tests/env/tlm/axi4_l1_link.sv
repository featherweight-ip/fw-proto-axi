// The L1 link, view `tlm` (see axi4_l1_cell.sv for the members every view
// has): the manager's axi4_req_if is a proxy onto the subordinate's inbox and
// the subordinate's axi4_rsp_if a proxy onto the manager's. Zero time; the
// proxies' listeners are the observation. No pins, so no knobs and no checker.
module axi4_l1_link
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    bit aclk = 0;
    always #5 aclk = ~aclk;

    axi4_req_if_inbox #(P) sub_in = new;
    axi4_rsp_if_inbox #(P) mgr_in = new;
    axi4_req_if_proxy #(P) req_px = new(sub_in);
    axi4_rsp_if_proxy #(P) rsp_px = new(mgr_in);
    axi4_req_if #(P)       req = req_px;
    axi4_rsp_if #(P)       rsp = rsp_px;
    bit                    up;

    initial up = 1;

    function void add_req_listener(axi4_req_if_listener #(P) l); req_px.add_listener(l); endfunction
    function void add_rsp_listener(axi4_rsp_if_listener #(P) l); rsp_px.add_listener(l); endfunction
    // Replace the far ends (the inboxes) with other receivers, e.g. L2 adapters.
    function void attach(axi4_rsp_if #(P) mgr_end, axi4_req_if #(P) sub_end);
        rsp_px.m_target = mgr_end;
        req_px.m_target = sub_end;
    endfunction
    function bit set_knob(string path, int unsigned v); return 0; endfunction
    // The listeners' events come from proxies (rules count a request at its pre).
    function bit at_pins(); return 0; endfunction
    // Segment A's checker counts (manager side, subordinate side): no checker here.
    function void chk_counts(output int unsigned m, output int unsigned s); m = 0; s = 0; endfunction
    function bit has_checker(); return 0; endfunction
    function string errors(); return ""; endfunction
    task settle(); endtask
endmodule
