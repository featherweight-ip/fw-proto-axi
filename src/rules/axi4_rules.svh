// The AXI4 rules (brief §5), attached in one place, in simulation. Events come in
// through req and rsp: add them to a proxy's or a pin monitor's listeners, or
// register them by path for an abstractor (axi4_observers). `pins` says the
// events come from a pin monitor (fw_rule::m_pins; it also adds rv_hold).
//
//   resp_match   correspondence: B and R only for an outstanding AW / AR, by ID
//   r_burst      R grouping; same-ID read order
//   w_burst      W grouping, in AW order
//   b_order      B after its AW and its last W; same-ID write order
//   burst_legal  AW / AR legal (A3.4.1), exclusive accesses too (A7.2.4)
//   w_lanes      WSTRB only on the beat's lanes
//   capacity     outstanding writes / reads within the declared capacity
//   exclusive    EXOKAY only for an exclusive access (free form)
//   rv_hold      VALID held, payload stable, until the handshake (pins only)
//
// Each failure is reported once ("[fw_rule] FAIL <time> <where>: <rule>(<key>):
// <event>"), and counted per rule.
class axi4_rules #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    axi4_req_if_listener_fanout #(P) req = new;
    axi4_rsp_if_listener_fanout #(P) rsp = new;
    string      where;
    bit         pins;
    fw_rule_set sets[$];

    function new(string at, bit at_pins = 0, int unsigned max_wr = 0, int unsigned max_rd = 0);
        axi4_rule_resp_match #(P)  r_match = new;
        axi4_rule_r_burst #(P)     r_rb = new;
        axi4_rule_w_burst #(P)     r_wb = new;
        axi4_rule_b_order #(P)     r_bo = new;
        axi4_rule_burst_legal #(P) r_bl = new;
        axi4_rule_w_lanes #(P)     r_wl = new;
        axi4_rule_capacity #(P)    r_cap = new(max_wr, max_rd);
        axi4_rule_exclusive #(P)   r_ex = new;
        where = at;
        pins = at_pins;
        add(r_match);
        add(r_rb);
        add(r_wb);
        add(r_bo);
        add(r_bl);
        add(r_wl);
        add(r_cap);
        add(r_ex);
        if (pins) begin
            axi4_rule_rv_hold #(P) r_rv = new;
            add(r_rv);
        end
    endfunction

    function void add(axi4_rule #(P) r);
        fw_rule_set s;
        r.m_pins = pins;
        s = new(r, where);
        sets.push_back(s);
        listen(s);
    endfunction

    local function void listen(fw_rule_set s);
        axi4_rule_node #(P) n;
        $cast(n, s.m_root);
        req.add_listener(n.req);
        rsp.add_listener(n.rsp);
    endfunction

    // Every rule back to its initial state, its failures cleared.
    function void reset();
        req.m_listeners.delete();
        rsp.m_listeners.delete();
        foreach (sets[i]) begin
            sets[i].reset();
            listen(sets[i]);
        end
    endfunction

    // Count failures without printing them (planted bugs).
    function void set_quiet(bit q);
        foreach (sets[i]) sets[i].quiet = q;
    endfunction

    function int unsigned n_fail();
        int unsigned n = 0;
        foreach (sets[i]) n += sets[i].n_fail;
        return n;
    endfunction

    function int unsigned n_fail_of(string rule);
        foreach (sets[i]) if (sets[i].m_proto.m_name == rule) return sets[i].n_fail;
        return 0;
    endfunction

    // "rule:n, ..." for the rules that failed; "" if none did.
    function string failed();
        string s;
        foreach (sets[i]) if (sets[i].n_fail != 0)
            s = {s, (s == "") ? "" : ", ", $sformatf("%s:%0d", sets[i].m_proto.m_name, sets[i].n_fail)};
        return s;
    endfunction

    // The first failure's message, "" if none.
    function string first();
        foreach (sets[i]) if (sets[i].m_fails.size() != 0) return sets[i].m_fails[0];
        return "";
    endfunction

    // Rule instances in simulation (one per key seen), all rules.
    function int unsigned n_inst();
        int unsigned n = 0;
        foreach (sets[i]) n += sets[i].n_inst;
        return n;
    endfunction
endclass
