class fw_proto_factory;
    static fw_proto_ctor m_ctors[string];
    static string        m_over[string];
    static string        m_type_of[string];     // full name -> type asked for

    static function void set_type_override(string base, string sub);
        m_over[base] = sub;
    endfunction

    static function fw_component create(string tn, string name, fw_component parent);
        string t = m_over.exists(tn) ? m_over[tn] : tn;
        fw_component c;
        if (!m_ctors.exists(t)) $fatal(1, "fw_proto_factory: %s is not registered", t);
        c = m_ctors[t].make(name, parent);
        m_type_of[c.get_full_name()] = tn;
        return c;
    endfunction

    // The type a component was created as ("" when not by the factory).
    static function string type_of(fw_component c);
        string n = c.get_full_name();
        return m_type_of.exists(n) ? m_type_of[n] : "";
    endfunction
endclass
