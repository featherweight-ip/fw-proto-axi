// Checker teeth in simulation (chk_teeth): drive axi4_checker's pins
// directly with scripted handshakes -- each sequence legal but for one
// planted fault -- and require that the side the broken rule binds counts a
// failure and the other side does not. A legal sequence must count none.
// The checker runs standalone (COUNT_ONLY), so there is one view.
`include "svunit_defines.svh"

module chk_teeth_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_types_pkg::*;

    string name = "chk_teeth_ut";
    svunit_testcase svunit_ut;

    localparam axi4_param_t P = '{ADDR_W: 32, DATA_W: 32, ID_W: 4, default: 0};

    logic aclk = 0, aresetn = 0;
    always #5 aclk = ~aclk;

    logic awvalid, awready, awlock, wvalid, wready, wlast;
    logic bvalid, bready, arvalid, arready, arlock, rvalid, rready, rlast;
    logic [3:0]  awid, bid, arid, rid;
    logic [31:0] awaddr, araddr, wdata, rdata;
    logic [7:0]  awlen, arlen;
    logic [2:0]  awsize, arsize, awprot, arprot;
    logic [1:0]  awburst, arburst, bresp, rresp;
    logic [3:0]  awcache, arcache, awqos, arqos, awregion, arregion, wstrb;
    logic        awuser, wuser, buser, aruser, ruser;

    axi4_checker #(.P(P), .MAX_OUT(4), .COUNT_ONLY(1)) u_chk (.*);

    int unsigned m0, s0;

    function void build();
        svunit_ut = new(name);
    endfunction

    // Every test starts from a fresh reset, all channels idle.
    task setup();
        svunit_ut.setup();
        {awvalid, awready, awlock, wvalid, wready, wlast} = '0;
        {bvalid, bready, arvalid, arready, arlock, rvalid, rready, rlast} = '0;
        {awid, bid, arid, rid, awaddr, araddr, wdata, rdata} = '0;
        {awlen, arlen, awsize, arsize, awprot, arprot} = '0;
        {awburst, arburst, bresp, rresp} = '0;
        {awcache, arcache, awqos, arqos, awregion, arregion, wstrb} = '0;
        {awuser, wuser, buser, aruser, ruser} = '0;
        awburst = 2'(AXI4_BURST_INCR); arburst = 2'(AXI4_BURST_INCR);
        @(negedge aclk) aresetn = 0;
        repeat (2) @(negedge aclk);
        aresetn = 1;
        repeat (2) @(negedge aclk);
        m0 = u_chk.n_err_m;
        s0 = u_chk.n_err_s;
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // Failures counted since setup, per side.
    function automatic int unsigned nm(); return u_chk.n_err_m - m0; endfunction
    function automatic int unsigned ns(); return u_chk.n_err_s - s0; endfunction

    // ---- one-cycle handshakes (driven at the falling edge) -------------
    task automatic aw(logic [3:0] id, logic [31:0] addr, logic [7:0] len,
                      logic [2:0] size = 3'd2, logic [1:0] burst = 2'(AXI4_BURST_INCR),
                      logic lock = 0);
        awid = id; awaddr = addr; awlen = len; awsize = size; awburst = burst; awlock = lock;
        awvalid = 1; awready = 1;
        @(negedge aclk) awvalid = 0; awready = 0;
    endtask

    task automatic w(logic last, logic [3:0] strb = 4'hf);
        wdata = $urandom; wstrb = strb; wlast = last;
        wvalid = 1; wready = 1;
        @(negedge aclk) wvalid = 0; wready = 0;
    endtask

    task automatic b(logic [3:0] id, logic [1:0] resp = 2'(AXI4_RESP_OKAY));
        bid = id; bresp = resp;
        bvalid = 1; bready = 1;
        @(negedge aclk) bvalid = 0; bready = 0;
    endtask

    task automatic ar(logic [3:0] id, logic [31:0] addr, logic [7:0] len);
        arid = id; araddr = addr; arlen = len; arsize = 3'd2;
        arvalid = 1; arready = 1;
        @(negedge aclk) arvalid = 0; arready = 0;
    endtask

    task automatic r(logic [3:0] id, logic last, logic [1:0] resp = 2'(AXI4_RESP_OKAY));
        rid = id; rdata = $urandom; rresp = resp; rlast = last;
        rvalid = 1; rready = 1;
        @(negedge aclk) rvalid = 0; rready = 0;
    endtask

    `SVUNIT_TESTS_BEGIN

    // No fault: a 2-beat write and a 2-beat read, W ahead of its AW too.
    `SVTEST(legal)
        aw(1, 32'h100, 1); w(0); w(1); b(1);
        w(0); w(1); aw(2, 32'h200, 1); b(2);
        ar(3, 32'h300, 1); r(3, 0); r(3, 1);
        `FAIL_UNLESS_EQUAL(nm(), 0)
        `FAIL_UNLESS_EQUAL(ns(), 0)
    `SVTEST_END

    // A3.1.2: a VALID high during reset.
    `SVTEST(valid_in_reset)
        aresetn = 0; awvalid = 1;
        @(negedge aclk) awvalid = 0; aresetn = 1;
        `FAIL_UNLESS(nm() > 0)
        `FAIL_UNLESS_EQUAL(ns(), 0)
    `SVTEST_END

    // A3.2.1: VALID dropped before READY.
    `SVTEST(valid_retract)
        awvalid = 1; awlen = 0;
        @(negedge aclk) awvalid = 0;
        @(negedge aclk);
        `FAIL_UNLESS(nm() > 0)
        `FAIL_UNLESS_EQUAL(ns(), 0)
    `SVTEST_END

    // A3.2.1: payload changed while VALID waits for READY.
    `SVTEST(payload_change)
        arvalid = 1; arlen = 0;
        @(negedge aclk) araddr = 32'h40;
        @(negedge aclk) arready = 1;
        @(negedge aclk) arvalid = 0; arready = 0;
        `FAIL_UNLESS(nm() > 0)
        `FAIL_UNLESS_EQUAL(ns(), 0)
    `SVTEST_END

    // A3.4.1: an INCR burst crossing a 4KB boundary.
    `SVTEST(burst_4k)
        aw(1, 32'hffc, 1);
        `FAIL_UNLESS(nm() > 0)
        `FAIL_UNLESS_EQUAL(ns(), 0)
    `SVTEST_END

    // A3.4.1: a WRAP burst of 3 beats.
    `SVTEST(wrap_len)
        aw(1, 32'h0, 2, 3'd2, 2'(AXI4_BURST_WRAP));
        `FAIL_UNLESS(nm() > 0)
        `FAIL_UNLESS_EQUAL(ns(), 0)
    `SVTEST_END

    // A3.4.1: WLAST on the first beat of a 2-beat burst.
    `SVTEST(wlast_early)
        aw(1, 32'h100, 1); w(1);
        `FAIL_UNLESS(nm() > 0)
        `FAIL_UNLESS_EQUAL(ns(), 0)
    `SVTEST_END

    // A3.4.4: a strobe on a lane the beat does not use (1-byte beat at lane 0).
    `SVTEST(wstrb_lane)
        aw(1, 32'h100, 0, 3'd0); w(1, 4'b0010); b(1);
        `FAIL_UNLESS(nm() > 0)
        `FAIL_UNLESS_EQUAL(ns(), 0)
    `SVTEST_END

    // A3.3.1: B before the last W beat.
    `SVTEST(b_before_wlast)
        aw(1, 32'h100, 1); w(0); b(1);
        `FAIL_UNLESS(ns() > 0)
        `FAIL_UNLESS_EQUAL(nm(), 0)
    `SVTEST_END

    // A5: BID matching no outstanding write.
    `SVTEST(bid_mismatch)
        aw(1, 32'h100, 0); w(1); b(2);
        `FAIL_UNLESS(ns() > 0)
        `FAIL_UNLESS_EQUAL(nm(), 0)
    `SVTEST_END

    // A5: R with no read outstanding.
    `SVTEST(r_without_ar)
        r(3, 1);
        `FAIL_UNLESS(ns() > 0)
        `FAIL_UNLESS_EQUAL(nm(), 0)
    `SVTEST_END

    // A3.4.1: RLAST on the first beat of a 2-beat burst.
    `SVTEST(rlast_early)
        ar(3, 32'h300, 1); r(3, 1);
        `FAIL_UNLESS(ns() > 0)
        `FAIL_UNLESS_EQUAL(nm(), 0)
    `SVTEST_END

    // A7.2: EXOKAY for a normal (lock = 0) write.
    `SVTEST(exokay_not_exclusive)
        aw(1, 32'h100, 0); w(1); b(1, 2'(AXI4_RESP_EXOKAY));
        `FAIL_UNLESS(ns() > 0)
        `FAIL_UNLESS_EQUAL(nm(), 0)
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
