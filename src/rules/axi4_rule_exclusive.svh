// Exclusive access (brief §5): EXOKAY only in answer to an exclusive access
// (A7.2), on B and on every R beat. Free form, the escape hatch: per-ID queues of
// the outstanding accesses' AxLOCK, so executable only and opaque to formal.
// Which access a response answers is the oldest outstanding one with its ID; an
// unmatched response is resp_match's to report. The legality of the exclusive
// access itself is burst_legal's. Binds the subordinate.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_exclusive #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    id_t m_wid[$], m_rid[$];
    bit  m_wlk[$], m_rlk[$];

    function new();
        super.new("exclusive");
        m_free_form = 1;
    endfunction

    virtual function fw_rule create();
        axi4_rule_exclusive #(P) r = new;
        return r;
    endfunction

    virtual function void on_aw(aw_t t);
        m_wid.push_back(t.id);
        m_wlk.push_back(t.lock);
    endfunction

    virtual function void on_ar(ar_t t);
        m_rid.push_back(t.id);
        m_rlk.push_back(t.lock);
    endfunction

    virtual function void on_b(b_t t);
        foreach (m_wid[i]) if (m_wid[i] == t.id) begin
            if (t.resp == AXI4_RESP_EXOKAY && !m_wlk[i])
                void'(chk(0, $sformatf("b id=%0h: EXOKAY for a write that is not exclusive", t.id)));
            m_wid.delete(i);
            m_wlk.delete(i);
            return;
        end
    endfunction

    virtual function void on_r(r_t t);
        foreach (m_rid[i]) if (m_rid[i] == t.id) begin
            if (t.resp == AXI4_RESP_EXOKAY && !m_rlk[i])
                void'(chk(0, $sformatf("r id=%0h: EXOKAY for a read that is not exclusive", t.id)));
            if (t.last) begin
                m_rid.delete(i);
                m_rlk.delete(i);
            end
            return;
        end
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
