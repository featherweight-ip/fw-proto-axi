// ------------------------------------------------------------------
// Manager side: burst requests in (axi4_burst_req_if), AW/W/AR beats out on
// `req`; B/R beats back in (it is the manager end's axi4_rsp_if), passed up
// on `up` (axi4_burst_rsp_if) as they arrive.
//   * a write sends AW then all its W beats, with no other write's W beats
//     in between (AXI4 has no WID: W follows AW order, A5.2);
//   * a request returns when its beats are accepted; any number may be
//     outstanding;
//   * per ID it checks that a B or R has a request outstanding, and RLAST
//     against the read's beat count (A5/A6).
// Beats go out as given (WLAST included), absent fields zeroed.
// ------------------------------------------------------------------
class axi4_mgr_adapter #(axi4_param_t P = AXI4_PARAM_DEFAULT)
        extends axi4_rsp_if_base #(P) implements axi4_burst_req_if #(P);
    typedef axi4_payloads #(P) pl;
    typedef axi4_types #(P)::aw_t aw_t;
    typedef axi4_types #(P)::w_t  w_t;
    typedef axi4_types #(P)::ar_t ar_t;
    typedef logic [w1(P.ID_W)-1:0] id_t;

    axi4_req_if #(P)       req;
    axi4_burst_rsp_if #(P) up;
    int unsigned           n_errors;

    local semaphore        m_wr_sem = new(1);
    local semaphore        m_rd_sem = new(1);
    local int unsigned     m_wr[id_t];      // writes outstanding
    local int unsigned     m_rd[id_t][$];   // reads outstanding: R beats still due
    local int unsigned     m_n_out;

    function new(axi4_req_if #(P) req_ = null, axi4_burst_rsp_if #(P) up_ = null);
        req = req_;
        up = up_;
    endfunction

    function void error(string msg);
        n_errors++;
        $display("%0t axi4_mgr_adapter: ERROR %s", $time, msg);
    endfunction

    function bit idle();
        return m_n_out == 0;
    endfunction

    // Counted before the beats go: the B may come back before they are all sent.
    virtual task write_burst(input aw_t aw, input w_t w[$]);
        aw_t a = pl::aw_mask(aw);
        if (w.size() != axi4_burst_beats(a.len))
            error($sformatf("write_burst with %0d W beats, AWLEN %0d", w.size(), a.len));
        m_wr_sem.get();
        if (!m_wr.exists(a.id)) m_wr[a.id] = 0;
        m_wr[a.id]++;
        m_n_out++;
        req.aw(a);
        foreach (w[i]) req.w(pl::w_mask(w[i]));
        m_wr_sem.put();
    endtask

    virtual task read_burst(input ar_t ar);
        ar_t a = pl::ar_mask(ar);
        m_rd_sem.get();
        m_rd[a.id].push_back(axi4_burst_beats(a.len));
        m_n_out++;
        req.ar(a);
        m_rd_sem.put();
    endtask

    virtual task b(input b_t t);
        if (!m_wr.exists(t.id) || m_wr[t.id] == 0) begin
            error($sformatf("B for ID 0x%0h with no write outstanding", t.id));
            return;
        end
        m_wr[t.id]--;
        m_n_out--;
        up.write_resp(t);
    endtask

    virtual task r(input r_t t);
        int unsigned due;
        if (!m_rd.exists(t.id) || m_rd[t.id].size() == 0) begin
            error($sformatf("R for ID 0x%0h with no read outstanding", t.id));
            return;
        end
        due = m_rd[t.id][0];
        if (t.last != (due == 1))
            error($sformatf("RLAST=%0b with %0d beats still due (ID 0x%0h)", t.last, due, t.id));
        if (t.last || due == 1) begin
            void'(m_rd[t.id].pop_front());
            m_n_out--;
        end else
            m_rd[t.id][0] = due - 1;
        up.read_resp(t);
    endtask
endclass
