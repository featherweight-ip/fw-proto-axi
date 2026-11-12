// A flag (rule state): set by one event, tested at another (happens-before).
class fw_flag extends fw_rule_state;
    bit v;

    function new(fw_rule r);
        void'(r.add_state(this));
    endfunction

    function void set();
        v = 1;
    endfunction

    function void clr();
        v = 0;
    endfunction

    virtual function void copy(fw_rule_state from);
        fw_flag f;
        $cast(f, from);
        v = f.v;
    endfunction
endclass
