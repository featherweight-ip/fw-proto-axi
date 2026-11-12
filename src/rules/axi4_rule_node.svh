// fw_rule_node for the AXI4 rules: the fan-outs of both channel listeners.
// Attach req and rsp of a set's root node where events come from.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_node #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_rule_node;
    axi4_req_if_listener_fanout #(P) req = new, req_kids = new;
    axi4_rsp_if_listener_fanout #(P) rsp = new, rsp_kids = new;

    virtual function void fan_out();
        axi4_rule #(P) r;
        if (probe != null) begin
            $cast(r, probe);
            req.add_listener(r);
            rsp.add_listener(r);
        end
        $cast(r, tmpl);
        req.add_listener(r);
        rsp.add_listener(r);
        req.add_listener(req_kids);
        rsp.add_listener(rsp_kids);
    endfunction

    virtual function void add_leaf(fw_rule c);
        axi4_rule #(P) r;
        $cast(r, c);
        req_kids.add_listener(r);
        rsp_kids.add_listener(r);
    endfunction

    virtual function void add_sub(fw_rule_node n);
        axi4_rule_node #(P) a;
        $cast(a, n);
        req_kids.add_listener(a.req);
        rsp_kids.add_listener(a.rsp);
    endfunction

    virtual function void clear_kids();
        req_kids.m_listeners.delete();
        rsp_kids.m_listeners.delete();
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
