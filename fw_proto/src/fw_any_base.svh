// The type-free part of fw_any: what fw_rule needs to name and copy its
// variables.
virtual class fw_any_base extends fw_rule_state;
    fw_rule      m_rule;
    string       m_name;
    bit          m_bound;

    // The value, or "*" while unbound.
    pure virtual function string show();
endclass
