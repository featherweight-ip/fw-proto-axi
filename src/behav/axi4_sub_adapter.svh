// ------------------------------------------------------------------
// Subordinate side: AW/W/AR beats in (it is the subordinate end's
// axi4_req_if), burst requests out on `tgt` (axi4_burst_req_if); the
// target's responses back in (axi4_burst_rsp_if), out as B/R beats on `rsp`.
//   * W beats are joined to AWs in order; W may arrive ahead of its AW
//     (A3.3.1). WLAST must fall on the burst's last beat;
//   * a request goes to the target once whole; the target may respond
//     inside the call or later, in request order per ID;
//   * responses are queued and sent by one loop per channel (started on
//     first use), so a response call never blocks on the pins. With
//     max_delay != 0 each send first waits a random 0..max_delay (delay())
//     and takes a random ID's next response: responses to different IDs
//     come back reordered; one ID's stay in order. R beats of different IDs
//     interleave only with r_interleave (AXI4 allows it; many managers and
//     interconnects do not accept it): otherwise a read's beats go out
//     together;
//   * RLAST is set from the read's beat count; a response with no request
//     outstanding for its ID is an error and is dropped.
// Everything else goes out as the target gave it, absent fields zeroed.
// ------------------------------------------------------------------
class axi4_sub_adapter #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_req_if_base #(P)
        implements axi4_burst_rsp_if #(P);
    typedef axi4_payloads #(P) pl;
    typedef axi4_types #(P)::b_t b_t;
    typedef axi4_types #(P)::r_t r_t;
    typedef logic [w1(P.ID_W)-1:0] id_t;
    typedef axi4_sub_wr_job #(P) wr_job;

    axi4_rsp_if #(P)       rsp;
    axi4_burst_req_if #(P) tgt;
    int unsigned           max_delay = 0; // in delay() units; 0: send at once, in order
    bit                    r_interleave = 0;  // R beats of different IDs may interleave
    int unsigned           n_errors;

    local wr_job           m_aw[$];    // writes waiting for their W beats
    local w_t              m_w[$];     // W beats ahead of their AW
    local int unsigned     m_wr[id_t];      // writes at the target
    local int unsigned     m_rd[id_t][$];   // reads at the target: R beats still due
    local b_t              m_b[$];     // responses waiting to be sent
    local r_t              m_r[$];
    local int unsigned     m_n_active;
    local bit              m_started;
    local bit              m_r_open;   // a read's beats are going out (no interleave)
    local id_t             m_r_id;
    // Raised on every push. A sender checks its queue and waits on these in
    // one time step, so no push is missed.
    local event            m_b_ev, m_r_ev;
    local string           m_r_at = "idle";   // where the R sender is, for state()

    function new(axi4_rsp_if #(P) rsp_ = null, axi4_burst_req_if #(P) tgt_ = null);
        rsp = rsp_;
        tgt = tgt_;
    endfunction

    function void error(string msg);
        n_errors++;
        $display("%0t axi4_sub_adapter: ERROR %s", $time, msg);
    endfunction

    function bit idle();
        return m_aw.size() == 0 && m_w.size() == 0 && m_n_active == 0;
    endfunction

    // What is in flight, for a stuck run's report.
    function string state();
        string q = "", d = "";
        foreach (m_r[i]) q = {q, $sformatf(" %0h%s", m_r[i].id, m_r[i].last ? "L" : "")};
        foreach (m_rd[id]) if (m_rd[id].size() != 0) d = {d, $sformatf(" %0h:%p", id, m_rd[id])};
        return $sformatf("aw %0d w %0d active %0d b_q %0d r_q [%s ] r_open %0b(id %0h) due [%s ] r sender: %s",
                         m_aw.size(), m_w.size(), m_n_active, m_b.size(), q,
                         m_r_open, m_r_id, d, m_r_at);
    endfunction

    // Waits n time units. Override to count clock cycles instead.
    virtual task delay(int unsigned n);
        #(n);
    endtask

    virtual task aw(input aw_t t);
        wr_job j = new;
        j.aw = t;
        m_aw.push_back(j);
        join_w();
    endtask

    virtual task w(input w_t t);
        m_w.push_back(t);
        join_w();
    endtask

    virtual task ar(input ar_t t);
        m_rd[t.id].push_back(axi4_burst_beats(t.len));
        m_n_active++;
        tgt.read_burst(t);
    endtask

    // Hand W beats to the oldest write still short of data; a whole write
    // goes to the target.
    local task join_w();
        while (m_aw.size() != 0 && m_w.size() != 0) begin
            wr_job j = m_aw[0];
            w_t    f = m_w.pop_front();
            bit    full;
            j.w.push_back(f);
            full = (j.w.size() == axi4_burst_beats(j.aw.len));
            if (f.last != full)
                error($sformatf("WLAST=%0b on beat %0d of %0d (AWID 0x%0h)",
                    f.last, j.w.size(), axi4_burst_beats(j.aw.len), j.aw.id));
            if (full) begin
                void'(m_aw.pop_front());
                if (!m_wr.exists(j.aw.id)) m_wr[j.aw.id] = 0;
                m_wr[j.aw.id]++;
                m_n_active++;
                tgt.write_burst(j.aw, j.w);
            end
        end
    endtask

    // ---- axi4_burst_rsp_if: the target's responses, queued for the senders.
    virtual task write_resp(input b_t b);
        if (!m_wr.exists(b.id) || m_wr[b.id] == 0) begin
            error($sformatf("write_resp for ID 0x%0h with no write outstanding", b.id));
            return;
        end
        m_wr[b.id]--;
        m_b.push_back(b);
        -> m_b_ev;
        start();
    endtask

    virtual task read_resp(input r_t r);
        int unsigned due;
        r_t          f = r;
        if (!m_rd.exists(r.id) || m_rd[r.id].size() == 0) begin
            error($sformatf("read_resp for ID 0x%0h with no read outstanding", r.id));
            return;
        end
        due = m_rd[r.id][0];
        f.last = (due == 1);
        if (due == 1) void'(m_rd[r.id].pop_front());
        else          m_rd[r.id][0] = due - 1;
        m_r.push_back(f);
        -> m_r_ev;
        start();
    endtask

    local function void start();
        if (m_started) return;
        m_started = 1;
        fork
            send_b();
            send_r();
        join_none
    endfunction

    // The index of the response to send next: the oldest, or with
    // max_delay the oldest of a random ID.
    local function int pick_b();
        int c[$];
        if (max_delay == 0) return 0;
        foreach (m_b[i]) begin
            bit first = 1;
            for (int k = 0; k < i; k++) if (m_b[k].id == m_b[i].id) first = 0;
            if (first) c.push_back(i);
        end
        return c[$urandom_range(c.size() - 1)];
    endfunction

    local function int pick_r();
        int c[$];
        if (m_r_open && !r_interleave) begin
            foreach (m_r[i]) if (m_r[i].id == m_r_id) return i;
            return -1;                  // the open read's next beat is not here yet
        end
        if (max_delay == 0) return 0;
        foreach (m_r[i]) begin
            bit first = 1;
            for (int k = 0; k < i; k++) if (m_r[k].id == m_r[i].id) first = 0;
            if (first) c.push_back(i);
        end
        return c[$urandom_range(c.size() - 1)];
    endfunction

    local task send_b();
        forever begin
            b_t f;
            int i;
            while (m_b.size() == 0) @(m_b_ev);
            if (max_delay != 0) delay($urandom_range(max_delay));
            i = pick_b();
            f = m_b[i];
            m_b.delete(i);
            rsp.b(pl::b_mask(f));
            m_n_active--;
        end
    endtask

    local task send_r();
        forever begin
            r_t f;
            int i;
            m_r_at = "queue";
            while (m_r.size() == 0) @(m_r_ev);
            if (max_delay != 0) begin
                int unsigned d = $urandom_range(max_delay);
                m_r_at = $sformatf("delay %0d from %0t", d, $time);
                delay(d);
            end
            i = pick_r();
            if (i < 0) begin
                m_r_at = "next beat";
                @(m_r_ev);              // the open read's next beat
                continue;
            end
            f = m_r[i];
            m_r.delete(i);
            m_r_at = $sformatf("send %0h since %0t", f.id, $time);
            rsp.r(pl::r_mask(f));
            m_r_open = !f.last;
            m_r_id = f.id;
            if (f.last) m_n_active--;
        end
    endtask
endclass
