// L1 suite body for one P (plan P4.3): the channel
// contract, checked through API handles only. The link is axi4_l1_link #(P),
// one module per view (tests/env/<view>/), with the same members:
//   req, rsp          what the manager / subordinate call (axi4_req_if / axi4_rsp_if)
//   sub_in, mgr_in    inboxes at the far ends
//   add_req_listener, add_rsp_listener   observation (proxy in tlm, pin monitor in xtor)
//   set_knob(path, v) "<role>.<ch>.<knob>"; 0 where the view has no such knob
//   attach(mgr_end, sub_end)   other receivers in place of the inboxes (L2)
//   settle()          let the link go quiet; errors() its checkers' findings
//
// Traffic is protocol-legal (bursts, WLAST, WSTRB lanes, B/R after their
// request with its ID, EXOKAY only for exclusive), so the xtor view's checkers
// stay at zero violations. Each test task returns "" or the first failure.
module axi4_l1_cell
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*,
           fw_proto_axi4_rules_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    typedef axi4_types #(P)::aw_t aw_t;
    typedef axi4_types #(P)::w_t  w_t;
    typedef axi4_types #(P)::b_t  b_t;
    typedef axi4_types #(P)::ar_t ar_t;
    typedef axi4_types #(P)::r_t  r_t;
    typedef axi4_payloads #(P) pl;

    localparam int unsigned DW_ = P.DATA_W, BUS = P.DATA_W / 8;
    localparam int unsigned AW_I = 0, W_I = 1, B_I = 2, AR_I = 3, R_I = 4;

    axi4_l1_link #(P) u_link ();

    // ---- observation: pre/post calls per channel, from the link's listener source
    class req_rec extends axi4_req_if_listener_base #(P);
        int unsigned n_pre[5], n_post[5];
        virtual function void aw_pre(input aw_t t);  n_pre[AW_I]++;  endfunction
        virtual function void w_pre(input w_t t);    n_pre[W_I]++;   endfunction
        virtual function void ar_pre(input ar_t t);  n_pre[AR_I]++;  endfunction
        virtual function void aw_post(input aw_t t); n_post[AW_I]++; endfunction
        virtual function void w_post(input w_t t);   n_post[W_I]++;  endfunction
        virtual function void ar_post(input ar_t t); n_post[AR_I]++; endfunction
    endclass

    class rsp_rec extends axi4_rsp_if_listener_base #(P);
        int unsigned n_pre[5], n_post[5];
        virtual function void b_pre(input b_t t);  n_pre[B_I]++;  endfunction
        virtual function void r_pre(input r_t t);  n_pre[R_I]++;  endfunction
        virtual function void b_post(input b_t t); n_post[B_I]++; endfunction
        virtual function void r_post(input r_t t); n_post[R_I]++; endfunction
    endclass

    req_rec rq = new;
    rsp_rec rs = new;
    axi4_rules #(P) rules;       // the AXI4 rules (plan P7), on the same events
    int unsigned n_sent[5];      // beats sent per channel since the last finish()
    bit ready;                   // the link is up and observed: tests may start

    initial begin
        wait (u_link.up);
        u_link.add_req_listener(rq);
        u_link.add_rsp_listener(rs);
        rules = new("link", u_link.at_pins());
        u_link.add_req_listener(rules.req);
        u_link.add_rsp_listener(rules.rsp);
        ready = 1;
    end

    // ---- protocol-legal traffic
    function automatic logic [1023:0] rnd();
        logic [1023:0] v;
        for (int i = 0; i < 32; i++) v[i*32 +: 32] = $urandom;
        return v;
    endfunction

    // One write: AW, its W beats, its B. One read: AR, its R beats.
    typedef struct {
        aw_t aw;
        w_t  w[$];
        b_t  b;
    } wr_t;
    typedef struct {
        ar_t ar;
        r_t  r[$];
    } rd_t;

    // A legal burst, as an AW (an AR is filled field by field from it: the
    // two structs differ in USER width). burst < 0: any type.
    function automatic aw_t rand_ax(int burst = -1, bit excl = 0);
        aw_t a;
        axi4_addr64_t addr;
        do begin
            a = aw_t'(rnd());
            a.size = axi4_size_e'($urandom_range($clog2(BUS), 0));
            a.lock = excl;
            if (excl) begin
                a.burst = AXI4_BURST_INCR;
                a.len = 8'((1 << $urandom_range(4, 0)) - 1);
            end else begin
                a.burst = (burst >= 0) ? axi4_burst_e'(burst) : axi4_burst_e'($urandom_range(2, 0));
                case (a.burst)
                    AXI4_BURST_WRAP: a.len = 8'((2 << $urandom_range(3, 0)) - 1);
                    AXI4_BURST_FIXED: a.len = 8'($urandom_range(3, 0));
                    default: a.len = 8'($urandom_range(7, 0));
                endcase
            end
            addr = axi4_addr64_t'(a.addr);
            if (a.burst == AXI4_BURST_WRAP) addr = axi4_aligned_addr(addr, a.size);
            if (excl) addr &= ~((axi4_addr64_t'(axi4_burst_beats(a.len)) << a.size) - 1);
            a.addr = addr[P.ADDR_W-1:0];
        end while (!axi4_burst_legal(addr, a.size, a.len, a.burst, BUS)
                   || (excl && !axi4_excl_legal(addr, a.size, a.len)));
        return a;
    endfunction

    function automatic axi4_resp_e rand_resp(bit excl);
        if (excl) return ($urandom_range(1, 0) != 0) ? AXI4_RESP_EXOKAY : AXI4_RESP_OKAY;
        case ($urandom_range(2, 0))
            0: return AXI4_RESP_OKAY;
            1: return AXI4_RESP_SLVERR;
            default: return AXI4_RESP_DECERR;
        endcase
    endfunction

    function automatic void rand_wr(output wr_t t, input int burst = -1, input bit excl = 0,
                                    input int resp = -1);
        t.aw = rand_ax(burst, excl);
        t.w.delete();
        for (int n = 0; n <= int'(t.aw.len); n++) begin
            w_t w = w_t'(rnd());
            int unsigned lo = axi4_beat_lower_lane(axi4_addr64_t'(t.aw.addr), t.aw.size,
                                                   t.aw.len, t.aw.burst, n, BUS);
            int unsigned hi = axi4_beat_upper_lane(axi4_addr64_t'(t.aw.addr), t.aw.size,
                                                   t.aw.len, t.aw.burst, n, BUS);
            for (int unsigned k = 0; k < BUS; k++)
                if (k < lo || k > hi) w.strb[k] = 1'b0;
            w.last = (n == int'(t.aw.len));
            t.w.push_back(w);
        end
        t.b = b_t'(rnd());
        t.b.id = t.aw.id;
        t.b.resp = (resp >= 0) ? axi4_resp_e'(resp) : rand_resp(excl);
    endfunction

    function automatic void rand_rd(output rd_t t, input int burst = -1, input bit excl = 0,
                                    input int resp = -1);
        aw_t a = rand_ax(burst, excl);
        t.ar = ar_t'(rnd());
        t.ar.id = a.id;
        t.ar.addr = a.addr;
        t.ar.len = a.len;
        t.ar.size = a.size;
        t.ar.burst = a.burst;
        t.ar.lock = a.lock;
        t.ar.cache = a.cache;
        t.ar.prot = a.prot;
        t.r.delete();
        for (int n = 0; n <= int'(a.len); n++) begin
            r_t r = r_t'(rnd());
            r.id = a.id;
            r.resp = (resp >= 0) ? axi4_resp_e'(resp) : rand_resp(excl);
            r.last = (n == int'(a.len));
            t.r.push_back(r);
        end
    endfunction

    function automatic string where(string what, int unsigned i, string diff);
        return $sformatf("%s %0d:%s", what, i, diff);
    endfunction

    // The running test's first failure. Forked parts report here (a task's
    // output may not be written from a fork); the test task copies it out.
    string m_err;
    function void fail(string msg);
        if (m_err == "") m_err = msg;
    endfunction

    // ---- the parts every test is built from. Senders count beats; checkers
    // take beats from the far end's inbox and compare. Each stops at the
    // first mismatch (fail()) but still drains its own count.
    task automatic send_aws(wr_t t[$]);
        foreach (t[i]) begin u_link.req.aw(t[i].aw); n_sent[AW_I]++; end
    endtask
    task automatic send_ws(wr_t t[$]);
        foreach (t[i]) foreach (t[i].w[k]) begin u_link.req.w(t[i].w[k]); n_sent[W_I]++; end
    endtask
    task automatic send_ars(rd_t t[$]);
        foreach (t[i]) begin u_link.req.ar(t[i].ar); n_sent[AR_I]++; end
    endtask
    task automatic send_bs(wr_t t[$]);
        foreach (t[i]) begin u_link.rsp.b(t[i].b); n_sent[B_I]++; end
    endtask
    task automatic send_rs(rd_t t[$]);
        foreach (t[i]) foreach (t[i].r[k]) begin u_link.rsp.r(t[i].r[k]); n_sent[R_I]++; end
    endtask

    task automatic get_aws(wr_t t[$]);
        aw_t g; string d;
        foreach (t[i]) begin
            u_link.sub_in.aw_in.get(g);
            if (!pl::aw_compare(g, t[i].aw, d)) fail(where("aw", i, d));
        end
    endtask
    task automatic get_ws(wr_t t[$]);
        w_t g; string d;
        foreach (t[i]) foreach (t[i].w[k]) begin
            u_link.sub_in.w_in.get(g);
            if (!pl::w_compare(g, t[i].w[k], d)) fail(where("w", i, d));
        end
    endtask
    task automatic get_ars(rd_t t[$]);
        ar_t g; string d;
        foreach (t[i]) begin
            u_link.sub_in.ar_in.get(g);
            if (!pl::ar_compare(g, t[i].ar, d)) fail(where("ar", i, d));
        end
    endtask
    task automatic get_bs(wr_t t[$]);
        b_t g; string d;
        foreach (t[i]) begin
            u_link.mgr_in.b_in.get(g);
            if (!pl::b_compare(g, t[i].b, d)) fail(where("b", i, d));
        end
    endtask
    task automatic get_rs(rd_t t[$]);
        r_t g; string d;
        foreach (t[i]) foreach (t[i].r[k]) begin
            u_link.mgr_in.r_in.get(g);
            if (!pl::r_compare(g, t[i].r[k], d)) fail(where("r", i, d));
        end
    endtask

    // The subordinate's side of a write: take its AW and W beats, answer B.
    // Of a read: take its AR, answer the R beats. Checked as they arrive.
    task automatic serve_writes(wr_t t[$]);
        aw_t ga; w_t gw; string d;
        foreach (t[i]) begin
            u_link.sub_in.aw_in.get(ga);
            if (!pl::aw_compare(ga, t[i].aw, d)) fail(where("aw", i, d));
            foreach (t[i].w[k]) begin
                u_link.sub_in.w_in.get(gw);
                if (!pl::w_compare(gw, t[i].w[k], d)) fail(where("w", i, d));
            end
            u_link.rsp.b(t[i].b);
            n_sent[B_I]++;
        end
    endtask
    task automatic serve_reads(rd_t t[$]);
        ar_t ga; string d;
        foreach (t[i]) begin
            u_link.sub_in.ar_in.get(ga);
            if (!pl::ar_compare(ga, t[i].ar, d)) fail(where("ar", i, d));
            foreach (t[i].r[k]) begin
                u_link.rsp.r(t[i].r[k]);
                n_sent[R_I]++;
            end
        end
    endtask

    // All five channels at once: the manager streams AW, W and AR while the
    // subordinate answers each write and read as it arrives.
    task automatic traffic(wr_t wr[$], rd_t rd[$]);
        fork
            send_aws(wr);
            send_ws(wr);
            send_ars(rd);
            serve_writes(wr);
            serve_reads(rd);
            get_bs(wr);
            get_rs(rd);
        join
    endtask

    // Every test ends here: the link quiet, nothing undelivered, the
    // observer saw each beat sent (one pre and one post each), no rule or
    // checker findings. Then the counts and the rules reset for the next test.
    task automatic finish(output string err);
        string ch[5] = '{"aw", "w", "b", "ar", "r"};
        u_link.settle();
        if (!(u_link.sub_in.idle() && u_link.mgr_in.idle()))
            fail("undelivered beats left in an inbox");
        for (int c = 0; c < 5; c++) begin
            int unsigned pre = (c == B_I || c == R_I) ? rs.n_pre[c] : rq.n_pre[c];
            int unsigned post = (c == B_I || c == R_I) ? rs.n_post[c] : rq.n_post[c];
            if (pre != n_sent[c] || post != n_sent[c])
                fail($sformatf("%s: sent %0d, observed pre %0d post %0d", ch[c], n_sent[c], pre, post));
        end
        if (rules.n_fail() != 0)
            fail($sformatf("rules failed: %s (first: %s)", rules.failed(), rules.first()));
        rules.reset();
        fail(u_link.errors());
        err = (m_err == "") ? "" : $sformatf("P(ID_W=%0d DATA_W=%0d) %s", P.ID_W, DW_, m_err);
        m_err = "";
        n_sent = '{default: 0};
        rq.n_pre = '{default: 0};
        rq.n_post = '{default: 0};
        rs.n_pre = '{default: 0};
        rs.n_post = '{default: 0};
        u_link.sub_in.clear();
        u_link.mgr_in.clear();
    endtask

    localparam int unsigned N = 8;

    task automatic make(int unsigned n, output wr_t wr[$], output rd_t rd[$]);
        wr.delete();
        rd.delete();
        for (int unsigned i = 0; i < n; i++) begin
            wr_t w; rd_t r;
            rand_wr(w);
            rand_rd(r);
            wr.push_back(w);
            rd.push_back(r);
        end
    endtask

    // ---- the tests

    // Requests, one channel at a time (AW, then W, then AR), each in order and
    // unchanged at the subordinate; then the responses (B, then R) at the manager.
    task automatic t_channels(output string err);
        wr_t wr[$]; rd_t rd[$];
        m_err = "";
        wait (ready);
        make(N, wr, rd);
        fork send_aws(wr); get_aws(wr); join
        fork send_ws(wr);  get_ws(wr);  join
        fork send_ars(rd); get_ars(rd); join
        fork send_bs(wr);  get_bs(wr);  join
        fork send_rs(rd);  get_rs(rd);  join
        finish(err);
    endtask

    // All five channels at once (traffic()), each in its own order.
    task automatic t_concurrent(output string err);
        wr_t wr[$]; rd_t rd[$];
        m_err = "";
        wait (ready);
        make(4 * N, wr, rd);
        traffic(wr, rd);
        finish(err);
    endtask

    // Channel independence: with the subordinate refusing AW, the channels that
    // may legally flow without it still do (W ahead of its AW, AR and R).
    // Then AW is released, every AW arrives in order, and the Bs follow.
    task automatic t_aw_stalled(output string err);
        wr_t wr[$]; rd_t rd[$];
        bit others_done = 0;
        m_err = "";
        wait (ready);
        make(N, wr, rd);
        u_link.sub_in.aw_in.stall = 1;
        // The AWs may all fit in the link's buffering, or block: either way
        // they do not decide when the wait below ends.
        fork
            send_aws(wr);
        join_none
        fork
            begin
                fork
                    send_ws(wr);
                    get_ws(wr);
                    send_ars(rd);
                    serve_reads(rd);
                    get_rs(rd);
                join
                others_done = 1;
            end
            begin
                // Bounded: the other channels must not wait behind AW.
                repeat (2000) begin
                    if (others_done) break;
                    @(posedge u_link.aclk);
                end
            end
        join_any
        if (!others_done) fail("W/AR/R blocked behind a stalled AW");
        if (u_link.sub_in.aw_in.n_recv != 0) fail("an AW got through the stall");
        u_link.sub_in.aw_in.stall = 0;
        wait (others_done);
        get_aws(wr);
        fork send_bs(wr); get_bs(wr); join
        finish(err);
    endtask

    // Every response code and burst type crosses the link intact: OKAY,
    // SLVERR, DECERR on normal accesses, EXOKAY on exclusive ones; FIXED,
    // INCR, WRAP on both AW and AR.
    task automatic t_encodings(output string err);
        wr_t wr[$]; rd_t rd[$];
        m_err = "";
        wait (ready);
        for (int bt = 0; bt < 3; bt++) begin
            for (int rc = 0; rc < 4; rc++) begin
                wr_t w; rd_t r;
                bit excl = (rc == int'(AXI4_RESP_EXOKAY));
                rand_wr(w, bt, excl && bt == int'(AXI4_BURST_INCR), excl ? -1 : rc);
                rand_rd(r, bt, excl && bt == int'(AXI4_BURST_INCR), excl ? -1 : rc);
                if (excl && bt != int'(AXI4_BURST_INCR)) continue;
                if (excl) begin
                    w.b.resp = AXI4_RESP_EXOKAY;
                    foreach (r.r[k]) r.r[k].resp = AXI4_RESP_EXOKAY;
                end
                wr.push_back(w);
                rd.push_back(r);
            end
        end
        traffic(wr, rd);
        finish(err);
    endtask

    // Backpressure from outside, set by path ("<role>.<ch>.<knob>"): the same
    // traffic runs with the defaults, then with every initiator and target
    // channel given max_gap 4 and a random depth. Where the view has pins, the
    // gaps must show there: the second run takes clearly longer.
    task automatic t_backpressure(output string err);
        string roles[2] = '{"mgr", "sub"};
        string chs[5] = '{"aw", "w", "b", "ar", "r"};
        bit applied = 0;
        longint t0, t_base, t_gap;
        wr_t wr[$]; rd_t rd[$];
        m_err = "";
        wait (ready);
        make(2 * N, wr, rd);
        t0 = $time;
        traffic(wr, rd);
        t_base = $time - t0;
        foreach (roles[i]) foreach (chs[c]) begin
            applied |= u_link.set_knob({roles[i], ".", chs[c], ".max_gap"}, 4);
            applied |= u_link.set_knob({roles[i], ".", chs[c], ".depth"}, $urandom_range(4, 1));
        end
        if (u_link.set_knob("mgr.aw.nonesuch", 1) || u_link.set_knob("nonesuch.aw.depth", 1)
                || u_link.set_knob("mgr", 1))
            fail("set_knob took a path with no knob");
        t0 = $time;
        traffic(wr, rd);
        t_gap = $time - t0;
        if (applied && t_gap * 4 < t_base * 5)
            fail($sformatf("gaps set by path did not slow the pins: %0d -> %0d", t_base, t_gap));
        foreach (roles[i]) foreach (chs[c]) begin
            void'(u_link.set_knob({roles[i], ".", chs[c], ".max_gap"}, 0));
            void'(u_link.set_knob({roles[i], ".", chs[c], ".depth"}, 4));
        end
        finish(err);
    endtask
endmodule
