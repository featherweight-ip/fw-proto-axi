// Outstanding capacity (brief §5): at most max_wr writes (AW accepted, B not yet)
// and max_rd reads (AR accepted, last R beat not yet) at once; 0 is no limit. The
// capacity is a declared fact of the port (brief §4: the API's outstanding count,
// or the IP's own parameter), given when the rules are attached. Binds the
// manager.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_capacity #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    int unsigned max_wr, max_rd;
    fw_count     n_aw, n_b, n_ar, n_rl;

    function new(int unsigned wr = 0, int unsigned rd = 0);
        super.new("capacity");
        max_wr = wr;
        max_rd = rd;
        n_aw = new(this);
        n_b = new(this);
        n_ar = new(this);
        n_rl = new(this);
    endfunction

    virtual function fw_rule create();
        axi4_rule_capacity #(P) r = new(max_wr, max_rd);
        return r;
    endfunction

    virtual function void on_aw(aw_t t);
        if (max_wr != 0 && n_aw.v - n_b.v >= max_wr)
            void'(chk(0, $sformatf("aw id=%0h: %0d writes outstanding already, capacity %0d",
                                   t.id, n_aw.v - n_b.v, max_wr)));
        n_aw.inc();
    endfunction

    virtual function void on_ar(ar_t t);
        if (max_rd != 0 && n_ar.v - n_rl.v >= max_rd)
            void'(chk(0, $sformatf("ar id=%0h: %0d reads outstanding already, capacity %0d",
                                   t.id, n_ar.v - n_rl.v, max_rd)));
        n_ar.inc();
    endfunction

    virtual function void on_b(b_t t);
        if (n_b.v < n_aw.v) n_b.inc();
    endfunction

    virtual function void on_r(r_t t);
        if (t.last && n_rl.v < n_ar.v) n_rl.inc();
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
