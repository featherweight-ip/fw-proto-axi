// L2 memory suite (l2_mem): transactions through the manager adapter, the
// link and the subordinate adapter to axi4_mem_model, and fw_mem_if
// accesses through axi4_to_mem. Checked through the API handles and the
// memory's backdoor (peek/poke); the same file runs in every view.
`include "svunit_defines.svh"

module l2_mem_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_types_pkg::*;
    import fw_proto_axi4_pkg::*;
    import axi4_test_pkg::*;

    string name = "l2_mem_ut";
    svunit_testcase svunit_ut;
    axi4_mem_env env;

    localparam int N = 32;

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        axi4_env_base::wait_ready();
        $cast(env, axi4_env_base::inst);
    endtask

    task teardown();
        `FAIL_UNLESS(env.idle())
        env.clear();
        svunit_ut.teardown();
    endtask

    // A write burst whose beat n carries byte 8'h10+n on every lane.
    function automatic axi4_xact wr(axi4_addr_t addr, axi4_size_e size,
            axi4_len_t len, axi4_burst_e burst, axi4_id_t id = 0, bit lock = 0);
        axi4_xact x = axi4_xact::new_write(addr, size, len, burst, id);
        x.lock = lock;
        for (int unsigned n = 0; n < x.n_beats(); n++) begin
            x.data.push_back({128{8'h10 + 8'(n)}});
            x.strb.push_back(beat_lanes(x, n, env.cfg.bus_bytes()));
            x.wuser.push_back('0);
        end
        return x;
    endfunction

    function automatic axi4_xact rd(axi4_addr_t addr, axi4_size_e size,
            axi4_len_t len, axi4_burst_e burst, axi4_id_t id = 0, bit lock = 0);
        axi4_xact x = axi4_xact::new_read(addr, size, len, burst, id);
        x.lock = lock;
        return x;
    endfunction

    // Bytes [a, a+n) of the memory all equal v.
    function automatic int unsigned diff_bytes(axi4_addr_t a, int unsigned n,
                                               byte unsigned v);
        int unsigned bad = 0;
        for (int unsigned i = 0; i < n; i++) if (env.mem.peek(a + i) != v) bad++;
        return bad;
    endfunction

    `SVUNIT_TESTS_BEGIN

    // fw_mem_if: 32-bit accesses on both halves of the 64-bit bus, a
    // 128-bit access (a two-beat burst); little-endian bytes in memory.
    `SVTEST(mem_if_rw)
        bit err;
        logic [31:0]  d32;
        logic [127:0] d128;
        env.m32.mem.write(err, 'h100, 32'h0403_0201, '1);
        `FAIL_UNLESS(!err)
        env.m32.mem.write(err, 'h104, 32'h0807_0605, '1);
        `FAIL_UNLESS(!err)
        for (int i = 0; i < 8; i++)
            `FAIL_UNLESS_EQUAL(env.mem.peek('h100 + i), i + 1)
        env.m32.mem.read(d32, err, 'h104);
        `FAIL_UNLESS(!err)
        `FAIL_UNLESS_EQUAL(d32, 32'h0807_0605)
        env.m128.mem.write(err, 'h200, 128'h0f0e0d0c_0b0a0908_07060504_03020100, '1);
        `FAIL_UNLESS(!err)
        for (int i = 0; i < 16; i++)
            `FAIL_UNLESS_EQUAL(env.mem.peek('h200 + i), i)
        env.m128.mem.read(d128, err, 'h200);
        `FAIL_UNLESS(!err)
        `FAIL_UNLESS_EQUAL(d128, 128'h0f0e0d0c_0b0a0908_07060504_03020100)
    `SVTEST_END

    // Only strobed bytes change; unwritten bytes read as `fill`.
    `SVTEST(strobes_and_fill)
        bit err;
        logic [31:0] d32;
        env.mem.fill = 8'ha5;
        env.m32.mem.read(d32, err, 'h300);
        `FAIL_UNLESS_EQUAL(d32, 32'ha5a5_a5a5)
        env.m32.mem.write(err, 'h304, 32'h4433_2211, 4'b0101);
        env.m32.mem.read(d32, err, 'h304);
        `FAIL_UNLESS_EQUAL(d32, 32'ha533_a511)
    `SVTEST_END

    // Narrow, unaligned INCR (A3.4.4): 2-byte transfers from 0x203. Beat 0
    // moves byte 0x203 only; beat n>0 moves 0x204+2(n-1) and the next.
    `SVTEST(narrow_unaligned_incr)
        axi4_xact w = wr('h203, AXI4_SIZE_2, 7, AXI4_BURST_INCR);
        axi4_xact r = rd('h203, AXI4_SIZE_2, 7, AXI4_BURST_INCR);
        env.mem.fill = 8'hee;
        env.mgr.xact.xact(w);
        `FAIL_UNLESS(w.resp === AXI4_RESP_OKAY)
        `FAIL_UNLESS_EQUAL(env.mem.peek('h202), 8'hee)
        `FAIL_UNLESS_EQUAL(env.mem.peek('h203), 8'h10)
        for (int n = 1; n < 8; n++)
            `FAIL_UNLESS_EQUAL(diff_bytes('h204 + 2*(n-1), 2, 8'h10 + n), 0)
        `FAIL_UNLESS_EQUAL(env.mem.peek('h212), 8'hee)
        env.mgr.xact.xact(r);
        `FAIL_UNLESS_EQUAL(r.data.size(), 8)
        `FAIL_UNLESS_EQUAL(r.data[0][63:0], 64'h0000_0000_1000_0000)
        `FAIL_UNLESS_EQUAL(r.data[1][63:0], 64'h0000_1111_0000_0000)
        `FAIL_UNLESS_EQUAL(r.data[2][63:0], 64'h1212_0000_0000_0000)
        `FAIL_UNLESS_EQUAL(r.data[3][63:0], 64'h0000_0000_0000_1313)
    `SVTEST_END

    // WRAP: 4 x 4 bytes from 0x308 wraps at the 16-byte boundary 0x300.
    `SVTEST(wrap_burst)
        axi4_xact w = wr('h308, AXI4_SIZE_4, 3, AXI4_BURST_WRAP);
        axi4_xact r = rd('h308, AXI4_SIZE_4, 3, AXI4_BURST_WRAP);
        env.mgr.xact.xact(w);
        `FAIL_UNLESS_EQUAL(diff_bytes('h308, 4, 8'h10), 0)
        `FAIL_UNLESS_EQUAL(diff_bytes('h30c, 4, 8'h11), 0)
        `FAIL_UNLESS_EQUAL(diff_bytes('h300, 4, 8'h12), 0)
        `FAIL_UNLESS_EQUAL(diff_bytes('h304, 4, 8'h13), 0)
        env.mgr.xact.xact(r);
        `FAIL_UNLESS_EQUAL(r.data[2][63:0], 64'h0000_0000_1212_1212)
        `FAIL_UNLESS_EQUAL(r.data[3][63:0], 64'h1313_1313_0000_0000)
    `SVTEST_END

    // FIXED: every beat at the same address; the last write wins.
    `SVTEST(fixed_burst)
        axi4_xact w = wr('h404, AXI4_SIZE_4, 3, AXI4_BURST_FIXED);
        axi4_xact r = rd('h404, AXI4_SIZE_4, 3, AXI4_BURST_FIXED);
        env.mgr.xact.xact(w);
        `FAIL_UNLESS_EQUAL(diff_bytes('h404, 4, 8'h13), 0)
        `FAIL_UNLESS_EQUAL(env.mem.peek('h408), 8'h00)
        env.mgr.xact.xact(r);
        foreach (r.data[n]) `FAIL_UNLESS_EQUAL(r.data[n][63:0], 64'h1313_1313_0000_0000)
    `SVTEST_END

    // Random legal INCR bursts with random strobes: reading a burst back
    // returns the strobed bytes written, `fill` elsewhere on active lanes.
    `SVTEST(random_incr_readback)
        int unsigned bad = 0;
        env.mem.fill = 8'h5a;
        for (int i = 0; i < N; i++) begin
            axi4_xact w, r;
            do w = rand_xact(env.cfg, 1); while (w.burst != AXI4_BURST_INCR);
            env.mem.clear();
            env.mem.fill = 8'h5a;
            env.mgr.xact.xact(w);
            if (w.resp !== AXI4_RESP_OKAY) bad++;
            r = rd(w.addr, w.size, w.len, w.burst, w.id);
            env.mgr.xact.xact(r);
            for (int unsigned n = 0; n < r.n_beats(); n++) begin
                int unsigned lo = axi4_beat_lower_lane(w.addr, w.size, w.len, w.burst, n, 8);
                int unsigned hi = axi4_beat_upper_lane(w.addr, w.size, w.len, w.burst, n, 8);
                for (int unsigned l = 0; l < 8; l++) begin
                    byte unsigned e = (l < lo || l > hi) ? 8'h00
                                    : w.strb[n][l] ? w.data[n][8*l +: 8] : 8'h5a;
                    if (r.data[n][8*l +: 8] !== e) bad++;
                end
            end
        end
        `FAIL_UNLESS_EQUAL(bad, 0)
    `SVTEST_END

    // Exclusive access (A7.2): read sets the reservation (EXOKAY); a matching
    // write succeeds once (EXOKAY); a repeat, or one after another ID wrote
    // the location, fails (OKAY, nothing written).
    `SVTEST(exclusive)
        axi4_xact r = rd('h500, AXI4_SIZE_8, 1, AXI4_BURST_INCR, 1, 1);
        axi4_xact w = wr('h500, AXI4_SIZE_8, 1, AXI4_BURST_INCR, 1, 1);
        axi4_xact w2 = wr('h500, AXI4_SIZE_8, 1, AXI4_BURST_INCR, 1, 1);
        axi4_xact other = wr('h508, AXI4_SIZE_1, 0, AXI4_BURST_INCR, 2);
        env.mgr.xact.xact(r);
        `FAIL_UNLESS(r.resp === AXI4_RESP_EXOKAY)
        `FAIL_UNLESS(r.rresp[1] === AXI4_RESP_EXOKAY)
        `FAIL_UNLESS(env.mem.has_resv(1))
        env.mgr.xact.xact(w);
        `FAIL_UNLESS(w.resp === AXI4_RESP_EXOKAY)
        `FAIL_UNLESS_EQUAL(diff_bytes('h508, 8, 8'h11), 0)
        `FAIL_UNLESS(!env.mem.has_resv(1))
        foreach (w2.data[n]) w2.data[n] = '0;
        env.mgr.xact.xact(w2);
        `FAIL_UNLESS(w2.resp === AXI4_RESP_OKAY)
        `FAIL_UNLESS_EQUAL(diff_bytes('h508, 8, 8'h11), 0)
        // another ID writes inside the reserved range: the reservation is lost
        r = rd('h500, AXI4_SIZE_8, 1, AXI4_BURST_INCR, 1, 1);
        env.mgr.xact.xact(r);
        env.mgr.xact.xact(other);
        `FAIL_UNLESS(!env.mem.has_resv(1))
        w2 = wr('h500, AXI4_SIZE_8, 1, AXI4_BURST_INCR, 1, 1);
        env.mgr.xact.xact(w2);
        `FAIL_UNLESS(w2.resp === AXI4_RESP_OKAY)
        `FAIL_UNLESS_EQUAL(env.mem.n_excl_ok, 1)
        `FAIL_UNLESS_EQUAL(env.mem.n_excl_fail, 2)
        // no exclusive support: OKAY
        env.mem.excl_support = 0;
        r = rd('h500, AXI4_SIZE_8, 1, AXI4_BURST_INCR, 1, 1);
        env.mgr.xact.xact(r);
        `FAIL_UNLESS(r.resp === AXI4_RESP_OKAY)
    `SVTEST_END

    // Error ranges: per-beat responses, no data moved on erroring beats,
    // err from fw_mem_if.
    `SVTEST(error_ranges)
        bit err;
        logic [31:0] d32;
        axi4_xact w = wr('h5f8, AXI4_SIZE_4, 3, AXI4_BURST_INCR);
        axi4_xact r = rd('h5f8, AXI4_SIZE_4, 3, AXI4_BURST_INCR);
        env.mem.add_err('h600, 'h6ff, AXI4_RESP_DECERR);
        env.mgr.xact.xact(w);
        `FAIL_UNLESS(w.resp === AXI4_RESP_DECERR)
        `FAIL_UNLESS_EQUAL(diff_bytes('h5f8, 4, 8'h10), 0)
        `FAIL_UNLESS_EQUAL(diff_bytes('h5fc, 4, 8'h11), 0)
        `FAIL_UNLESS_EQUAL(diff_bytes('h600, 8, 8'h00), 0)
        env.mgr.xact.xact(r);
        `FAIL_UNLESS(r.resp === AXI4_RESP_DECERR)
        `FAIL_UNLESS(r.rresp[1] === AXI4_RESP_OKAY)
        `FAIL_UNLESS(r.rresp[2] === AXI4_RESP_DECERR)
        env.m32.mem.write(err, 'h610, 32'h1, '1);
        `FAIL_UNLESS(err)
        env.m32.mem.read(d32, err, 'h610);
        `FAIL_UNLESS(err)
        env.m32.mem.read(d32, err, 'h700);
        `FAIL_UNLESS(!err)
    `SVTEST_END

    // Concurrent fw_mem_if writes with random service delays, then reads.
    `SVTEST(concurrent_mem_if)
        int unsigned bad = 0;
        env.sub.max_delay = 8;
        for (int i = 0; i < N; i++) begin
            automatic int k = i;
            fork begin
                bit err;
                env.m32.mem.write(err, 'h800 + 4*k, 32'hc0de_0000 + k, '1);
                if (err) bad++;
            end join_none
        end
        wait fork;
        for (int i = 0; i < N; i++) begin
            bit err;
            logic [31:0] d32;
            env.m32.mem.read(d32, err, 'h800 + 4*i);
            if (err || d32 !== 32'hc0de_0000 + i) bad++;
        end
        `FAIL_UNLESS_EQUAL(bad, 0)
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
