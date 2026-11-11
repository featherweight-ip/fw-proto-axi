// AXI4 behaviour, new style (plan P5): hand-written classes on the generated _base
// classes of fw_proto_axi4_core_pkg_woven; no macros.
//
//   axi4_mgr_adapter      burst requests in, channel beats out; B/R beats back up
//                         as burst responses (manager end)
//   axi4_sub_adapter      channel beats in, burst requests out; burst responses back
//                         as B/R beats (subordinate end)
//   axi4_mem_model        a memory behind the burst API
//   axi4_burst_blocking   a blocking call per burst over the burst API, for tests
//   axi4_xact_on_burst    the convenience axi4_xact_if over axi4_burst_blocking
//   axi4_burst_on_xact    an axi4_xact_if target behind the burst API (lossy: no USER,
//                         one response per read)
//   axi4_burst_mgr_socket, axi4_burst_sub_socket
//                         the burst API pair on a component (fw_socket / fw_mirror)
//   axi4_to_mem           fw-hdl's fw_mem_if over an axi4_xact_if
//
// The burst API is two-way (design §3.4, D11): requests return once their beats
// are accepted; responses come back as calls, as they complete. Nothing above the
// transactors waits per outstanding transaction, except the blocking shims.
//
// The adapters pass the channel payloads through unchanged, apart from zeroing the
// fields the parameter set leaves off the pins (the generated axi4_payloads::<ch>_mask),
// so a link with pins and one without deliver the same beats. Only the two shims
// convert between the channel payloads and the convenience API's arguments
// (axi4_attr).
package fw_proto_axi4_behav_pkg;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_std_pkg::fw_mem_if;
    import fw_hdl_pkg::fw_component, fw_hdl_pkg::fw_socket, fw_hdl_pkg::fw_mirror;

    // ------------------------------------------------------------------
    // The convenience API's attributes against the address channels, and the
    // burst arithmetic both sides need.
    // ------------------------------------------------------------------
    class axi4_attr #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_types #(P)::aw_t   aw_t;
        typedef axi4_types #(P)::ar_t   ar_t;
        typedef axi4_types #(P)::attr_t attr_t;
        typedef axi4_types #(P)::addr_t addr_t;
        typedef axi4_types #(P)::strb_t strb_t;
        localparam int unsigned BUS = P.DATA_W / 8;

        static function aw_t to_aw(addr_t addr, int unsigned beats, attr_t a);
            aw_t f = '0;
            f.id = a.id; f.addr = addr; f.len = 8'(beats - 1); f.size = a.size;
            f.burst = a.burst; f.lock = a.lock; f.cache = a.cache; f.prot = a.prot;
            f.qos = a.qos; f.region = a.region; f.user = a.user[$bits(f.user)-1:0];
            return f;
        endfunction

        static function ar_t to_ar(addr_t addr, int unsigned beats, attr_t a);
            ar_t f = '0;
            f.id = a.id; f.addr = addr; f.len = 8'(beats - 1); f.size = a.size;
            f.burst = a.burst; f.lock = a.lock; f.cache = a.cache; f.prot = a.prot;
            f.qos = a.qos; f.region = a.region; f.user = a.user[$bits(f.user)-1:0];
            return f;
        endfunction

        // Only the attribute fields are taken (not addr, len).
        /* verilator lint_off UNUSEDSIGNAL */
        static function attr_t of_aw(aw_t f);
            attr_t a = '0;
            a.id = f.id; a.size = f.size; a.burst = f.burst; a.lock = f.lock;
            a.cache = f.cache; a.prot = f.prot; a.qos = f.qos; a.region = f.region;
            a.user[$bits(f.user)-1:0] = f.user;
            return a;
        endfunction

        static function attr_t of_ar(ar_t f);
            attr_t a = '0;
            a.id = f.id; a.size = f.size; a.burst = f.burst; a.lock = f.lock;
            a.cache = f.cache; a.prot = f.prot; a.qos = f.qos; a.region = f.region;
            a.user[$bits(f.user)-1:0] = f.user;
            return a;
        endfunction
        /* verilator lint_on UNUSEDSIGNAL */

        // The active byte lanes of beat n of a burst (A3.4.3).
        static function strb_t lanes(axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
                                     axi4_burst_e burst, int unsigned n);
            int unsigned lo = axi4_beat_lower_lane(addr, size, len, burst, n, BUS);
            int unsigned hi = axi4_beat_upper_lane(addr, size, len, burst, n, BUS);
            strb_t m = '0;
            for (int unsigned l = lo; l <= hi; l++) m[l] = 1'b1;
            return m;
        endfunction

        // OKAY < EXOKAY < SLVERR < DECERR: a burst's response is its worst beat's.
        static function axi4_resp_e worst(axi4_resp_e a, axi4_resp_e b);
            return (b > a) ? b : a;
        endfunction
    endclass

    // ------------------------------------------------------------------
    // In-order service per AXI ID: a ticket is taken in arrival order, and
    // holders of the same ID take turns in ticket order (same ID completes in
    // order, different IDs are independent; A5/A6).
    // ------------------------------------------------------------------
    class axi4_id_turns #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef logic [w1(P.ID_W)-1:0] id_t;
        local int unsigned m_next[id_t];
        local int unsigned m_serving[id_t];
        local int unsigned m_n_release;

        function int unsigned ticket(id_t id);
            if (!m_next.exists(id)) begin
                m_next[id] = 0;
                m_serving[id] = 0;
            end
            return m_next[id]++;
        endfunction

        task wait_turn(id_t id, int unsigned t);
            while (m_serving[id] != t) begin
                int unsigned n = m_n_release;
                wait (m_n_release != n);
            end
        endtask

        function void release_turn(id_t id);
            m_serving[id]++;
            m_n_release++;
        endfunction
    endclass

    // A blocking caller's transaction (axi4_burst_blocking): its response, once done.
    class axi4_burst_waiter #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        axi4_types #(P)::b_t   b;
        axi4_types #(P)::r_t   r[$];
        bit                    done;
    endclass

    // A write of the subordinate adapter waiting for its W beats.
    class axi4_sub_wr_job #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        axi4_types #(P)::aw_t  aw;
        axi4_types #(P)::w_t   w[$];
    endclass

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

    // ------------------------------------------------------------------
    // A sparse byte-addressed memory behind the burst API. A request is served
    // at once: its response is called back on `rsp` before the request returns.
    // apply_write/apply_read are the same, as functions, for a reference model.
    //   * each beat moves only its active byte lanes (A3.4.4: narrow and
    //     unaligned transfers); a write lane is written only where its strobe
    //     is set; inactive read lanes return 0;
    //   * bytes never written read as `fill`;
    //   * error ranges: a beat whose address falls in one gets that range's
    //     response and moves no data; B carries the worst beat's;
    //   * exclusive access (A7.2), one reservation per ID: an exclusive read
    //     sets it and returns EXOKAY; an exclusive write with the reservation's
    //     address, size and len, not overwritten since, writes and returns
    //     EXOKAY; otherwise OKAY and nothing is written. A write that changes
    //     memory clears the reservations it overlaps. With excl_support = 0,
    //     exclusive accesses get OKAY (A7.2.5) and an exclusive write is an
    //     ordinary one. A burst breaking A7.2.4 is never exclusive.
    // USER is not stored: B and R carry 0.
    // ------------------------------------------------------------------
    class axi4_mem_model #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_burst_req_if_base #(P);
        typedef axi4_types #(P)::b_t b_t;
        typedef axi4_types #(P)::r_t r_t;
        axi4_burst_rsp_if #(P) rsp;
        typedef axi4_attr #(P) at;
        typedef axi4_types #(P)::data_t data_t;
        typedef axi4_types #(P)::strb_t strb_t;
        typedef logic [w1(P.ID_W)-1:0] id_t;
        localparam int unsigned BUS = P.DATA_W / 8;

        byte unsigned fill = 8'h00;
        bit           excl_support = 1;
        int unsigned  n_excl_ok, n_excl_fail;

        typedef struct {
            axi4_addr64_t lo, hi;
            axi4_resp_e   resp;
        } err_range_t;

        typedef struct {
            axi4_addr64_t addr;
            axi4_size_e   size;
            logic [7:0]   len;
        } resv_t;

        local byte unsigned m_mem[axi4_addr64_t];
        local err_range_t   m_err[$];
        local resv_t        m_resv[id_t];

        // ---- backdoor
        function byte unsigned peek(axi4_addr64_t a);
            return m_mem.exists(a) ? m_mem[a] : fill;
        endfunction

        function void poke(axi4_addr64_t a, byte unsigned v);
            m_mem[a] = v;
        endfunction

        function void add_err(axi4_addr64_t lo, axi4_addr64_t hi,
                              axi4_resp_e resp = AXI4_RESP_SLVERR);
            err_range_t r = '{lo, hi, resp};
            m_err.push_back(r);
        endfunction

        function bit has_resv(id_t id);
            return m_resv.exists(id);
        endfunction

        function void clear();
            m_mem.delete();
            m_err.delete();
            m_resv.delete();
            fill = 8'h00;
            excl_support = 1;
            n_excl_ok = 0;
            n_excl_fail = 0;
        endfunction

        // OKAY, or the response of the error range holding a.
        function axi4_resp_e beat_resp(axi4_addr64_t a);
            foreach (m_err[i])
                if (a >= m_err[i].lo && a <= m_err[i].hi) return m_err[i].resp;
            return AXI4_RESP_OKAY;
        endfunction

        // Bytes [a, a+n) overlap reservation r.
        local function bit overlaps(resv_t r, axi4_addr64_t a, int unsigned n);
            axi4_addr64_t rhi = r.addr + (axi4_addr64_t'(axi4_burst_beats(r.len)) << r.size);
            return a < rhi && a + axi4_addr64_t'(n) > r.addr;
        endfunction

        local function void write_byte(axi4_addr64_t a, byte unsigned v);
            id_t ids[$];
            m_mem[a] = v;
            foreach (m_resv[id]) if (overlaps(m_resv[id], a, 1)) ids.push_back(id);
            foreach (ids[i]) m_resv.delete(ids[i]);
        endfunction

        local function bit excl_ok(axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
                                   logic lock);
            return excl_support && lock && axi4_excl_legal(addr, size, len);
        endfunction

        // A memory ignores cache, prot, QOS, region and USER.
        /* verilator lint_off UNUSEDSIGNAL */
        function b_t apply_write(aw_t aw, w_t w[$]);
            axi4_addr64_t a = axi4_addr64_t'(aw.addr);
            bit           excl = aw.lock && excl_support;
            b_t           b = '0;
            b.id = aw.id;
            b.resp = AXI4_RESP_OKAY;
            if (excl) begin
                if (!excl_ok(a, aw.size, aw.len, aw.lock) || !m_resv.exists(aw.id)
                        || m_resv[aw.id].addr != a || m_resv[aw.id].size != aw.size
                        || m_resv[aw.id].len != aw.len) begin
                    n_excl_fail++;
                    return b;               // OKAY, nothing written
                end
                m_resv.delete(aw.id);
            end
            for (int unsigned n = 0; n < axi4_burst_beats(aw.len); n++) begin
                axi4_addr64_t ba = axi4_beat_addr(a, aw.size, aw.len, aw.burst, n);
                axi4_addr64_t base = ba & ~(axi4_addr64_t'(BUS) - 1);
                strb_t        m = at::lanes(a, aw.size, aw.len, aw.burst, n);
                axi4_resp_e   r = beat_resp(ba);
                b.resp = at::worst(b.resp, r);
                if (r != AXI4_RESP_OKAY || n >= w.size()) continue;
                for (int unsigned l = 0; l < BUS; l++)
                    if (m[l] && w[n].strb[l] === 1'b1)
                        write_byte(base + axi4_addr64_t'(l), w[n].data[8*l +: 8]);
            end
            if (excl) begin
                if (b.resp == AXI4_RESP_OKAY) begin
                    b.resp = AXI4_RESP_EXOKAY;
                    n_excl_ok++;
                end else
                    n_excl_fail++;
            end
            return b;
        endfunction

        function void apply_read(ar_t ar, output r_t r[$]);
            axi4_addr64_t a = axi4_addr64_t'(ar.addr);
            bit           excl = excl_ok(a, ar.size, ar.len, ar.lock);
            axi4_resp_e   worst = AXI4_RESP_OKAY;
            r = {};
            for (int unsigned n = 0; n < axi4_burst_beats(ar.len); n++) begin
                axi4_addr64_t ba = axi4_beat_addr(a, ar.size, ar.len, ar.burst, n);
                axi4_addr64_t base = ba & ~(axi4_addr64_t'(BUS) - 1);
                strb_t        m = at::lanes(a, ar.size, ar.len, ar.burst, n);
                r_t           f = '0;
                f.id = ar.id;
                f.resp = beat_resp(ba);
                f.last = (n == axi4_burst_beats(ar.len) - 1);
                if (f.resp == AXI4_RESP_OKAY) begin
                    for (int unsigned l = 0; l < BUS; l++)
                        if (m[l]) f.data[8*l +: 8] = peek(base + axi4_addr64_t'(l));
                    if (excl) f.resp = AXI4_RESP_EXOKAY;
                end
                worst = at::worst(worst, f.resp);
                r.push_back(f);
            end
            if (excl && worst == AXI4_RESP_EXOKAY) begin
                resv_t rv = '{a, ar.size, ar.len};
                m_resv[ar.id] = rv;
            end
        endfunction
        /* verilator lint_on UNUSEDSIGNAL */

        virtual task write_burst(input aw_t aw, input w_t w[$]);
            rsp.write_resp(apply_write(aw, w));
        endtask

        virtual task read_burst(input ar_t ar);
            r_t r[$];
            apply_read(ar, r);
            foreach (r[i]) rsp.read_resp(r[i]);
        endtask
    endclass

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

    // ------------------------------------------------------------------
    // The convenience API over the burst API: axi4_xact_if calls in, blocking
    // bursts out on `blk`.
    // ------------------------------------------------------------------
    class axi4_xact_on_burst #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_xact_if_base #(P);
        typedef axi4_attr #(P) at;
        typedef axi4_types #(P)::aw_t aw_t;
        typedef axi4_types #(P)::w_t  w_t;
        typedef axi4_types #(P)::b_t  b_t;
        typedef axi4_types #(P)::r_t  r_t;

        axi4_burst_blocking #(P) blk;

        function new(axi4_burst_blocking #(P) blk_ = null);
            blk = blk_;
        endfunction

        // Of B only the response is reported.
        /* verilator lint_off UNUSEDSIGNAL */
        virtual task write(input addr_t addr, input data_t data[$], input strb_t strb[$],
                           input attr_t attr, output axi4_resp_e resp);
            aw_t aw;
            w_t  w[$];
            b_t  b;
            if (data.size() == 0 || data.size() > 256) begin
                $error("axi4_xact_on_burst: write with %0d data beats", data.size());
                resp = AXI4_RESP_SLVERR;
                return;
            end
            aw = at::to_aw(addr, data.size(), attr);
            foreach (data[n]) begin
                w_t f = '0;
                f.data = data[n];
                f.strb = (n < strb.size()) ? strb[n]
                       : at::lanes(axi4_addr64_t'(addr), aw.size, aw.len, aw.burst, n);
                f.last = (n == data.size() - 1);
                w.push_back(f);
            end
            blk.write(aw, w, b);
            resp = b.resp;
        endtask
        /* verilator lint_on UNUSEDSIGNAL */

        virtual task read(input addr_t addr, input int unsigned beats, input attr_t attr,
                          output data_t data[$], output axi4_resp_e resp);
            r_t r[$];
            data = {};
            resp = AXI4_RESP_OKAY;
            if (beats == 0 || beats > 256) begin
                $error("axi4_xact_on_burst: read of %0d beats", beats);
                resp = AXI4_RESP_SLVERR;
                return;
            end
            blk.read(at::to_ar(addr, beats, attr), r);
            foreach (r[n]) begin
                data.push_back(r[n].data);
                resp = at::worst(resp, r[n].resp);
            end
        endtask
    endclass

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

    // ------------------------------------------------------------------
    // The burst API pair on a component: the manager's socket calls requests
    // and provides responses; the subordinate's mirror the reverse.
    // ------------------------------------------------------------------
    class axi4_burst_mgr_socket #(axi4_param_t P = AXI4_PARAM_DEFAULT)
            extends fw_socket #(axi4_burst_req_if #(P), axi4_burst_rsp_if #(P));
        function new(string name, fw_component parent, axi4_burst_rsp_if #(P) imp = null);
            super.new(name, parent, imp);
        endfunction
    endclass

    class axi4_burst_sub_socket #(axi4_param_t P = AXI4_PARAM_DEFAULT)
            extends fw_mirror #(axi4_burst_req_if #(P), axi4_burst_rsp_if #(P));
        function new(string name, fw_component parent, axi4_burst_req_if #(P) imp = null);
            super.new(name, parent, imp);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // fw-hdl's protocol-independent fw_mem_if over an axi4_xact_if (`xact`,
    // e.g. an axi4_xact_on_burst over a manager adapter). Each access is one
    // INCR transaction: one beat of the access's own size when DATA is no wider
    // than the bus, else full-width beats covering DATA. Data and strobes go on
    // the lanes the address selects (A3.4.4). err = 1 on SLVERR or DECERR. An
    // access should be aligned to its size.
    // ------------------------------------------------------------------
    class axi4_to_mem #(axi4_param_t P = AXI4_PARAM_DEFAULT, type ADDR = logic [31:0],
                        type DATA = logic [63:0], type STRB = logic [7:0])
            implements fw_mem_if #(ADDR, DATA, STRB);
        typedef axi4_types #(P)::attr_t attr_t;
        typedef axi4_types #(P)::addr_t addr_t;
        typedef axi4_types #(P)::data_t data_t;
        typedef axi4_types #(P)::strb_t strb_t;
        localparam int unsigned BUS = P.DATA_W / 8;
        localparam int unsigned BYTES = $bits(DATA) / 8;

        axi4_xact_if #(P) xact;
        attr_t            attr;      // id, cache, prot, ...; size and burst are set per access
        // Bytes per beat. A variable, not a localparam: Verilator 5.055 faults on the
        // constant form when DATA is narrower than the bus.
        local int unsigned m_bpb;

        function new(axi4_xact_if #(P) xact_ = null);
            xact = xact_;
            attr = '0;
            m_bpb = (BYTES < BUS) ? BYTES : BUS;
        endfunction

        local function attr_t mk_attr();
            attr_t a = attr;
            a.size = axi4_size_e'($clog2(m_bpb));
            a.burst = AXI4_BURST_INCR;
            a.lock = 1'b0;
            return a;
        endfunction

        local function int unsigned lane0(ADDR addr, int unsigned n);
            return axi4_beat_lower_lane(axi4_addr64_t'(addr), axi4_size_e'($clog2(m_bpb)),
                                        8'(BYTES / m_bpb - 1), AXI4_BURST_INCR, n, BUS);
        endfunction

        virtual task write(output bit err, input ADDR addr, input DATA data, input STRB strb);
            data_t      d[$];
            strb_t      s[$];
            axi4_resp_e resp;
            for (int unsigned n = 0; n < BYTES / m_bpb; n++) begin
                data_t       dn = '0;
                strb_t       sn = '0;
                int unsigned off = lane0(addr, n);
                for (int unsigned i = 0; i < m_bpb; i++) begin
                    dn[8*(off + i) +: 8] = data[8*(n*m_bpb + i) +: 8];
                    sn[off + i] = strb[n*m_bpb + i];
                end
                d.push_back(dn);
                s.push_back(sn);
            end
            xact.write(addr_t'(addr), d, s, mk_attr(), resp);
            err = (resp inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR});
        endtask

        virtual task read(output DATA data, output bit err, input ADDR addr);
            data_t      d[$];
            axi4_resp_e resp;
            xact.read(addr_t'(addr), BYTES / m_bpb, mk_attr(), d, resp);
            data = '0;
            for (int unsigned n = 0; n < BYTES / m_bpb && n < d.size(); n++) begin
                int unsigned off = lane0(addr, n);
                for (int unsigned i = 0; i < m_bpb; i++)
                    data[8*(n*m_bpb + i) +: 8] = d[n][8*(off + i) +: 8];
            end
            err = (resp inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR});
        endtask
    endclass
endpackage
