// ------------------------------------------------------------------
// A convenience-API target behind the burst API: burst requests in,
// axi4_xact_if calls out on `xact`, responses back on `rsp`. A blocking
// target needs a process per call: each request is served in its own, and
// per ID they respond in request order (axi4_id_turns). Lossy by nature: W
// USER is dropped, B and R carry USER 0, and every R beat carries the
// read's one response.
// ------------------------------------------------------------------
class axi4_burst_on_xact #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_burst_req_if_base #(P);
    typedef axi4_attr #(P) at;
    typedef axi4_types #(P)::b_t b_t;
    typedef axi4_types #(P)::r_t r_t;
    typedef axi4_types #(P)::data_t data_t;
    typedef axi4_types #(P)::strb_t strb_t;

    axi4_xact_if #(P)      xact;
    axi4_burst_rsp_if #(P) rsp;

    local axi4_id_turns #(P) m_wr_turns = new;
    local axi4_id_turns #(P) m_rd_turns = new;

    function new(axi4_xact_if #(P) xact_ = null, axi4_burst_rsp_if #(P) rsp_ = null);
        xact = xact_;
        rsp = rsp_;
    endfunction

    virtual task write_burst(input aw_t aw, input w_t w[$]);
        int unsigned t = m_wr_turns.ticket(aw.id);
        fork serve_write(aw, w, t); join_none
    endtask

    virtual task read_burst(input ar_t ar);
        int unsigned t = m_rd_turns.ticket(ar.id);
        fork serve_read(ar, t); join_none
    endtask

    local task serve_write(aw_t aw, w_t w[$], int unsigned t);
        data_t      data[$];
        strb_t      strb[$];
        axi4_resp_e resp;
        b_t         b = '0;
        foreach (w[n]) begin
            data.push_back(w[n].data);
            strb.push_back(w[n].strb);
        end
        xact.write(aw.addr, data, strb, at::of_aw(aw), resp);
        b.id = aw.id;
        b.resp = resp;
        m_wr_turns.wait_turn(aw.id, t);
        rsp.write_resp(b);
        m_wr_turns.release_turn(aw.id);
    endtask

    local task serve_read(ar_t ar, int unsigned t);
        data_t       data[$];
        axi4_resp_e  resp;
        int unsigned n = axi4_burst_beats(ar.len);
        xact.read(ar.addr, n, at::of_ar(ar), data, resp);
        m_rd_turns.wait_turn(ar.id, t);
        for (int unsigned i = 0; i < n; i++) begin
            r_t f = '0;
            f.id = ar.id;
            f.data = (i < data.size()) ? data[i] : '0;
            f.resp = resp;
            f.last = (i == n - 1);
            rsp.read_resp(f);
        end
        m_rd_turns.release_turn(ar.id);
    endtask
endclass
