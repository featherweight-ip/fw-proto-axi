// A rule (design §3.5, abstractors.md §4a): a listener whose body states what must
// hold, in a restricted form:
//   chk(c, msg)                     immediate check; msg names the API event
//   fw_count, fw_flag, fw_value #(T) auxiliary state
//   fw_any #(T)                     quantified variables (is(x) only)
//   pure functions of the event's arguments and that state
// A protocol's rule base extends this and implements the protocol's listener
// interfaces (e.g. axi4_rule). A rule that needs anything else (queues, plain
// members) is free form (m_free_form): executable only, opaque to formal, and
// it may not have quantified variables (its state cannot be copied).
//
// In simulation a rule runs inside an fw_rule_set: one instance per value of its
// variables seen.
virtual class fw_rule;
    string        m_name;
    fw_rule_state m_state[$];
    fw_any_base   m_vars[$];
    // The events come from a pin monitor: a post is the handshake. A request
    // then counts at its post; from a proxy at its pre (a response may come
    // inside the request's call, design §3.4).
    bit           m_pins;
    bit           m_free_form;
    // Set by fw_rule_set / fw_rule_node:
    fw_rule_node  m_node;       // the node this instance belongs to
    bit           m_probe;      // the twin that finds new values; never reports
    bit           m_retired;    // takes no more events

    function new(string name);
        m_name = name;
    endfunction

    // A new instance of the same class, with the same constructor settings.
    pure virtual function fw_rule create();

    // The protocol's node: the fan-outs that deliver its listener calls.
    pure virtual function fw_rule_node new_node();

    function int unsigned add_state(fw_rule_state s);
        m_state.push_back(s);
        return m_state.size() - 1;
    endfunction

    function void add_var(fw_any_base a);
        m_vars.push_back(a);
    endfunction

    // The check: c must hold. Returns c.
    function bit chk(bit c, string msg);
        if (!c && !m_probe && m_node != null) m_node.m_set.fail(this, msg);
        return c;
    endfunction

    // Simulation only: this instance's key is discharged (e.g. its burst is
    // complete and checked); it takes no more events and is not created again.
    function void retire();
        if (!m_probe && !unbound()) begin
            m_retired = 1;
            m_node.m_n_retired++;
        end
    endfunction

    function bit unbound();
        foreach (m_vars[i]) if (!m_vars[i].m_bound) return 1;
        return 0;
    endfunction

    // "(id=3, j=*)", or "" with no variables.
    function string keys();
        string s;
        if (m_vars.size() == 0) return "";
        foreach (m_vars[i])
            s = {s, (i == 0) ? "" : ", ", m_vars[i].m_name, "=", m_vars[i].show()};
        return {"(", s, ")"};
    endfunction

    // The key of this instance with variable a bound to s.
    function string sig_with(fw_any_base a, string s);
        string r;
        foreach (m_vars[i]) r = {r, (m_vars[i] == a) ? s : m_vars[i].show(), ","};
        return r;
    endfunction

    function string sig();
        return sig_with(null, "");
    endfunction

    function void copy_state(fw_rule from);
        foreach (m_state[i]) m_state[i].copy(from.m_state[i]);
        m_pins = from.m_pins;
    endfunction
endclass
