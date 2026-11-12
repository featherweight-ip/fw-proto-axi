// The generated transactors back to back (plan P4.2), for one P: axi4_mgr_xtor's
// pins wired straight to axi4_sub_xtor's, with axi4_mon_xtor and axi4_checker
// (COUNT_ONLY) on the link. The class side is the generated bridges: the manager
// bridge's responses and the subordinate bridge's requests land in inboxes, and
// the monitor bridge's listener calls are recorded. run() sends N writes and N
// reads, one at a time, protocol-legal, and checks every beat at the far end, at
// the monitor, the checker's counts and the AXI4 rules on the monitor's events
// (plan P7). It returns "" or the first failure.
module axi4_xtor_ns_b2b
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*,
           fw_proto_axi4_rules_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    typedef axi4_types #(P)::aw_t aw_t;
    typedef axi4_types #(P)::w_t  w_t;
    typedef axi4_types #(P)::b_t  b_t;
    typedef axi4_types #(P)::ar_t ar_t;
    typedef axi4_types #(P)::r_t  r_t;
    typedef axi4_payloads #(P) pl;

    localparam int unsigned IW_ = w1(P.ID_W), AW_ = P.ADDR_W, DW_ = P.DATA_W;
    localparam int unsigned AUW_ = w1(P.AWUSER_W), WUW_ = w1(P.WUSER_W), BUW_ = w1(P.BUSER_W);
    localparam int unsigned RAW_ = w1(P.ARUSER_W), RUW_ = w1(P.RUSER_W);

    // The checker takes the old package's parameter struct.
    localparam axi4_types_pkg::axi4_param_t CP = '{
        ADDR_W: P.ADDR_W, DATA_W: P.DATA_W, ID_W: P.ID_W, AWUSER_W: P.AWUSER_W,
        WUSER_W: P.WUSER_W, BUSER_W: P.BUSER_W, ARUSER_W: P.ARUSER_W, RUSER_W: P.RUSER_W};

    bit   aclk = 0;
    logic aresetn = 0;
    always #5 aclk = ~aclk;

    // The link, named as on axi4_checker.
    logic awvalid, awready, awlock;
    logic [IW_-1:0] awid;
    logic [AW_-1:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize, awprot;
    logic [1:0] awburst;
    logic [3:0] awcache, awqos, awregion;
    logic [AUW_-1:0] awuser;
    logic wvalid, wready, wlast;
    logic [DW_-1:0] wdata;
    logic [DW_/8-1:0] wstrb;
    logic [WUW_-1:0] wuser;
    logic bvalid, bready;
    logic [IW_-1:0] bid;
    logic [1:0] bresp;
    logic [BUW_-1:0] buser;
    logic arvalid, arready, arlock;
    logic [IW_-1:0] arid;
    logic [AW_-1:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize, arprot;
    logic [1:0] arburst;
    logic [3:0] arcache, arqos, arregion;
    logic [RAW_-1:0] aruser;
    logic rvalid, rready, rlast;
    logic [IW_-1:0] rid;
    logic [DW_-1:0] rdata;
    logic [1:0] rresp;
    logic [RUW_-1:0] ruser;

    axi4_mgr_xtor #(P) u_mgr (.*);
    axi4_sub_xtor #(P) u_sub (.*);
    axi4_mon_xtor #(P) u_mon (.*);
    axi4_checker #(.P(CP), .COUNT_ONLY(1)) u_chk (.*);

    // Monitor listeners: what the pins carried, pre (first valid) and post (handshake).
    class req_rec extends axi4_req_if_listener_base #(P);
        int unsigned n_pre[3];
        aw_t aw_q[$]; w_t w_q[$]; ar_t ar_q[$];
        virtual function void aw_pre(input aw_t t); n_pre[0]++; endfunction
        virtual function void w_pre(input w_t t);   n_pre[1]++; endfunction
        virtual function void ar_pre(input ar_t t); n_pre[2]++; endfunction
        virtual function void aw_post(input aw_t t); aw_q.push_back(t); endfunction
        virtual function void w_post(input w_t t);   w_q.push_back(t);  endfunction
        virtual function void ar_post(input ar_t t); ar_q.push_back(t); endfunction
    endclass

    class rsp_rec extends axi4_rsp_if_listener_base #(P);
        int unsigned n_pre[2];
        b_t b_q[$]; r_t r_q[$];
        virtual function void b_pre(input b_t t); n_pre[0]++; endfunction
        virtual function void r_pre(input r_t t); n_pre[1]++; endfunction
        virtual function void b_post(input b_t t); b_q.push_back(t); endfunction
        virtual function void r_post(input r_t t); r_q.push_back(t); endfunction
    endclass

    axi4_mgr_xtor_bridge #(P) mb;
    axi4_sub_xtor_bridge #(P) sb;
    axi4_mon_xtor_bridge #(P) monb;
    axi4_rules #(P)           rules;     // on the monitor's events (pins)
    axi4_rsp_if_inbox #(P)    m_in;      // what the manager receives
    axi4_req_if_inbox #(P)    s_in;      // what the subordinate receives
    req_rec rq;
    rsp_rec rs;

    initial begin
        m_in = new;
        s_in = new;
        mb = new(u_mgr.u_if, m_in);
        sb = new(u_sub.u_if, s_in);
        monb = new(u_mon.u_if);
        rq = new;
        rs = new;
        monb.req.add_listener(rq);
        monb.rsp.add_listener(rs);
        rules = new("b2b", 1);
        monb.req.add_listener(rules.req);
        monb.rsp.add_listener(rules.rsp);
        fork
            mb.run();
            sb.run();
            monb.run();
        join_none
        repeat (4) @(posedge aclk);
        aresetn = 1;
    end

    // Random bits, as wide as any field.
    function automatic logic [1023:0] rnd();
        logic [1023:0] v;
        for (int i = 0; i < 32; i++) v[i*32 +: 32] = $urandom;
        return v;
    endfunction

    // Full-width INCR bursts of 2 beats, 0x100 apart: aligned, no 4K crossing.
    function automatic void ax(int unsigned i, output aw_t a);
        a = aw_t'(rnd());
        a.addr = AW_'(i * 'h100);
        a.len = 8'd1;
        a.size = axi4_size_e'($clog2(DW_ / 8));
        a.burst = AXI4_BURST_INCR;
        a.lock = 1'b0;
        a.cache = 4'b0011;
    endfunction

    function automatic string cmp(bit ok, string what, int unsigned i, string diff);
        return ok ? "" : $sformatf("P(ID_W=%0d DATA_W=%0d) %s %0d:%s", P.ID_W, DW_, what, i, diff);
    endfunction

    localparam int unsigned N = 6;

    task automatic run(output string err);
        aw_t aw_s[$], aw_g; w_t w_s[$], w_g; b_t b_s[$], b_g;
        ar_t ar_s[$], ar_g; r_t r_s[$], r_g;
        string d;
        err = "";
        wait (aresetn);
        for (int unsigned i = 0; i < N && err == ""; i++) begin
            aw_t a; ar_t ra; w_t w; b_t b; r_t r;
            // write: AW, two W beats, then B
            ax(i, a);
            aw_s.push_back(a);
            mb.aw(a);
            for (int k = 0; k < 2; k++) begin
                w = w_t'(rnd());
                w.strb = '1;
                w.last = (k == 1);
                w_s.push_back(w);
                mb.w(w);
            end
            s_in.aw_in.get(aw_g);
            if (!pl::aw_compare(aw_g, a, d)) err = cmp(0, "aw", i, d);
            for (int k = 0; k < 2 && err == ""; k++) begin
                s_in.w_in.get(w_g);
                if (!pl::w_compare(w_g, w_s[2*i+k], d)) err = cmp(0, "w", i, d);
            end
            b = b_t'(rnd());
            b.id = a.id;
            b.resp = AXI4_RESP_OKAY;
            b_s.push_back(b);
            sb.b(b);
            m_in.b_in.get(b_g);
            if (err == "" && !pl::b_compare(b_g, b, d)) err = cmp(0, "b", i, d);
            // read: AR, then two R beats
            ax(i + N, a);
            ra = ar_t'(rnd());
            ra.id = a.id;
            ra.addr = a.addr;
            ra.len = a.len;
            ra.size = a.size;
            ra.burst = a.burst;
            ra.lock = a.lock;
            ra.cache = a.cache;
            ar_s.push_back(ra);
            mb.ar(ra);
            s_in.ar_in.get(ar_g);
            if (err == "" && !pl::ar_compare(ar_g, ra, d)) err = cmp(0, "ar", i, d);
            for (int k = 0; k < 2; k++) begin
                r = r_t'(rnd());
                r.id = ra.id;
                r.resp = AXI4_RESP_OKAY;
                r.last = (k == 1);
                r_s.push_back(r);
                sb.r(r);
                m_in.r_in.get(r_g);
                if (err == "" && !pl::r_compare(r_g, r, d)) err = cmp(0, "r", i, d);
            end
        end
        repeat (8) @(posedge aclk);
        if (err != "") return;

        // The monitor saw every beat once, in order, with one first-valid call each.
        if (rq.aw_q.size() != N || rq.w_q.size() != 2*N || rq.ar_q.size() != N
                || rs.b_q.size() != N || rs.r_q.size() != 2*N) begin
            err = $sformatf("monitor counts aw=%0d w=%0d b=%0d ar=%0d r=%0d", rq.aw_q.size(),
                            rq.w_q.size(), rs.b_q.size(), rq.ar_q.size(), rs.r_q.size());
            return;
        end
        if (rq.n_pre != '{N, 2*N, N} || rs.n_pre != '{N, 2*N}) begin
            err = $sformatf("monitor pre counts aw=%0d w=%0d ar=%0d b=%0d r=%0d", rq.n_pre[0],
                            rq.n_pre[1], rq.n_pre[2], rs.n_pre[0], rs.n_pre[1]);
            return;
        end
        foreach (aw_s[i]) if (!pl::aw_compare(rq.aw_q[i], aw_s[i], d)) begin err = cmp(0, "mon aw", i, d); return; end
        foreach (w_s[i])  if (!pl::w_compare(rq.w_q[i], w_s[i], d))    begin err = cmp(0, "mon w", i, d);  return; end
        foreach (b_s[i])  if (!pl::b_compare(rs.b_q[i], b_s[i], d))    begin err = cmp(0, "mon b", i, d);  return; end
        foreach (ar_s[i]) if (!pl::ar_compare(rq.ar_q[i], ar_s[i], d)) begin err = cmp(0, "mon ar", i, d); return; end
        foreach (r_s[i])  if (!pl::r_compare(rs.r_q[i], r_s[i], d))    begin err = cmp(0, "mon r", i, d);  return; end

        if (u_chk.n_err_m != 0 || u_chk.n_err_s != 0)
            err = $sformatf("P(ID_W=%0d) checker: %0d manager, %0d subordinate violations",
                            P.ID_W, u_chk.n_err_m, u_chk.n_err_s);
        else if (rules.n_fail() != 0)
            err = $sformatf("P(ID_W=%0d) rules failed: %s (first: %s)", P.ID_W, rules.failed(),
                            rules.first());
    endtask
endmodule
