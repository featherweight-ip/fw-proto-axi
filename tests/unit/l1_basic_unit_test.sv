// L1 suite (l1_basic): the L1 contract, checked through the API handles
// only. The same file runs in every view.
`include "svunit_defines.svh"

module l1_basic_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_types_pkg::*;
    import fw_proto_axi4_pkg::*;
    import axi4_test_pkg::*;

    string name = "l1_basic_ut";
    svunit_testcase svunit_ut;
    axi4_l1_env env;

    localparam int N = 16;

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        axi4_env_base::wait_ready();
        $cast(env, axi4_env_base::inst);
    endtask

    // Every test leaves the link quiescent: nothing undelivered, no stall.
    task teardown();
        `FAIL_UNLESS(env.idle())
        env.clear();
        svunit_ut.teardown();
    endtask

    // Bounded wait for the time-consuming views; zero-time in `tlm`.
    localparam time TMO = 20ns;

    // ---- one channel, one direction: send n, expect the same n in order
    `define AXI4_XFER(CH, SEND, INBOX, GEN, NUM) \
        begin \
            axi4_``CH``_beat_t sent[$], got; \
            int bad = 0; \
            for (int i = 0; i < NUM; i++) sent.push_back(GEN(env.cfg)); \
            fork \
                foreach (sent[i]) SEND.CH(sent[i]); \
                foreach (sent[i]) begin \
                    INBOX.get(got); \
                    if (got !== sent[i]) bad++; \
                end \
            join \
            `FAIL_UNLESS_EQUAL(bad, 0) \
        end

    `SVUNIT_TESTS_BEGIN

    // Manager -> subordinate: AW, W, AR each arrive in order, unchanged.
    `SVTEST(req_channels)
        `AXI4_XFER(aw, env.mgr.axi.t, env.sub.aw_in, rand_aw, N)
        `AXI4_XFER(w,  env.mgr.axi.t, env.sub.w_in,  rand_w,  N)
        `AXI4_XFER(ar, env.mgr.axi.t, env.sub.ar_in, rand_ar, N)
    `SVTEST_END

    // Subordinate -> manager: B, R.
    `SVTEST(rsp_channels)
        `AXI4_XFER(b, env.sub.axi.t, env.mgr.b_in, rand_b, N)
        `AXI4_XFER(r, env.sub.axi.t, env.mgr.r_in, rand_r, N)
    `SVTEST_END

    // All five channels at once; each keeps its own order.
    `SVTEST(all_channels_concurrent)
        fork
            `AXI4_XFER(aw, env.mgr.axi.t, env.sub.aw_in, rand_aw, 4*N)
            `AXI4_XFER(w,  env.mgr.axi.t, env.sub.w_in,  rand_w,  4*N)
            `AXI4_XFER(ar, env.mgr.axi.t, env.sub.ar_in, rand_ar, 4*N)
            `AXI4_XFER(b,  env.sub.axi.t, env.mgr.b_in,  rand_b,  4*N)
            `AXI4_XFER(r,  env.sub.axi.t, env.mgr.r_in,  rand_r,  4*N)
        join
    `SVTEST_END

    // Channel independence: with the subordinate refusing AW indefinitely,
    // every other channel still flows. Then AW is released and delivers
    // everything, in order.
    `SVTEST(aw_stalled_others_flow)
        axi4_aw_beat_t aws[$], ga;
        bit others_done = 0;
        for (int i = 0; i < N; i++) aws.push_back(rand_aw(env.cfg));
        env.sub.aw_in.stall = 1;
        fork
            foreach (aws[i]) env.mgr.axi.t.aw(aws[i]);
            begin
                fork
                    `AXI4_XFER(w,  env.mgr.axi.t, env.sub.w_in,  rand_w,  N)
                    `AXI4_XFER(ar, env.mgr.axi.t, env.sub.ar_in, rand_ar, N)
                    `AXI4_XFER(b,  env.sub.axi.t, env.mgr.b_in,  rand_b,  N)
                    `AXI4_XFER(r,  env.sub.axi.t, env.mgr.r_in,  rand_r,  N)
                join
                others_done = 1;
                `FAIL_UNLESS_EQUAL(env.sub.aw_in.n_recv, 0)
                env.sub.aw_in.stall = 0;
            end
            begin
                #(TMO);
                `FAIL_IF_LOG(!others_done, "other channels blocked behind a stalled AW")
                env.sub.aw_in.stall = 0;
            end
        join_any
        foreach (aws[i]) begin
            env.sub.aw_in.get(ga);
            `FAIL_UNLESS(ga === aws[i])
        end
        `FAIL_UNLESS(others_done)
        disable fork;
    `SVTEST_END

    // Every response code and burst type crosses the link intact.
    `SVTEST(every_encoding)
        axi4_b_beat_t b, gb; axi4_r_beat_t r, gr; axi4_ar_beat_t a, ga;
        for (int i = 0; i < 4; i++) begin
            b = rand_b(env.cfg); b.resp = axi4_resp_e'(i);
            env.sub.axi.t.b(b); env.mgr.b_in.get(gb);
            `FAIL_UNLESS(gb === b)
            r = rand_r(env.cfg); r.resp = axi4_resp_e'(i);
            env.sub.axi.t.r(r); env.mgr.r_in.get(gr);
            `FAIL_UNLESS(gr === r)
        end
        for (int i = 0; i < 3; i++) begin
            do a = rand_ar(env.cfg); while (a.burst != axi4_burst_e'(i));
            env.mgr.axi.t.ar(a); env.sub.ar_in.get(ga);
            `FAIL_UNLESS(ga === a)
        end
    `SVTEST_END

    // The configuration masks exactly the absent / narrow bits.
    `SVTEST(cfg_masks)
        axi4_w_beat_t  w = axi4_w_beat_t'(rand_bits());
        axi4_aw_beat_t a = axi4_aw_beat_t'(rand_bits());
        axi4_cfg c = axi4_cfg::from_param(AXI4_TEST_PARAM);
        // (No string literals inside SVUnit macros: they stringify the expression.)
        string same = "", id_w = "ID_W";
        w = c.mask_w(w);
        a = c.mask_aw(a);
        `FAIL_UNLESS(w.data[1023:64] == '0)
        `FAIL_UNLESS(w.strb[127:8] == '0)
        `FAIL_UNLESS(w.user[63:3] == '0)
        `FAIL_UNLESS(a.id[31:4] == '0)
        `FAIL_UNLESS(a.addr[63:32] == '0)
        `FAIL_UNLESS(a.user[63:2] == '0)
        `FAIL_UNLESS(c.compatible(axi4_cfg::from_param(c.to_param())) == same)
        c.id_w = 0;
        `FAIL_UNLESS(c.compatible(env.cfg) == id_w)
    `SVTEST_END

    // Stream pack/unpack: unpack(pack(b)) == cfg.mask(b), at the test
    // configuration, with ID/USER absent, and at the widest one.
    `SVTEST(wire_round_trip)
        axi4_cfg cs[3];
        cs[0] = axi4_cfg::from_param(AXI4_TEST_PARAM);
        cs[1] = new(12, 8, 0);
        cs[2] = axi4_cfg::from_param(AXI4_PARAM_MAX);
        foreach (cs[k]) begin
            for (int i = 0; i < 20; i++) begin
                axi4_aw_beat_t a = axi4_aw_beat_t'({rand_bits(), rand_bits()});
                axi4_ar_beat_t r = axi4_ar_beat_t'({rand_bits(), rand_bits()});
                axi4_w_beat_t  w = axi4_w_beat_t'({rand_bits(), rand_bits()});
                axi4_b_beat_t  b = axi4_b_beat_t'({rand_bits(), rand_bits()});
                axi4_r_beat_t  d = axi4_r_beat_t'({rand_bits(), rand_bits()});
                axi4_cfg c = cs[k];
                `FAIL_UNLESS(axi4_wire::unpack_aw(c, axi4_wire::pack_aw(c, a)) == c.mask_aw(a))
                `FAIL_UNLESS(axi4_wire::unpack_ar(c, axi4_wire::pack_ar(c, r)) == c.mask_ar(r))
                `FAIL_UNLESS(axi4_wire::unpack_w(c, axi4_wire::pack_w(c, w)) == c.mask_w(w))
                `FAIL_UNLESS(axi4_wire::unpack_b(c, axi4_wire::pack_b(c, b)) == c.mask_b(b))
                `FAIL_UNLESS(axi4_wire::unpack_r(c, axi4_wire::pack_r(c, d)) == c.mask_r(d))
            end
        end
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
