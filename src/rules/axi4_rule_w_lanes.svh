// Narrow transfers (brief §4): WSTRB is high only on the byte lanes of the beat
// (A3.4.3), from its AW's address, size, length and burst type. Checked once the
// AW is known (not for beats that ran ahead of it). For every write-data burst j.
// Binds the manager.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_w_lanes #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    fw_any #(int unsigned) j;
    fw_count               n_aw, n_wb, beats;
    fw_value #(aw_t)         aw;

    function new();
        super.new("w_lanes");
        j = new(this, "burst");
        n_aw = new(this);
        n_wb = new(this);
        beats = new(this);
        aw = new(this);
    endfunction

    virtual function fw_rule create();
        axi4_rule_w_lanes #(P) r = new;
        return r;
    endfunction

    virtual function void on_aw(aw_t t);
        if (j.is(n_aw.v)) aw.set(t);
        n_aw.inc();
    endfunction

    virtual function void on_w(w_t t);
        if (j.is(n_wb.v)) begin
            if (aw.valid) begin
                strb_t m = lanes(axi4_addr64_t'(aw.v.addr), aw.v.size, aw.v.len, aw.v.burst, beats.v);
                if ((t.strb & ~m) != '0)
                    void'(chk(0, $sformatf("w burst %0d, beat %0d: wstrb %0h outside the beat's lanes %0h",
                                           n_wb.v, beats.v, t.strb, m)));
                if (t.last) retire();
            end
            beats.inc();
        end
        if (t.last) n_wb.inc();
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
