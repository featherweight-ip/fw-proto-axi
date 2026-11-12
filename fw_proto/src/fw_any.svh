// A quantified variable (abstractors.md §4a): the rule must hold for every value
// of it. The rule only asks is(x), "is x the value?"; it never reads the value.
// Formal leaves the variable symbolic. Simulation runs one copy of the rule per
// value seen (fw_rule_node): an unbound copy stands for every value not seen
// yet, so is() is 0 there, and its probe twin turns each new x into a bound copy
// that then takes the same event.
class fw_any #(type T = int) extends fw_any_base;
    T            v;
    int unsigned m_idx;     // index in m_rule's state

    function new(fw_rule r, string name);
        m_rule = r;
        m_name = name;
        m_idx = r.add_state(this);
        r.add_var(this);
    endfunction

    function bit is(T x);
        if (m_bound) return x == v;
        if (m_rule.m_probe) begin
            string s = $sformatf("%0h", x);
            if (m_rule.m_node.m_set.is_new(m_rule.sig_with(this, s))) begin
                fw_rule     c = m_rule.m_node.spawn();
                fw_any #(T) a;
                $cast(a, c.m_state[m_idx]);
                a.v = x;
                a.m_bound = 1;
                m_rule.m_node.adopt(c);
            end
        end
        return 0;
    endfunction

    virtual function string show();
        return m_bound ? $sformatf("%0h", v) : "*";
    endfunction

    virtual function void copy(fw_rule_state from);
        fw_any #(T) f;
        $cast(f, from);
        v = f.v;
        m_bound = f.m_bound;
    endfunction
endclass
