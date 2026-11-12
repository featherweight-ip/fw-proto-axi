// B after its write (brief §5, happens-before) and same-ID write order: the j-th
// B with ID k answers the j-th write with ID k and comes after that write's AW and
// its last W beat. Write-data bursts follow AW order, so that write's data is the
// g-th burst, g its position among all AWs. For every ID k and write j of that
// ID. (Which of two writes of one ID a B answers shows only through this
// ordering.) Binds the subordinate.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_b_order #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    fw_any #(id_t)         k;
    fw_any #(int unsigned) j;
    fw_count               n_awk, n_aw, n_wb, n_bk;
    fw_value #(int unsigned) g;

    function new();
        super.new("b_order");
        k = new(this, "id");
        j = new(this, "write");
        n_awk = new(this);
        n_aw = new(this);
        n_wb = new(this);
        n_bk = new(this);
        g = new(this);
    endfunction

    virtual function fw_rule create();
        axi4_rule_b_order #(P) r = new;
        return r;
    endfunction

    virtual function void on_aw(aw_t t);
        if (k.is(t.id)) begin
            if (j.is(n_awk.v)) g.set(n_aw.v);
            n_awk.inc();
        end
        n_aw.inc();
    endfunction

    virtual function void on_w(w_t t);
        if (t.last) n_wb.inc();
    endfunction

    virtual function void on_b(b_t t);
        if (!k.is(t.id)) return;
        // Without its AW, the B is resp_match's to report.
        if (j.is(n_bk.v) && g.valid) begin
            if (n_wb.v <= g.v)
                void'(chk(0, $sformatf("b id=%0h (write %0d of this ID): before the last W beat of its write",
                                       t.id, n_bk.v)));
            retire();
        end
        n_bk.inc();
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
