// L2 suite body for one P (plan P5, the new-style l2_basic): whole transactions
// through the manager adapter, the link and the subordinate adapter to a trivial
// target (axi4_l2_ns_env). Each test task returns "" or the first failure.
module axi4_l2_ns_cell
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*,
           fw_proto_axi4_behav_pkg::*, axi4_l2_ns_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    typedef axi4_l2_xact #(P)       xact_t;
    typedef axi4_types #(P)::aw_t   aw_t;
    typedef axi4_types #(P)::ar_t   ar_t;
    typedef axi4_types #(P)::w_t    w_t;
    typedef axi4_types #(P)::b_t    b_t;
    typedef axi4_types #(P)::r_t    r_t;
    typedef axi4_types #(P)::data_t data_t;
    typedef axi4_attr #(P)          at;
    typedef axi4_payloads #(P)      pl;

    localparam int unsigned N = 32;

    axi4_l2_ns_env #(P) env ();

    string m_err;
    function void fail(string msg);
        if (m_err == "") m_err = msg;
    endfunction

    task automatic start();
        m_err = "";
        wait (env.ready);
        env.serve(env.tgt_b);
    endtask

    task automatic finish(output string err);
        string e;
        env.finish(e);
        fail(e);
        err = (m_err == "") ? "" : $sformatf("P(ID_W=%0d DATA_W=%0d) %s", P.ID_W, P.DATA_W, m_err);
    endtask

    // A read came back with the target's data, one beat per beat of len, and resp.
    function automatic void check_rd(xact_t x, axi4_resp_e resp, string what);
        if (x.resp !== resp) fail($sformatf("%s: resp %s, expected %s", what, x.resp.name(), resp.name()));
        if (x.data.size() != x.n_beats()) begin
            fail($sformatf("%s: %0d beats for %0d", what, x.data.size(), x.n_beats()));
            return;
        end
        foreach (x.data[i])
            if (x.data[i] !== env.tgt.data_of(x.addr, i)) fail($sformatf("%s: R beat %0d", what, i));
    endfunction

    // Issue x; the target must see it unchanged (as the link carries it).
    task automatic issue_checked(xact_t x, int unsigned i);
        int unsigned base = env.tgt.seen.size();
        string d;
        env.run(x);
        if (env.tgt.seen.size() != base + 1) begin
            fail($sformatf("xact %0d: target saw %0d", i, env.tgt.seen.size() - base));
            return;
        end
        d = env.diff_req(env.tgt.seen[base], x);
        if (d != "") fail($sformatf("xact %0d (%s): %s", i, x.convert2string(), d));
        if (x.write && x.resp !== AXI4_RESP_OKAY) fail($sformatf("xact %0d: B %s", i, x.resp.name()));
        if (!x.write) check_rd(x, AXI4_RESP_OKAY, $sformatf("xact %0d", i));
    endtask

    // One single-beat write, then a single-beat read.
    task automatic t_single_write_read(output string err);
        xact_t w, r;
        start();
        w = env.wr('h100, axi4_size_e'($clog2(P.DATA_W / 8)), 0);
        r = env.req(0, 'h100, axi4_size_e'($clog2(P.DATA_W / 8)), 0);
        issue_checked(w, 0);
        issue_checked(r, 1);
        finish(err);
    endtask

    // Random legal bursts (INCR/WRAP/FIXED, every size, len 1..16), one at a time.
    task automatic t_random_bursts(output string err);
        start();
        for (int unsigned i = 0; i < N; i++) issue_checked(env.rand_req(i % 2), i);
        finish(err);
    endtask

    // Random VALID/READY stalls on every channel, set by path: the same traffic
    // still completes intact and, where the view has pins, takes clearly longer.
    task automatic t_backpressure(output string err);
        string roles[2] = '{"mgr", "sub"};
        string chs[5] = '{"aw", "w", "b", "ar", "r"};
        xact_t xs[$];
        bit applied = 0;
        longint t0, t_base, t_gap;
        start();
        for (int unsigned i = 0; i < N; i++) xs.push_back(env.rand_req(i % 2));
        t0 = $time;
        foreach (xs[i]) issue_checked(xs[i], i);
        t_base = $time - t0;
        foreach (roles[i]) foreach (chs[c])
            applied |= env.u_link.set_knob({roles[i], ".", chs[c], ".max_gap"}, 4);
        t0 = $time;
        foreach (xs[i]) begin
            xact_t x = xs[i];
            if (!x.write) x.data.delete();
            issue_checked(x, i);
        end
        t_gap = $time - t0;
        foreach (roles[i]) foreach (chs[c])
            void'(env.u_link.set_knob({roles[i], ".", chs[c], ".max_gap"}, 0));
        if (applied && t_gap * 2 < t_base * 3)
            fail($sformatf("gaps set by path did not slow the pins: %0d -> %0d", t_base, t_gap));
        finish(err);
    endtask

    // Many callers at once over few IDs, with random service delays at the
    // subordinate: all complete, and per ID and direction they complete in the
    // order the target served them (same-ID ordering, A6).
    task automatic t_concurrent_ids(output string err);
        xact_t xs[$], done_q[$];
        start();
        env.sub.max_delay = 80;
        env.sub.r_interleave = 1;   // reordered and interleaved across IDs
        for (int unsigned i = 0; i < N; i++) begin
            xact_t x = env.rand_req($urandom_range(1, 0));
            x.attr.id = '0;
            x.attr.id[1:0] = 2'($urandom_range(3, 0));
            xs.push_back(x);
        end
        foreach (xs[i]) begin
            automatic xact_t x = xs[i];
            fork
                begin
                    env.run(x);
                    done_q.push_back(x);
                end
            join_none
        end
        wait fork;
        if (done_q.size() != N || env.tgt.seen.size() != N)
            fail($sformatf("%0d done, target saw %0d, of %0d", done_q.size(), env.tgt.seen.size(), N));
        for (int d = 0; d < 2; d++)
            for (int id = 0; id < 4; id++) begin
                xact_t a[$], b[$];
                foreach (done_q[i])
                    if (done_q[i].write == d && env.on_link(done_q[i]).id == id) a.push_back(done_q[i]);
                foreach (env.tgt.seen[i])
                    if (env.tgt.seen[i].write == d && env.tgt.seen[i].attr.id == id)
                        b.push_back(env.tgt.seen[i]);
                if (a.size() != b.size())
                    fail($sformatf("dir %0d id %0d: %0d done, %0d served", d, id, a.size(), b.size()));
                else foreach (a[i]) begin
                    string df = env.diff_req(b[i], a[i]);
                    if (df != "") fail($sformatf("dir %0d id %0d #%0d out of order: %s", d, id, i, df));
                end
            end
        foreach (xs[i]) if (!xs[i].write) check_rd(xs[i], AXI4_RESP_OKAY, $sformatf("xact %0d", i));
        finish(err);
    endtask

    // Error responses reach the caller: B, and the read's response on every R beat.
    task automatic t_error_responses(output string err);
        xact_t w, r, ok;
        start();
        env.tgt.err_lo = 'h2000;
        env.tgt.err_hi = 'h2fff;
        env.tgt.err_resp = AXI4_RESP_DECERR;
        w = env.wr('h2000, AXI4_SIZE_4, 3);
        env.run(w);
        if (w.resp !== AXI4_RESP_DECERR) fail($sformatf("write: %s", w.resp.name()));
        r = env.req(0, 'h2000, AXI4_SIZE_4, 3);
        env.run(r);
        check_rd(r, AXI4_RESP_DECERR, "read");
        ok = env.req(0, 'h3000, AXI4_SIZE_4, 1);
        env.run(ok);
        check_rd(ok, AXI4_RESP_OKAY, "read ok");
        env.tgt.err_resp = AXI4_RESP_SLVERR;
        r = env.req(0, 'h2000, AXI4_SIZE_4, 3);
        env.run(r);
        check_rd(r, AXI4_RESP_SLVERR, "read slverr");
        env.u_link.settle();
        if (env.rs.r.size() != 10) fail($sformatf("%0d R beats observed, 10 sent", env.rs.r.size()));
        else foreach (env.rs.r[i]) begin
            axi4_resp_e e = (i < 4) ? AXI4_RESP_DECERR : (i < 6) ? AXI4_RESP_OKAY : AXI4_RESP_SLVERR;
            if (env.rs.r[i].resp !== e) fail($sformatf("R beat %0d: %s", i, env.rs.r[i].resp.name()));
        end
        finish(err);
    endtask

    // The link observer (pin monitor or proxy listeners) saw every beat once, in
    // order: each AW/AR as the target was asked, every W/B/R beat.
    task automatic t_link_beats(output string err);
        xact_t xs[$];
        int unsigned wi = 0, ri = 0, wb = 0, rb = 0;
        start();
        for (int unsigned i = 0; i < N; i++) begin
            xact_t x = env.rand_req(i % 2);
            env.run(x);
            xs.push_back(x);
        end
        env.u_link.settle();
        foreach (xs[i]) begin
            xact_t x = xs[i];
            xact_t s = env.tgt.seen[i];
            if (x.write) begin
                if (wi >= env.rq.aw.size() || wi >= env.rs.b.size()) begin fail("AW/B missing"); break; end
                if (env.rq.aw[wi] !== s.link_aw()) fail($sformatf("AW %0d", wi));
                if (env.rs.b[wi].id !== s.attr.id || env.rs.b[wi].resp !== AXI4_RESP_OKAY)
                    fail($sformatf("B %0d", wi));
                wi++;
                foreach (x.data[k]) begin
                    if (wb >= env.rq.w.size()) begin fail("W missing"); break; end
                    if (env.rq.w[wb].data !== x.data[k] || env.rq.w[wb].strb !== x.strb[k]
                            || env.rq.w[wb].last !== (k == x.data.size() - 1))
                        fail($sformatf("W beat %0d of xact %0d", k, i));
                    wb++;
                end
            end else begin
                if (ri >= env.rq.ar.size()) begin fail("AR missing"); break; end
                if (env.rq.ar[ri] !== s.link_ar()) fail($sformatf("AR %0d", ri));
                ri++;
                foreach (x.data[k]) begin
                    if (rb >= env.rs.r.size()) begin fail("R missing"); break; end
                    if (env.rs.r[rb].data !== x.data[k] || env.rs.r[rb].id !== s.attr.id
                            || env.rs.r[rb].last !== (k == x.data.size() - 1))
                        fail($sformatf("R beat %0d of xact %0d", k, i));
                    rb++;
                end
            end
        end
        if (wi != env.rq.aw.size() || ri != env.rq.ar.size() || wb != env.rq.w.size()
                || rb != env.rs.r.size() || wi != env.rs.b.size())
            fail($sformatf("extra beats: aw %0d/%0d w %0d/%0d b %0d/%0d ar %0d/%0d r %0d/%0d",
                env.rq.aw.size(), wi, env.rq.w.size(), wb, env.rs.b.size(), wi,
                env.rq.ar.size(), ri, env.rs.r.size(), rb));
        finish(err);
    endtask

    // A listener on the transaction-API proxy sees each call: pre before the call
    // reaches the adapter, post after it returns, with the call's arguments and
    // its response and data.
    task automatic t_xact_listener(output string err);
        xact_t xs[$];
        string exp[$];
        int unsigned n0;
        start();
        n0 = env.brec.n_calls;
        for (int unsigned i = 0; i < 8; i++) begin
            xact_t x = env.rand_req(i % 2);
            env.run(x);
            xs.push_back(x);
            exp.push_back(x.write ? "write_pre" : "read_pre");
            exp.push_back(x.write ? "write_post" : "read_post");
        end
        if (env.xrec.ev != exp) fail("listener events out of order");
        if (env.xrec.calls.size() != xs.size()) fail("listener missed a post");
        else foreach (xs[i]) begin
            xact_t c = env.xrec.calls[i];
            if (c.write != xs[i].write || c.addr !== xs[i].addr || c.attr !== xs[i].attr
                    || c.resp !== xs[i].resp || c.data != xs[i].data)
                fail($sformatf("call %0d: listener saw other arguments", i));
            if (c.write && c.strb != xs[i].strb) fail($sformatf("call %0d: strobes", i));
            if (!c.write && c.len !== xs[i].len) fail($sformatf("call %0d: len", i));
        end
        // Each convenience call went through the burst API once.
        if (env.brec.n_calls - n0 != xs.size())
            fail($sformatf("%0d calls, %0d on the burst API", xs.size(), env.brec.n_calls - n0));
        // A removed listener sees nothing more.
        env.xact.remove_listener(env.xrec);
        env.run(env.rand_req(1));
        env.xact.add_listener(env.xrec);
        if (env.xrec.ev.size() != exp.size()) fail("removed listener still called");
        finish(err);
    endtask

    // The burst API loses nothing. Random bursts with every field random (USER
    // on AW/AR and on every W beat) reach a burst target exactly as the link
    // carries them (absent fields zeroed); its B and R beats (per-beat RRESP and
    // USER) come back exactly, with RLAST on the last beat whatever the target put
    // there.
    task automatic t_burst_fidelity(output string err);
        start();
        env.serve(env.btgt);
        for (int unsigned i = 0; i < N; i++) begin
            xact_t x = env.rand_req(i % 2);
            string d;
            if (x.write) begin
                aw_t aw = at::to_aw(x.addr, x.n_beats(), x.attr);
                w_t  w[$];
                b_t  b, e;
                foreach (x.data[n]) begin
                    w_t f = w_t'(env.rnd());
                    f.data = x.data[n];
                    f.strb = x.strb[n];
                    f.last = (n == x.data.size() - 1);
                    w.push_back(f);
                end
                env.blk.write(aw, w, b);
                if (env.btgt.seen.size() != i + 1 || !env.btgt.seen[i].write) begin
                    fail($sformatf("burst %0d: not seen by the target", i));
                    break;
                end
                if (!pl::aw_compare(env.btgt.seen[i].aw, pl::aw_mask(aw), d) || env.btgt.seen[i].aw !== pl::aw_mask(aw))
                    fail($sformatf("burst %0d AW:%s", i, d));
                if (env.btgt.seen[i].w.size() != w.size()) fail($sformatf("burst %0d: W beat count", i));
                else foreach (w[n])
                    if (env.btgt.seen[i].w[n] !== pl::w_mask(w[n]))
                        fail($sformatf("burst %0d W beat %0d: %s, sent %s", i, n,
                                       pl::w_sprint(env.btgt.seen[i].w[n]), pl::w_sprint(w[n])));
                e = env.btgt.seen[i].b;
                e.id = pl::aw_mask(aw).id;
                e = pl::b_mask(e);
                if (b !== e) fail($sformatf("burst %0d B: %s, target gave %s", i, pl::b_sprint(b), pl::b_sprint(e)));
            end else begin
                ar_t ar = at::to_ar(x.addr, x.n_beats(), x.attr);
                r_t  r[$];
                env.blk.read(ar, r);
                if (env.btgt.seen.size() != i + 1 || env.btgt.seen[i].write) begin
                    fail($sformatf("burst %0d: not seen by the target", i));
                    break;
                end
                if (env.btgt.seen[i].ar !== pl::ar_mask(ar)) fail($sformatf("burst %0d AR", i));
                if (r.size() != x.n_beats()) fail($sformatf("burst %0d: %0d R beats", i, r.size()));
                else foreach (r[n]) begin
                    r_t e = env.btgt.seen[i].r[n];
                    e.id = pl::ar_mask(ar).id;
                    e.last = (n == r.size() - 1);
                    e = pl::r_mask(e);
                    if (r[n] !== e)
                        fail($sformatf("burst %0d R beat %0d: %s, target gave %s", i, n,
                                       pl::r_sprint(r[n]), pl::r_sprint(e)));
                end
            end
        end
        finish(err);
    endtask
endmodule
