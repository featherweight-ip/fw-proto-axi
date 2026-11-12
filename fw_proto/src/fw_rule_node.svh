// Simulation of a rule with unbound variables: tmpl stands for every value not
// seen yet; probe, a twin in the same state, takes each event first and turns a
// new value into a copy of tmpl (still before the event) bound to it, a kid. The
// protocol's subclass holds the fan-outs that deliver an event to
// [probe, tmpl, kids], in that order, so a kid added by the probe takes the same
// event. A kid with variables still unbound is a node itself.
virtual class fw_rule_node;
    fw_rule_set  m_set;
    fw_rule      tmpl, probe;
    fw_rule      m_kids[$];
    fw_rule_node m_subs[$];
    int unsigned m_n_retired;

    // Fan-outs: [probe (if any), tmpl, kids].
    pure virtual function void fan_out();
    pure virtual function void add_leaf(fw_rule r);
    pure virtual function void add_sub(fw_rule_node n);
    pure virtual function void clear_kids();

    function void init(fw_rule_set s, fw_rule t);
        if (t.m_free_form && t.m_vars.size() != 0)
            $fatal(1, "%s: a free-form rule cannot have quantified variables", t.m_name);
        m_set = s;
        tmpl = t;
        t.m_node = this;
        if (t.unbound()) begin
            probe = t.create();
            probe.copy_state(t);
            probe.m_probe = 1;
            probe.m_node = this;
        end
        fan_out();
    endfunction

    // A copy of tmpl as it is now.
    function fw_rule spawn();
        fw_rule c = tmpl.create();
        c.copy_state(tmpl);
        return c;
    endfunction

    function void adopt(fw_rule c);
        m_set.m_sigs[c.sig()] = 1;
        m_set.n_inst++;
        if (c.unbound()) begin
            fw_rule_node n = c.new_node();
            n.init(m_set, c);
            m_subs.push_back(n);
            add_sub(n);
        end else begin
            sweep();
            c.m_node = this;
            m_kids.push_back(c);
            add_leaf(c);
        end
    endfunction

    // Drop retired kids once they are many. Called from the probe, before the
    // kids' fan-out takes the event.
    function void sweep();
        fw_rule live[$];
        if (m_n_retired < 64 || 2 * m_n_retired < m_kids.size()) return;
        foreach (m_kids[i]) if (!m_kids[i].m_retired) live.push_back(m_kids[i]);
        m_kids = live;
        m_n_retired = 0;
        clear_kids();
        foreach (m_subs[i]) add_sub(m_subs[i]);
        foreach (m_kids[i]) add_leaf(m_kids[i]);
    endfunction

    // Every instance that reports: tmpl, the kids, and the sub-nodes'.
    function void instances(ref fw_rule q[$]);
        q.push_back(tmpl);
        foreach (m_kids[i]) if (!m_kids[i].m_retired) q.push_back(m_kids[i]);
        foreach (m_subs[i]) m_subs[i].instances(q);
    endfunction
endclass
