// W grouping (brief §5): the write-data bursts follow AW order, burst j having
// exactly AWLEN+1 beats of AW j, WLAST on the last only. W may run ahead of its
// AW (A3.3.1); such data is checked when the AW comes. For every burst j. Binds
// the manager.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_w_burst #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    fw_any #(int unsigned) j;
    fw_count               n_aw, n_wb, beats;
    fw_value #(logic [7:0])  len;
    fw_flag                done;      // burst j's WLAST seen

    function new();
        super.new("w_burst");
        j = new(this, "burst");
        n_aw = new(this);
        n_wb = new(this);
        beats = new(this);
        len = new(this);
        done = new(this);
    endfunction

    virtual function fw_rule create();
        axi4_rule_w_burst #(P) r = new;
        return r;
    endfunction

    virtual function void on_aw(aw_t t);
        if (j.is(n_aw.v)) begin
            len.set(t.len);
            if (done.v) begin
                if (beats.v != int'(t.len) + 1)
                    void'(chk(0, $sformatf("aw %0d (id=%0h len=%0d): its write data, sent ahead, had %0d beats",
                                           n_aw.v, t.id, t.len, beats.v)));
                retire();
            end else if (beats.v > int'(t.len))
                void'(chk(0, $sformatf("aw %0d (id=%0h len=%0d): %0d beats of its data sent ahead without WLAST",
                                       n_aw.v, t.id, t.len, beats.v)));
        end
        n_aw.inc();
    endfunction

    virtual function void on_w(w_t t);
        if (j.is(n_wb.v)) begin
            beats.inc();
            if (len.valid) begin
                if (beats.v > int'(len.v) + 1 || t.last != (beats.v == int'(len.v) + 1))
                    void'(chk(0, $sformatf("w burst %0d, beat %0d of %0d: wlast=%0d",
                                           n_wb.v, beats.v, int'(len.v) + 1, t.last)));
            end else if (!t.last && beats.v >= 256)
                void'(chk(0, $sformatf("w burst %0d (ahead of its AW): %0d beats without WLAST",
                                       n_wb.v, beats.v)));
            if (t.last) begin
                done.set();
                if (len.valid) retire();
            end
        end
        if (t.last) n_wb.inc();
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
