// L2 memory suite body for one P (plan P5): transactions to
// axi4_mem_model through the adapters and the link, and fw_mem_if accesses through
// axi4_to_mem (axi4_l2_env). Checked through the API handles and the memory's
// backdoor (peek/poke). Expectations are by byte address and active lane, so they
// hold for any bus width. Each test task returns "" or the first failure.
module axi4_l2_mem_cell
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*,
           fw_proto_axi4_behav_pkg::*, axi4_l2_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    typedef axi4_l2_xact #(P)       xact_t;
    typedef axi4_types #(P)::addr_t addr_t;
    typedef axi4_types #(P)::data_t data_t;
    typedef axi4_types #(P)::strb_t strb_t;
    typedef axi4_types #(P)::r_t    r_t;
    typedef axi4_attr #(P)          at;

    localparam int unsigned N = 32;
    localparam int unsigned BUS = P.DATA_W / 8;

    axi4_l2_env #(P) env ();

    string m_err;
    function void fail(string msg);
        if (m_err == "") m_err = msg;
    endfunction

    task automatic start();
        m_err = "";
        wait (env.ready);
        env.serve(env.mem);
    endtask

    task automatic finish(output string err);
        string e;
        env.finish(e);
        fail(e);
        err = (m_err == "") ? "" : $sformatf("P(ID_W=%0d DATA_W=%0d) %s", P.ID_W, P.DATA_W, m_err);
    endtask

    // Bytes [a, a+n) of the memory all equal v.
    function automatic void expect_bytes(axi4_addr64_t a, int unsigned n, byte unsigned v,
                                         string what);
        for (int unsigned i = 0; i < n; i++)
            if (env.mem.peek(a + i) != v) begin
                fail($sformatf("%s: mem[0x%0h] = 0x%0h, expected 0x%0h", what, a + i,
                               env.mem.peek(a + i), v));
                return;
            end
    endfunction

    // A read returned, on each beat's active lanes, the memory's bytes, and 0 on
    // the other lanes. Beats from `zero_from` on errored: all 0.
    function automatic void expect_read(xact_t x, string what, int unsigned zero_from = 256);
        if (x.data.size() != x.n_beats()) begin
            fail($sformatf("%s: %0d beats for %0d", what, x.data.size(), x.n_beats()));
            return;
        end
        for (int unsigned n = 0; n < x.n_beats(); n++) begin
            strb_t        m = x.lanes(n);
            axi4_addr64_t b = x.beat_addr(n) & ~(axi4_addr64_t'(BUS) - 1);
            for (int unsigned l = 0; l < BUS; l++) begin
                byte unsigned e = (m[l] && n < zero_from) ? env.mem.peek(b + l) : 8'h00;
                if (x.data[n][8*l +: 8] !== e) begin
                    fail($sformatf("%s: beat %0d lane %0d = 0x%0h, expected 0x%0h", what, n, l,
                                   x.data[n][8*l +: 8], e));
                    return;
                end
            end
        end
    endfunction

    // The widest size up to 8 bytes the bus allows.
    localparam axi4_size_e SZ8 = axi4_size_e'((BUS < 8) ? $clog2(BUS) : 3);
    localparam int unsigned B8 = 1 << SZ8;

    // fw_mem_if: 32-bit accesses at neighbouring words, a 128-bit access (one or
    // more beats, by bus width); little-endian bytes in memory.
    task automatic t_mem_if_rw(output string err);
        bit err_;
        logic [31:0] d32;
        logic [127:0] d128;
        start();
        env.m32.write(err_, 'h100, 32'h0403_0201, '1);
        if (err_) fail("m32 write 0x100: err");
        env.m32.write(err_, 'h104, 32'h0807_0605, '1);
        for (int i = 0; i < 8; i++)
            if (env.mem.peek('h100 + i) != i + 1) fail($sformatf("mem[0x%0h]", 'h100 + i));
        env.m32.read(d32, err_, 'h104);
        if (err_ || d32 !== 32'h0807_0605) fail($sformatf("m32 read 0x104: 0x%0h", d32));
        env.m128.write(err_, 'h200, 128'h0f0e0d0c_0b0a0908_07060504_03020100, '1);
        if (err_) fail("m128 write: err");
        for (int i = 0; i < 16; i++)
            if (env.mem.peek('h200 + i) != i) fail($sformatf("mem[0x%0h]", 'h200 + i));
        env.m128.read(d128, err_, 'h200);
        if (err_ || d128 !== 128'h0f0e0d0c_0b0a0908_07060504_03020100)
            fail($sformatf("m128 read: 0x%0h", d128));
        finish(err);
    endtask

    // Only strobed bytes change; unwritten bytes read as `fill`.
    task automatic t_strobes_and_fill(output string err);
        bit err_;
        logic [31:0] d32;
        start();
        env.mem.fill = 8'ha5;
        env.m32.read(d32, err_, 'h300);
        if (d32 !== 32'ha5a5_a5a5) fail($sformatf("fill: 0x%0h", d32));
        env.m32.write(err_, 'h304, 32'h4433_2211, 4'b0101);
        env.m32.read(d32, err_, 'h304);
        if (d32 !== 32'ha533_a511) fail($sformatf("strobed: 0x%0h", d32));
        finish(err);
    endtask

    // Narrow, unaligned INCR (A3.4.4): 2-byte transfers from 0x203. Beat 0 moves
    // byte 0x203 only; beat n>0 moves 0x204+2(n-1) and the next.
    task automatic t_narrow_unaligned_incr(output string err);
        xact_t w, r;
        start();
        env.mem.fill = 8'hee;
        w = env.wr('h203, AXI4_SIZE_2, 7);
        env.run(w);
        if (w.resp !== AXI4_RESP_OKAY) fail($sformatf("write: %s", w.resp.name()));
        expect_bytes('h202, 1, 8'hee, "below");
        expect_bytes('h203, 1, 8'h10, "beat 0");
        for (int n = 1; n < 8; n++) expect_bytes('h204 + 2*(n-1), 2, 8'h10 + 8'(n), "beat");
        expect_bytes('h212, 1, 8'hee, "above");
        r = env.req(0, 'h203, AXI4_SIZE_2, 7);
        env.run(r);
        expect_read(r, "read");
        if (r.data[0][8*('h203 % BUS) +: 8] !== 8'h10) fail("read beat 0 lane");
        finish(err);
    endtask

    // WRAP: 4 x 4 bytes from 0x308 wraps at the 16-byte boundary 0x300.
    task automatic t_wrap_burst(output string err);
        xact_t w, r;
        start();
        w = env.wr('h308, AXI4_SIZE_4, 3, AXI4_BURST_WRAP);
        env.run(w);
        expect_bytes('h308, 4, 8'h10, "beat 0");
        expect_bytes('h30c, 4, 8'h11, "beat 1");
        expect_bytes('h300, 4, 8'h12, "beat 2");
        expect_bytes('h304, 4, 8'h13, "beat 3");
        r = env.req(0, 'h308, AXI4_SIZE_4, 3, AXI4_BURST_WRAP);
        env.run(r);
        expect_read(r, "read");
        finish(err);
    endtask

    // FIXED: every beat at the same address; the last write wins.
    task automatic t_fixed_burst(output string err);
        xact_t w, r;
        start();
        w = env.wr('h404, AXI4_SIZE_4, 3, AXI4_BURST_FIXED);
        env.run(w);
        expect_bytes('h404, 4, 8'h13, "last beat");
        expect_bytes('h408, 1, 8'h00, "after");
        r = env.req(0, 'h404, AXI4_SIZE_4, 3, AXI4_BURST_FIXED);
        env.run(r);
        expect_read(r, "read");
        foreach (r.data[n])
            if (r.data[n][8*('h404 % BUS) +: 32] !== 32'h1313_1313) fail($sformatf("beat %0d", n));
        finish(err);
    endtask

    // Random legal INCR bursts with random strobes: reading a burst back returns
    // the strobed bytes written and `fill` elsewhere on active lanes.
    task automatic t_random_incr_readback(output string err);
        start();
        for (int unsigned i = 0; i < N; i++) begin
            xact_t w = env.rand_req(1, AXI4_BURST_INCR);
            xact_t r;
            env.mem.clear();
            env.mem.fill = 8'h5a;
            w.attr.lock = 0;
            env.run(w);
            if (w.resp !== AXI4_RESP_OKAY) fail($sformatf("write %0d: %s", i, w.resp.name()));
            r = env.req(0, w.addr, w.attr.size, w.len, w.attr.burst, w.attr.id);
            env.run(r);
            if (r.data.size() != r.n_beats()) begin fail("beat count"); break; end
            for (int unsigned n = 0; n < r.n_beats(); n++) begin
                strb_t m = r.lanes(n);
                for (int unsigned l = 0; l < BUS; l++) begin
                    byte unsigned e = !m[l] ? 8'h00 : w.strb[n][l] ? w.data[n][8*l +: 8] : 8'h5a;
                    if (r.data[n][8*l +: 8] !== e) fail($sformatf("xact %0d beat %0d lane %0d", i, n, l));
                end
            end
        end
        finish(err);
    endtask

    // Exclusive access (A7.2): a read sets the reservation (EXOKAY); a matching
    // write succeeds once (EXOKAY); a repeat, or one after another ID wrote the
    // location, fails (OKAY, nothing written). Two beats of B8 bytes at 0x500.
    task automatic t_exclusive(output string err);
        int unsigned rid = (P.ID_W == 0) ? 0 : 1;
        xact_t r, w, w2, other;
        start();
        r = env.req(0, 'h500, SZ8, 1, AXI4_BURST_INCR, 1, 1);
        env.run(r);
        if (r.resp !== AXI4_RESP_EXOKAY) fail($sformatf("excl read: %s", r.resp.name()));
        if (!env.mem.has_resv(rid)) fail("no reservation after the exclusive read");
        w = env.wr('h500, SZ8, 1, AXI4_BURST_INCR, 1, 1);
        env.run(w);
        if (w.resp !== AXI4_RESP_EXOKAY) fail($sformatf("excl write: %s", w.resp.name()));
        expect_bytes('h500 + B8, B8, 8'h11, "excl write");
        if (env.mem.has_resv(rid)) fail("reservation kept after the exclusive write");
        w2 = env.wr('h500, SZ8, 1, AXI4_BURST_INCR, 1, 1);
        foreach (w2.data[n]) w2.data[n] = '0;
        env.run(w2);
        if (w2.resp !== AXI4_RESP_OKAY) fail($sformatf("repeat excl write: %s", w2.resp.name()));
        expect_bytes('h500 + B8, B8, 8'h11, "failed excl write wrote");
        // another ID writes inside the reserved range: the reservation is lost
        r = env.req(0, 'h500, SZ8, 1, AXI4_BURST_INCR, 1, 1);
        env.run(r);
        other = env.wr('h500 + B8, AXI4_SIZE_1, 0, AXI4_BURST_INCR, 2);
        env.run(other);
        if (env.mem.has_resv(rid)) fail("reservation kept after an overlapping write");
        w2 = env.wr('h500, SZ8, 1, AXI4_BURST_INCR, 1, 1);
        env.run(w2);
        if (w2.resp !== AXI4_RESP_OKAY) fail($sformatf("excl write after loss: %s", w2.resp.name()));
        if (env.mem.n_excl_ok != 1 || env.mem.n_excl_fail != 2)
            fail($sformatf("excl ok %0d fail %0d", env.mem.n_excl_ok, env.mem.n_excl_fail));
        // no exclusive support: OKAY
        env.mem.excl_support = 0;
        r = env.req(0, 'h500, SZ8, 1, AXI4_BURST_INCR, 1, 1);
        env.run(r);
        if (r.resp !== AXI4_RESP_OKAY) fail($sformatf("excl read, no support: %s", r.resp.name()));
        // every R beat of the exclusive reads carried the read's response
        env.u_link.settle();
        foreach (env.rs.r[i]) begin
            axi4_resp_e e = (i < 4) ? AXI4_RESP_EXOKAY : AXI4_RESP_OKAY;
            if (env.rs.r[i].resp !== e) fail($sformatf("R beat %0d: %s", i, env.rs.r[i].resp.name()));
        end
        finish(err);
    endtask

    // Error ranges: no data moved on erroring beats; the response is the worst
    // beat's; err from fw_mem_if.
    task automatic t_error_ranges(output string err);
        bit err_;
        logic [31:0] d32;
        xact_t w, r;
        start();
        env.mem.add_err('h600, 'h6ff, AXI4_RESP_DECERR);
        w = env.wr('h5f8, AXI4_SIZE_4, 3);
        env.run(w);
        if (w.resp !== AXI4_RESP_DECERR) fail($sformatf("write: %s", w.resp.name()));
        expect_bytes('h5f8, 4, 8'h10, "beat 0");
        expect_bytes('h5fc, 4, 8'h11, "beat 1");
        expect_bytes('h600, 8, 8'h00, "erroring beats");
        r = env.req(0, 'h5f8, AXI4_SIZE_4, 3);
        env.run(r);
        if (r.resp !== AXI4_RESP_DECERR) fail($sformatf("read: %s", r.resp.name()));
        expect_read(r, "read", 2);
        // On the burst API each beat has its own response.
        begin
            r_t rr[$];
            axi4_resp_e e[4] = '{AXI4_RESP_OKAY, AXI4_RESP_OKAY, AXI4_RESP_DECERR, AXI4_RESP_DECERR};
            env.blk.read(at::to_ar('h5f8, 4, r.attr), rr);
            if (rr.size() != 4) fail($sformatf("blk.read: %0d beats", rr.size()));
            else foreach (rr[n])
                if (rr[n].resp !== e[n]) fail($sformatf("blk.read beat %0d: %s", n, rr[n].resp.name()));
        end
        env.m32.write(err_, 'h610, 32'h1, '1);
        if (!err_) fail("m32 write in the error range: no err");
        env.m32.read(d32, err_, 'h610);
        if (!err_) fail("m32 read in the error range: no err");
        env.m32.read(d32, err_, 'h700);
        if (err_) fail("m32 read outside the error range: err");
        finish(err);
    endtask

    // Concurrent fw_mem_if writes with random service delays, then reads.
    task automatic t_concurrent_mem_if(output string err);
        start();
        env.sub.max_delay = 80;
        env.sub.r_interleave = 1;   // reordered and interleaved across IDs
        for (int i = 0; i < N; i++) begin
            automatic int k = i;
            fork begin
                bit e;
                env.m32.write(e, 'h800 + 4*k, 32'hc0de_0000 + k, '1);
                if (e) fail($sformatf("write %0d: err", k));
            end join_none
        end
        wait fork;
        for (int i = 0; i < N; i++) begin
            bit e;
            logic [31:0] d32;
            env.m32.read(d32, e, 'h800 + 4*i);
            if (e || d32 !== 32'hc0de_0000 + i) fail($sformatf("read %0d: 0x%0h", i, d32));
        end
        finish(err);
    endtask
endmodule
