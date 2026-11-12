// ------------------------------------------------------------------
// A blocking call per burst over the burst API, for test writers: write()
// and read() send the request on `req` and return with its response. It is
// the requester's axi4_burst_rsp_if (`up` of an axi4_mgr_adapter). Callers
// may overlap; each waits on a per-ID queue, in request order (A5/A6), keyed
// by the ID as the link carries it (absent fields zeroed). n_waiting counts
// the callers still waiting.
// ------------------------------------------------------------------
class axi4_burst_blocking #(axi4_param_t P = AXI4_PARAM_DEFAULT)
        extends axi4_burst_rsp_if_base #(P);
    typedef axi4_payloads #(P) pl;
    typedef axi4_types #(P)::aw_t aw_t;
    typedef axi4_types #(P)::w_t  w_t;
    typedef axi4_types #(P)::ar_t ar_t;
    typedef logic [w1(P.ID_W)-1:0] id_t;
    typedef axi4_burst_waiter #(P) waiter;

    axi4_burst_req_if #(P) req;
    int unsigned           n_errors;
    int unsigned           n_waiting;

    local semaphore m_wr_sem = new(1);
    local semaphore m_rd_sem = new(1);
    local waiter    m_wr[id_t][$];
    local waiter    m_rd[id_t][$];

    function new(axi4_burst_req_if #(P) req_ = null);
        req = req_;
    endfunction

    function void error(string msg);
        n_errors++;
        $display("%0t axi4_burst_blocking: ERROR %s", $time, msg);
    endfunction

    // Queued before the request goes: the response may come inside it. The
    // semaphore keeps queue order and request order the same.
    task write(input aw_t aw, input w_t w[$], output b_t b);
        waiter p = new;
        n_waiting++;
        m_wr_sem.get();
        m_wr[pl::aw_mask(aw).id].push_back(p);
        req.write_burst(aw, w);
        m_wr_sem.put();
        wait (p.done);
        n_waiting--;
        b = p.b;
    endtask

    task read(input ar_t ar, output r_t r[$]);
        waiter p = new;
        n_waiting++;
        m_rd_sem.get();
        m_rd[pl::ar_mask(ar).id].push_back(p);
        req.read_burst(ar);
        m_rd_sem.put();
        wait (p.done);
        n_waiting--;
        r = p.r;
    endtask

    virtual task write_resp(input b_t b);
        waiter p;
        if (!m_wr.exists(b.id) || m_wr[b.id].size() == 0) begin
            error($sformatf("write_resp for ID 0x%0h with no write waiting", b.id));
            return;
        end
        p = m_wr[b.id].pop_front();
        p.b = b;
        p.done = 1;
    endtask

    virtual task read_resp(input r_t r);
        waiter p;
        if (!m_rd.exists(r.id) || m_rd[r.id].size() == 0) begin
            error($sformatf("read_resp for ID 0x%0h with no read waiting", r.id));
            return;
        end
        p = m_rd[r.id][0];
        p.r.push_back(r);
        if (r.last) begin
            void'(m_rd[r.id].pop_front());
            p.done = 1;
        end
    endtask
endclass
