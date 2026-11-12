// A bounded register (rule state; fw-hdl has an fw_reg, its register model): one value captured from an event, e.g. the
// length of the burst a quantified index picks. `valid` once set.
class fw_value #(type T = int) extends fw_rule_state;
    T   v;
    bit valid;

    function new(fw_rule r);
        void'(r.add_state(this));
    endfunction

    function void set(T x);
        v = x;
        valid = 1;
    endfunction

    function void clr();
        valid = 0;
    endfunction

    virtual function void copy(fw_rule_state from);
        fw_value #(T) f;
        $cast(f, from);
        v = f.v;
        valid = f.valid;
    endfunction
endclass
