// One rule, attached in one place, in simulation: its instances (one per value
// of its variables seen, fw_rule_node) and its failures. Each failure names the
// place, the rule, the instance's key and the rule's message (the API event).
class fw_rule_set;
    string       m_where;
    fw_rule      m_proto;
    fw_rule_node m_root;
    bit          m_sigs[string];
    int unsigned n_fail, n_inst;
    string       m_fails[$];        // the first max_report
    int unsigned max_report = 10;
    bit          quiet;             // count, do not print (planted bugs)

    function new(fw_rule r, string where);
        m_where = where;
        m_proto = r;
        reset();
    endfunction

    // Back to the rule's initial state: a fresh instance tree.
    function void reset();
        fw_rule r = m_proto.create();
        r.m_pins = m_proto.m_pins;
        m_sigs.delete();
        m_fails.delete();
        n_fail = 0;
        n_inst = 1;
        m_root = r.new_node();
        m_root.init(this, r);
        m_sigs[r.sig()] = 1;
    endfunction

    function bit is_new(string sig);
        return !m_sigs.exists(sig);
    endfunction

    function void fail(fw_rule r, string msg);
        string s = $sformatf("%0t %s: %s%s: %s", $time, m_where, r.m_name, r.keys(), msg);
        n_fail++;
        if (m_fails.size() < max_report) m_fails.push_back(s);
        if (!quiet && n_fail <= max_report) $display("[fw_rule] FAIL %s", s);
    endfunction
endclass
