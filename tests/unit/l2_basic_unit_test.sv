// L2 suite (l2_basic): whole transactions through the manager adapter, the
// link and the subordinate adapter to a trivial target. Checked through the
// API handles only; the same file runs in every view.
`include "svunit_defines.svh"

module l2_basic_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_types_pkg::*;
    import fw_proto_axi4_pkg::*;
    import axi4_test_pkg::*;

    string name = "l2_basic_ut";
    svunit_testcase svunit_ut;
    axi4_l2_env env;

    localparam int N = 32;

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        axi4_env_base::wait_ready();
        $cast(env, axi4_env_base::inst);
    endtask

    // Every test leaves the link quiescent: nothing outstanding, no errors.
    task teardown();
        `FAIL_UNLESS(env.idle())
        env.clear();
        svunit_ut.teardown();
    endtask

    // The target saw exactly what the manager asked for.
    function automatic int unsigned diff_req(axi4_xact a, axi4_xact b);
        int unsigned bad = 0;
        if (a.write !== b.write || a.to_ax() !== b.to_ax()) bad++;
        if (a.write) begin
            if (a.data.size() != b.data.size()) return bad + 1;
            foreach (a.data[i])
                if (a.data[i] !== b.data[i] || a.strb[i] !== b.strb[i] ||
                    a.wuser[i] !== b.wuser[i]) bad++;
        end
        return bad;
    endfunction

    // A read came back with the target's data, one beat per beat of len.
    function automatic int unsigned diff_rd(axi4_xact x, axi4_resp_e resp);
        int unsigned bad = 0;
        if (x.resp !== resp) bad++;
        if (x.data.size() != x.n_beats() || x.rresp.size() != x.n_beats()) return bad + 1;
        foreach (x.data[i]) begin
            axi4_r_beat_t e = '0;      // what the link carries: masked to cfg
            e.data = axi4_test_target::data_of(x.addr, i);
            e = env.cfg.mask_r(e);
            if (x.data[i] !== e.data ||
                x.rresp[i] !== resp) bad++;
        end
        return bad;
    endfunction

    `SVUNIT_TESTS_BEGIN

    // One single-beat write, then a single-beat read.
    `SVTEST(single_write_read)
        axi4_xact w = axi4_xact::new_write('h100, AXI4_SIZE_8);
        axi4_xact r = axi4_xact::new_read('h100, AXI4_SIZE_8);
        w.data.push_back('h0123_4567_89ab_cdef);
        w.strb.push_back('hff);
        w.wuser.push_back('0);
        env.mgr.xact.xact(w);
        `FAIL_UNLESS(w.done)
        `FAIL_UNLESS(w.resp === AXI4_RESP_OKAY)
        env.mgr.xact.xact(r);
        `FAIL_UNLESS(r.done)
        `FAIL_UNLESS_EQUAL(diff_rd(r, AXI4_RESP_OKAY), 0)
        `FAIL_UNLESS_EQUAL(env.tgt.seen.size(), 2)
        `FAIL_UNLESS_EQUAL(diff_req(env.tgt.seen[0], w), 0)
    `SVTEST_END

    // Random legal bursts (INCR/WRAP/FIXED, every size, len 1..16), one at
    // a time: the target sees each request unchanged, reads return its data.
    `SVTEST(random_bursts)
        int unsigned bad = 0;
        for (int i = 0; i < N; i++) begin
            axi4_xact x = rand_xact(env.cfg, i % 2);
            axi4_xact sent = axi4_xact::from_ax(x.to_ax(), x.write);
            sent.data = x.data; sent.strb = x.strb; sent.wuser = x.wuser;
            env.mgr.xact.xact(x);
            if (!x.done) bad++;
            if (env.tgt.seen.size() != i + 1 || diff_req(env.tgt.seen[i], sent) != 0) bad++;
            if (!x.write && diff_rd(x, AXI4_RESP_OKAY) != 0) bad++;
            if (x.write && x.resp !== AXI4_RESP_OKAY) bad++;
        end
        `FAIL_UNLESS_EQUAL(bad, 0)
    `SVTEST_END

    // Many callers at once over few IDs, with random service delays at the
    // subordinate: all complete, and per ID and direction they complete in
    // the order the target served them (same-ID ordering, A6).
    `SVTEST(concurrent_ids)
        axi4_xact xs[$], done_q[$];
        int unsigned bad = 0;
        env.sub.max_delay = 8;
        for (int i = 0; i < N; i++) begin
            axi4_xact x = rand_xact(env.cfg, $urandom_range(1));
            x.id = $urandom_range(3);
            xs.push_back(x);
        end
        foreach (xs[i]) begin
            automatic axi4_xact x = xs[i];
            fork
                begin
                    env.mgr.xact.xact(x);
                    done_q.push_back(x);
                end
            join_none
        end
        wait fork;
        `FAIL_UNLESS_EQUAL(done_q.size(), N)
        `FAIL_UNLESS_EQUAL(env.tgt.seen.size(), N)
        for (int d = 0; d < 2; d++)
            for (int id = 0; id < 4; id++) begin
                axi4_xact a[$], b[$];
                foreach (done_q[i])
                    if (done_q[i].write == d && done_q[i].id == id) a.push_back(done_q[i]);
                foreach (env.tgt.seen[i])
                    if (env.tgt.seen[i].write == d && env.tgt.seen[i].id == id)
                        b.push_back(env.tgt.seen[i]);
                if (a.size() != b.size()) bad++;
                else foreach (a[i]) if (diff_req(a[i], b[i]) != 0) bad++;
            end
        foreach (xs[i]) if (!xs[i].write && diff_rd(xs[i], AXI4_RESP_OKAY) != 0) bad++;
        `FAIL_UNLESS_EQUAL(bad, 0)
    `SVTEST_END

    // Error responses reach the caller: B, every R beat and the burst resp.
    `SVTEST(error_responses)
        axi4_xact w = axi4_xact::new_write('h2000, AXI4_SIZE_4, 3);
        axi4_xact r = axi4_xact::new_read('h2000, AXI4_SIZE_4, 3);
        axi4_xact ok = axi4_xact::new_read('h3000, AXI4_SIZE_4, 1);
        env.tgt.err_lo = 'h2000; env.tgt.err_hi = 'h2fff;
        env.tgt.err_resp = AXI4_RESP_DECERR;
        repeat (4) begin
            w.data.push_back('1); w.strb.push_back('hf); w.wuser.push_back('0);
        end
        env.mgr.xact.xact(w);
        `FAIL_UNLESS(w.resp === AXI4_RESP_DECERR)
        env.mgr.xact.xact(r);
        `FAIL_UNLESS_EQUAL(diff_rd(r, AXI4_RESP_DECERR), 0)
        env.mgr.xact.xact(ok);
        `FAIL_UNLESS_EQUAL(diff_rd(ok, AXI4_RESP_OKAY), 0)
        env.tgt.err_resp = AXI4_RESP_SLVERR;
        env.mgr.xact.xact(r);
        `FAIL_UNLESS_EQUAL(diff_rd(r, AXI4_RESP_SLVERR), 0)
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
