// Auxiliary state of a rule (fw_count, fw_flag, fw_value, fw_any): the only state a
// rule in the restricted form may keep (abstractors.md §4a). Each piece registers
// with its rule when built, so a rule can be copied (fw_rule::copy_state) without
// naming its members.
virtual class fw_rule_state;
    pure virtual function void copy(fw_rule_state from);
endclass
