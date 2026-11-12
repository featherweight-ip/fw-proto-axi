// Correspondence (brief §5): a B only for an outstanding write with its ID (AW
// accepted, B not yet), an R beat only for an outstanding read with its ID (AR
// accepted, its last R beat not yet). For every ID k. Binds the subordinate.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_resp_match #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    fw_any #(id_t) k;
    fw_count       n_aw, n_b, n_ar, n_rl;

    function new();
        super.new("resp_match");
        k = new(this, "id");
        n_aw = new(this);
        n_b = new(this);
        n_ar = new(this);
        n_rl = new(this);
    endfunction

    virtual function fw_rule create();
        axi4_rule_resp_match #(P) r = new;
        return r;
    endfunction

    virtual function void on_aw(aw_t t);
        if (k.is(t.id)) n_aw.inc();
    endfunction

    virtual function void on_ar(ar_t t);
        if (k.is(t.id)) n_ar.inc();
    endfunction

    virtual function void on_b(b_t t);
        if (!k.is(t.id)) return;
        if (chk(n_b.v < n_aw.v, $sformatf("b id=%0h: no write outstanding with this ID", t.id)))
            n_b.inc();
    endfunction

    virtual function void on_r(r_t t);
        if (!k.is(t.id)) return;
        if (chk(n_rl.v < n_ar.v, $sformatf("r id=%0h: no read outstanding with this ID", t.id))
            && t.last)
            n_rl.inc();
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
