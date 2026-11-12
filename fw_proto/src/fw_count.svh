// A counter (rule state).
class fw_count extends fw_rule_state;
    int unsigned v;

    function new(fw_rule r);
        void'(r.add_state(this));
    endfunction

    function void inc();
        v++;
    endfunction

    function void dec();
        v--;
    endfunction

    virtual function void copy(fw_rule_state from);
        fw_count f;
        $cast(f, from);
        v = f.v;
    endfunction
endclass
