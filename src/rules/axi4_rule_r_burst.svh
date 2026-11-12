// R grouping and same-ID read order (brief §5): the reads of one ID are answered
// in AR order, each with exactly ARLEN+1 beats, RLAST on the last only. For every
// ID k and every read j of that ID. (Two reads of one ID answered in the other
// order show here only if their lengths differ; with equal lengths only the data
// tells, which is the data-integrity rule's job.) Binds the subordinate.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_r_burst #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    fw_any #(id_t)         k;
    fw_any #(int unsigned) j;
    fw_count               n_ar, n_rb, beats;
    fw_value #(logic [7:0])  len;

    function new();
        super.new("r_burst");
        k = new(this, "id");
        j = new(this, "read");
        n_ar = new(this);
        n_rb = new(this);
        beats = new(this);
        len = new(this);
    endfunction

    virtual function fw_rule create();
        axi4_rule_r_burst #(P) r = new;
        return r;
    endfunction

    virtual function void on_ar(ar_t t);
        if (!k.is(t.id)) return;
        if (j.is(n_ar.v)) len.set(t.len);
        n_ar.inc();
    endfunction

    virtual function void on_r(r_t t);
        if (!k.is(t.id)) return;
        // Without its AR, the beat is resp_match's to report.
        if (j.is(n_rb.v) && len.valid) begin
            beats.inc();
            if (beats.v > int'(len.v) + 1 || t.last != (beats.v == int'(len.v) + 1))
                void'(chk(0, $sformatf("r id=%0h, read %0d of this ID, beat %0d of %0d: rlast=%0d",
                                       t.id, n_rb.v, beats.v, int'(len.v) + 1, t.last)));
            if (t.last) retire();
        end
        if (t.last) n_rb.inc();
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
