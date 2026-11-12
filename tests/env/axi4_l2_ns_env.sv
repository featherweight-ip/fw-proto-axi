// L2 environment for one P (plan P5): whole transactions over the L1 link of the
// image's view (axi4_l1_ns_link, tests/env/<view>/).
//
//   xact (proxy) -> axi4_xact_on_burst -> blk (axi4_burst_blocking)
//     -> breq (proxy) -> mgr (axi4_mgr_adapter) -> link -> sub (axi4_sub_adapter)
//     -> tgt_b (axi4_burst_on_xact) -> tgt  |  mem  |  btgt
// and the responses back: target -> sub -> link -> mgr -> brsp (proxy) -> blk.
//
// Members the L2 cells use:
//   xact            the convenience API (proxy), blocking
//   blk             the burst API, blocking: write(aw, w, b), read(ar, r)
//   breq, brsp      the burst API's two directions (proxies): requests, responses
//   xrec, brec      listeners on xact, and on breq + brsp (every request, response)
//   mgr, sub        the adapters; sub.max_delay reorders responses across IDs
//   serve(t)        what sub calls: tgt_b (the plain test target tgt behind the shim),
//                   mem (the memory model) or btgt (a burst target with random
//                   per-beat responses and USER); tgt.max_delay slows each call
//   m32, m128       fw_mem_if over xact, 32- and 128-bit accesses
//   rq, rs          every beat on the link (pin monitor in xtor, proxies in tlm)
//   blk_d, mgr_d,   the direct path, no link: blk_d -> mgr_d -> isub, a stub that
//   isub, sink      answers inside the call; sink takes mgr_d's responses when a
//                   test calls mgr_d itself
//   check_bursts()  random bursts through a blocking shim, checked against a log
//   rules, rules_d  the AXI4 rules (plan P7) on the link (its pin monitor in xtor,
//                   its proxies in tlm) and on the direct path (proxies around isub)
//   u_link          the link: set_knob(), settle(), errors()
module axi4_l2_ns_env
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*,
           fw_proto_axi4_behav_pkg::*, fw_proto_axi4_rules_pkg::*, axi4_l2_ns_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    typedef axi4_l2_xact #(P)       xact_t;
    typedef axi4_payloads #(P)      pl;
    typedef axi4_attr #(P)          at;
    typedef axi4_types #(P)::aw_t   aw_t;
    typedef axi4_types #(P)::w_t    w_t;
    typedef axi4_types #(P)::b_t    b_t;
    typedef axi4_types #(P)::ar_t   ar_t;
    typedef axi4_types #(P)::r_t    r_t;
    typedef axi4_types #(P)::attr_t attr_t;
    typedef axi4_types #(P)::addr_t addr_t;
    typedef axi4_types #(P)::data_t data_t;
    typedef axi4_types #(P)::strb_t strb_t;
    localparam int unsigned BUS = P.DATA_W / 8;

    axi4_l1_ns_link #(P) u_link ();

    // ---- a trivial target: logs what it serves (on arrival), answers reads
    // with data_of(), everything with `resp` (or err_resp inside [err_lo,
    // err_hi]); with max_delay != 0 each call first takes a random 0..max_delay,
    // so calls finish out of order.
    class test_target extends axi4_xact_if_base #(P);
        xact_t       seen[$];
        axi4_resp_e  resp = AXI4_RESP_OKAY;
        int unsigned max_delay;
        addr_t      err_lo = '1, err_hi = '0;
        axi4_resp_e err_resp = AXI4_RESP_SLVERR;

        static function data_t data_of(addr_t addr, int unsigned n);
            data_t d;
            for (int unsigned i = 0; i < P.DATA_W / 32; i++)
                d[32*i +: 32] = 32'(addr) ^ (32'h9e37_79b9 * (n + 1)) ^ i;
            return d;
        endfunction

        local function axi4_resp_e resp_of(addr_t a);
            return (a >= err_lo && a <= err_hi) ? err_resp : resp;
        endfunction

        virtual task write(input addr_t addr, input data_t data[$], input strb_t strb[$],
                           input attr_t attr, output axi4_resp_e resp);
            xact_t x = new;
            x.write = 1; x.addr = addr; x.attr = attr; x.data = data; x.strb = strb;
            x.len = 8'(data.size() - 1);
            x.resp = resp_of(addr);
            seen.push_back(x);
            if (max_delay != 0) #($urandom_range(max_delay));
            resp = x.resp;
        endtask

        virtual task read(input addr_t addr, input int unsigned beats, input attr_t attr,
                          output data_t data[$], output axi4_resp_e resp);
            xact_t x = new;
            x.write = 0; x.addr = addr; x.attr = attr; x.len = 8'(beats - 1);
            x.resp = resp_of(addr);
            for (int unsigned n = 0; n < beats; n++) x.data.push_back(data_of(addr, n));
            seen.push_back(x);
            if (max_delay != 0) #($urandom_range(max_delay));
            data = x.data;
            resp = x.resp;
        endtask
    endclass

    // ---- a burst target: logs every burst as it arrives and answers at once
    // with random B and R beats (per-beat RRESP, USER, and garbage RLAST, which
    // the subordinate adapter must replace; the ID is the request's, as the
    // burst API requires), kept for the test to compare.
    class burst_seen;
        bit  write;
        aw_t aw; w_t w[$]; b_t b;
        ar_t ar; r_t r[$];
    endclass

    // Every burst a target served, in arrival order.
    class burst_log;
        burst_seen seen[$];
    endclass

    // Random beats, ID as the request's (the burst API requires it).
    class burst_rnd;
        static function axi4_resp_e resp();
            case ($urandom_range(2, 0))
                0: return AXI4_RESP_OKAY;
                1: return AXI4_RESP_SLVERR;
                default: return AXI4_RESP_DECERR;
            endcase
        endfunction

        static function logic [1023:0] bits();
            logic [1023:0] v;
            for (int i = 0; i < 32; i++) v[i*32 +: 32] = $urandom;
            return v;
        endfunction
    endclass

    class burst_target extends axi4_burst_req_if_base #(P);
        burst_log              log = new;
        axi4_burst_rsp_if #(P) rsp;

        virtual task write_burst(input aw_t aw, input w_t w[$]);
            burst_seen s = new;
            b_t        b = b_t'(burst_rnd::bits());
            s.write = 1; s.aw = aw; s.w = w;
            b.id = aw.id;
            b.resp = burst_rnd::resp();
            s.b = b;
            log.seen.push_back(s);
            rsp.write_resp(b);
        endtask

        virtual task read_burst(input ar_t ar);
            burst_seen s = new;
            s.write = 0; s.ar = ar;
            for (int unsigned n = 0; n < axi4_burst_beats(ar.len); n++) begin
                r_t f = r_t'(burst_rnd::bits());
                f.id = ar.id;
                f.resp = burst_rnd::resp();
                s.r.push_back(f);
            end
            log.seen.push_back(s);
            foreach (s.r[n]) rsp.read_resp(s.r[n]);
        endtask
    endclass

    // ---- the direct path, no link: blk_d -> mgr_d -> isub. isub stands in for
    // the link and the subordinate end and answers inside the call: B within
    // the last W beat's call, every R beat within the AR's call (random beats,
    // as the link carries them). With beat_delay != 0 each beat first takes
    // that long, so concurrent callers' beats can overlap. W follows AW order.
    class inline_sub extends axi4_req_if_base #(P);
        axi4_rsp_if #(P) rsp;
        int unsigned     beat_delay;
        int unsigned     n_errors;
        burst_log        log = new;
        local burst_seen m_open[$];   // writes short of W beats

        virtual task aw(input aw_t t);
            burst_seen s = new;
            if (beat_delay != 0) #(beat_delay);
            s.write = 1; s.aw = t;
            log.seen.push_back(s);
            m_open.push_back(s);
        endtask

        virtual task w(input w_t t);
            burst_seen s;
            if (beat_delay != 0) #(beat_delay);
            if (m_open.size() == 0) begin
                n_errors++;
                $display("%0t inline_sub: ERROR W beat with no AW open", $time);
                return;
            end
            s = m_open[0];
            s.w.push_back(t);
            if (!t.last) return;
            void'(m_open.pop_front());
            s.b = b_t'(burst_rnd::bits());
            s.b.id = s.aw.id;
            s.b.resp = burst_rnd::resp();
            s.b = pl::b_mask(s.b);
            rsp.b(s.b);
        endtask

        virtual task ar(input ar_t t);
            burst_seen   s = new;
            int unsigned n = axi4_burst_beats(t.len);
            if (beat_delay != 0) #(beat_delay);
            s.write = 0; s.ar = t;
            log.seen.push_back(s);
            for (int unsigned i = 0; i < n; i++) begin
                r_t f = r_t'(burst_rnd::bits());
                f.id = t.id;
                f.resp = burst_rnd::resp();
                f.last = (i == n - 1);
                f = pl::r_mask(f);
                s.r.push_back(f);
                rsp.r(f);
            end
        endtask

        function bit idle();
            return m_open.size() == 0;
        endfunction

        function void clear();
            log.seen.delete();
            m_open.delete();
            beat_delay = 0;
            n_errors = 0;
        endfunction
    endclass

    // What mgr_d passes up when the test calls it directly (no blocking shim).
    class rsp_sink extends axi4_burst_rsp_if_base #(P);
        b_t b[$];
        r_t r[$];
        virtual task write_resp(input b_t t); b.push_back(t); endtask
        virtual task read_resp(input r_t t); r.push_back(t); endtask
    endclass

    // ---- observers
    class xact_rec extends axi4_xact_if_listener_base #(P);
        string ev[$];            // "write_pre", "write_post", ... in call order
        xact_t calls[$];         // one per post: request and response as observed
        virtual function void write_pre(input addr_t addr, input data_t data[$],
                                        input strb_t strb[$], input attr_t attr);
            ev.push_back("write_pre");
        endfunction
        virtual function void write_post(input addr_t addr, input data_t data[$],
                                         input strb_t strb[$], input attr_t attr,
                                         input axi4_resp_e resp);
            xact_t x = new;
            x.write = 1; x.addr = addr; x.data = data; x.strb = strb; x.attr = attr;
            x.resp = resp;
            ev.push_back("write_post");
            calls.push_back(x);
        endfunction
        virtual function void read_pre(input addr_t addr, input int unsigned beats,
                                       input attr_t attr);
            ev.push_back("read_pre");
        endfunction
        virtual function void read_post(input addr_t addr, input int unsigned beats,
                                        input attr_t attr, input data_t data[$],
                                        input axi4_resp_e resp);
            xact_t x = new;
            x.write = 0; x.addr = addr; x.len = 8'(beats - 1); x.attr = attr; x.data = data;
            x.resp = resp;
            ev.push_back("read_post");
            calls.push_back(x);
        endfunction
        function void clear(); ev.delete(); calls.delete(); endfunction
    endclass

    // Every burst request and response (all traffic passes breq and brsp), for
    // the watchdog: a transaction is open from its request to its last response.
    class burst_rec;
        int unsigned n_open;     // transactions in flight
        time         t_last;     // the last request or response
        int unsigned n_calls;    // transactions completed
    endclass

    class burst_req_rec extends axi4_burst_req_if_listener_base #(P);
        burst_rec c;
        function new(burst_rec c_); c = c_; endfunction
        virtual function void write_burst_pre(input aw_t aw, input w_t w[$]);
            c.n_open++; c.t_last = $time;
        endfunction
        virtual function void read_burst_pre(input ar_t ar);
            c.n_open++; c.t_last = $time;
        endfunction
    endclass

    class burst_rsp_rec extends axi4_burst_rsp_if_listener_base #(P);
        burst_rec c;
        function new(burst_rec c_); c = c_; endfunction
        virtual function void write_resp_post(input b_t b);
            c.n_open--; c.t_last = $time; c.n_calls++;
        endfunction
        virtual function void read_resp_post(input r_t r);
            c.t_last = $time;
            if (r.last) begin c.n_open--; c.n_calls++; end
        endfunction
    endclass

    class req_rec extends axi4_req_if_listener_base #(P);
        aw_t aw[$]; w_t w[$]; ar_t ar[$];
        virtual function void aw_post(input aw_t t); aw.push_back(t); endfunction
        virtual function void w_post(input w_t t);   w.push_back(t);  endfunction
        virtual function void ar_post(input ar_t t); ar.push_back(t); endfunction
        function void clear(); aw.delete(); w.delete(); ar.delete(); endfunction
    endclass

    class rsp_rec extends axi4_rsp_if_listener_base #(P);
        b_t b[$]; r_t r[$];
        virtual function void b_post(input b_t t); b.push_back(t); endfunction
        virtual function void r_post(input r_t t); r.push_back(t); endfunction
        function void clear(); b.delete(); r.delete(); endfunction
    endclass

    axi4_mgr_adapter #(P)        mgr;
    axi4_sub_adapter #(P)        sub;
    axi4_burst_req_if_proxy #(P) breq;
    axi4_burst_rsp_if_proxy #(P) brsp;
    axi4_burst_blocking #(P)     blk;
    axi4_xact_on_burst #(P)      shim;
    axi4_xact_if_proxy #(P)      xact;
    test_target                  tgt = new;
    axi4_burst_on_xact #(P)      tgt_b = new(tgt);
    burst_target                 btgt = new;
    inline_sub                   isub = new;
    axi4_mgr_adapter #(P)        mgr_d;
    axi4_burst_blocking #(P)     blk_d;
    rsp_sink                     sink = new;
    axi4_req_if_proxy #(P)       isub_px = new(isub);
    axi4_rsp_if_proxy #(P)       mgr_d_px;
    axi4_rules #(P)              rules, rules_d;
    axi4_mem_model #(P)          mem = new;
    burst_rec                    brec = new;
    burst_req_rec                brq = new(brec);
    burst_rsp_rec                brs = new(brec);
    axi4_to_mem #(P, logic [31:0], logic [31:0], logic [3:0])    m32;
    axi4_to_mem #(P, logic [31:0], logic [127:0], logic [15:0])  m128;
    xact_rec                xrec = new;
    req_rec                 rq = new;
    rsp_rec                 rs = new;
    bit                     ready;

    initial begin
        wait (u_link.up);
        mgr = new(u_link.req);
        sub = new(u_link.rsp, tgt_b);
        u_link.attach(mgr, sub);
        tgt_b.rsp = sub;
        mem.rsp = sub;
        btgt.rsp = sub;
        breq = new(mgr);
        breq.add_listener(brq);
        blk = new(breq);
        brsp = new(blk);
        brsp.add_listener(brs);
        mgr.up = brsp;
        shim = new(blk);
        xact = new(shim);
        xact.add_listener(xrec);
        m32 = new(xact);
        m128 = new(xact);
        u_link.add_req_listener(rq);
        u_link.add_rsp_listener(rs);
        mgr_d = new(isub_px);
        blk_d = new(mgr_d);
        mgr_d.up = blk_d;
        mgr_d_px = new(mgr_d);
        isub.rsp = mgr_d_px;
        rules = new("link", u_link.at_pins());
        u_link.add_req_listener(rules.req);
        u_link.add_rsp_listener(rules.rsp);
        rules_d = new("direct");
        isub_px.add_listener(rules_d.req);
        mgr_d_px.add_listener(rules_d.rsp);
        ready = 1;
    end

    // Watchdog: a lost response leaves its caller waiting forever while the clock
    // runs on. With transactions in flight, or blocking callers still waiting
    // (a response that reached no waiter), and no request or response for STALL
    // time units, stop the run and say so.
    localparam time STALL = 100_000;
    initial begin
        wait (ready);
        forever begin
            #(STALL);
            if ((brec.n_open != 0 || blk.n_waiting != 0 || blk_d.n_waiting != 0) &&
                $time - brec.t_last >= STALL)
                $fatal(1, "axi4_l2_ns_env (ID_W=%0d DATA_W=%0d): %0d transactions open, %0d callers waiting, since %0t (mgr errors %0d, sub errors %0d, blk errors %0d)",
                       P.ID_W, P.DATA_W, brec.n_open, blk.n_waiting + blk_d.n_waiting, brec.t_last, mgr.n_errors,
                       sub.n_errors, blk.n_errors);
        end
    end

    // What the subordinate adapter serves: tgt_b, mem or btgt.
    function void serve(axi4_burst_req_if #(P) t);
        sub.tgt = t;
    endfunction

    // ---- requests

    function automatic logic [1023:0] rnd();
        logic [1023:0] v;
        for (int i = 0; i < 32; i++) v[i*32 +: 32] = $urandom;
        return v;
    endfunction

    // A request (no response) with the attributes as given.
    function automatic xact_t req(bit write, addr_t addr, axi4_size_e size, int unsigned len,
                                  axi4_burst_e burst = AXI4_BURST_INCR, int unsigned id = 0,
                                  bit lock = 0);
        xact_t x = new;
        x.write = write; x.addr = addr; x.len = 8'(len);
        x.attr = '0;
        x.attr.size = size; x.attr.burst = burst; x.attr.lock = lock;
        x.attr.id = id[$bits(x.attr.id)-1:0];
        return x;
    endfunction

    // A write whose beat n carries byte 8'h10+n on every active lane.
    function automatic xact_t wr(addr_t addr, axi4_size_e size, int unsigned len,
                                 axi4_burst_e burst = AXI4_BURST_INCR, int unsigned id = 0,
                                 bit lock = 0);
        xact_t x = req(1, addr, size, len, burst, id, lock);
        for (int unsigned n = 0; n < x.n_beats(); n++) begin
            data_t d;
            for (int unsigned l = 0; l < BUS; l++) d[8*l +: 8] = 8'h10 + 8'(n);
            x.data.push_back(d);
            x.strb.push_back(x.lanes(n));
        end
        return x;
    endfunction

    // A random legal request (A3.4.1), random attributes; a write has random
    // data and random strobes on its active lanes.
    function automatic xact_t rand_req(bit write, int burst = -1);
        xact_t x;
        axi4_addr64_t a;
        do begin
            x = new;
            x.write = write;
            x.attr = attr_t'(rnd());
            x.attr.lock = 1'b0;
            x.attr.size = axi4_size_e'($urandom_range($clog2(BUS), 0));
            x.attr.burst = (burst >= 0) ? axi4_burst_e'(burst) : axi4_burst_e'($urandom_range(2, 0));
            x.len = (x.attr.burst == AXI4_BURST_WRAP) ? 8'((2 << $urandom_range(3, 0)) - 1)
                                                      : 8'($urandom_range(15, 0));
            a = axi4_addr64_t'(addr_t'(rnd()));
            if (x.attr.burst == AXI4_BURST_WRAP) a = axi4_aligned_addr(a, x.attr.size);
            x.addr = addr_t'(a);
        end while (!axi4_burst_legal(a, x.attr.size, x.len, x.attr.burst, BUS));
        if (write)
            for (int unsigned n = 0; n < x.n_beats(); n++) begin
                x.data.push_back(data_t'(rnd()));
                x.strb.push_back(strb_t'(rnd()) & x.lanes(n));
            end
        return x;
    endfunction

    // Issue x through `xact`; the response (and read data) land in x.
    task automatic run(xact_t x);
        if (x.write) xact.write(x.addr, x.data, x.strb, x.attr, x.resp);
        else begin
            data_t d[$];
            xact.read(x.addr, x.n_beats(), x.attr, d, x.resp);
            x.data = d;
        end
        x.done = 1;
    endtask

    // What the pins carry of x's attributes.
    function automatic attr_t on_link(xact_t x);
        return x.link_attr();
    endfunction

    // "" or what differs between the request a target saw and the one sent.
    function automatic string diff_req(xact_t seen, xact_t sent);
        if (seen.write != sent.write) return "direction";
        if (seen.addr !== sent.addr) return $sformatf("addr 0x%0h, sent 0x%0h", seen.addr, sent.addr);
        if (seen.len !== sent.len) return $sformatf("len %0d, sent %0d", seen.len, sent.len);
        if (seen.attr !== on_link(sent))
            return $sformatf("attr 0x%0h, sent 0x%0h", seen.attr, on_link(sent));
        if (sent.write) begin
            if (seen.data.size() != sent.data.size()) return "beat count";
            foreach (sent.data[i])
                if (seen.data[i] !== sent.data[i] || seen.strb[i] !== sent.strb[i])
                    return $sformatf("W beat %0d", i);
        end
        return "";
    endfunction

    // `count` random bursts through blk (axi4_burst_blocking) to a burst target that
    // logs in `log`: the target sees each request as the link carries it (absent
    // fields zeroed), and the caller gets the target's B and R beats, ID set to
    // the request's and RLAST to the beat count. err: "" or the first failure.
    string m_chk;
    function void chk_fail(string msg);
        if (m_chk == "") m_chk = msg;
    endfunction

    task automatic check_bursts(axi4_burst_blocking #(P) blk, burst_log log, int unsigned count,
                                output string err);
        int unsigned base = log.seen.size();
        m_chk = "";
        for (int unsigned i = 0; i < count; i++) begin
            xact_t x = rand_req(i % 2);
            string d;
            if (x.write) begin
                aw_t aw = at::to_aw(x.addr, x.n_beats(), x.attr);
                w_t  w[$];
                b_t  b, e;
                foreach (x.data[n]) begin
                    w_t f = w_t'(rnd());
                    f.data = x.data[n];
                    f.strb = x.strb[n];
                    f.last = (n == x.data.size() - 1);
                    w.push_back(f);
                end
                blk.write(aw, w, b);
                if (log.seen.size() != base + i + 1 || !log.seen[base + i].write) begin
                    chk_fail($sformatf("burst %0d: not seen by the target", i));
                    break;
                end
                if (!pl::aw_compare(log.seen[base + i].aw, pl::aw_mask(aw), d) || log.seen[base + i].aw !== pl::aw_mask(aw))
                    chk_fail($sformatf("burst %0d AW:%s", i, d));
                if (log.seen[base + i].w.size() != w.size()) chk_fail($sformatf("burst %0d: W beat count", i));
                else foreach (w[n])
                    if (log.seen[base + i].w[n] !== pl::w_mask(w[n]))
                        chk_fail($sformatf("burst %0d W beat %0d: %s, sent %s", i, n,
                                       pl::w_sprint(log.seen[base + i].w[n]), pl::w_sprint(w[n])));
                e = log.seen[base + i].b;
                e.id = pl::aw_mask(aw).id;
                e = pl::b_mask(e);
                if (b !== e) chk_fail($sformatf("burst %0d B: %s, target gave %s", i, pl::b_sprint(b), pl::b_sprint(e)));
            end else begin
                ar_t ar = at::to_ar(x.addr, x.n_beats(), x.attr);
                r_t  r[$];
                blk.read(ar, r);
                if (log.seen.size() != base + i + 1 || log.seen[base + i].write) begin
                    chk_fail($sformatf("burst %0d: not seen by the target", i));
                    break;
                end
                if (log.seen[base + i].ar !== pl::ar_mask(ar)) chk_fail($sformatf("burst %0d AR", i));
                if (r.size() != x.n_beats()) chk_fail($sformatf("burst %0d: %0d R beats", i, r.size()));
                else foreach (r[n]) begin
                    r_t e = log.seen[base + i].r[n];
                    e.id = pl::ar_mask(ar).id;
                    e.last = (n == r.size() - 1);
                    e = pl::r_mask(e);
                    if (r[n] !== e)
                        chk_fail($sformatf("burst %0d R beat %0d: %s, target gave %s", i, n,
                                       pl::r_sprint(r[n]), pl::r_sprint(e)));
                end
            end
        end
        err = m_chk;
    endtask

    // ---- life cycle

    function int unsigned n_errors();
        return mgr.n_errors + sub.n_errors + blk.n_errors + mgr_d.n_errors + blk_d.n_errors +
               isub.n_errors;
    endfunction

    // "" when the env is quiet and clean, else what is not.
    task automatic finish(output string err);
        u_link.settle();
        err = "";
        if (!mgr.idle() || !sub.idle()) err = "adapters not idle";
        else if (!mgr_d.idle() || !isub.idle() || blk_d.n_waiting != 0) err = "direct path not idle";
        else if (n_errors() != 0) err = $sformatf("%0d adapter errors", n_errors());
        else if (rules.n_fail() + rules_d.n_fail() != 0)
            err = $sformatf("rules failed: %s%s (first: %s%s)", rules.failed(), rules_d.failed(),
                            rules.first(), rules_d.first());
        else err = u_link.errors();
        rules.reset();
        rules_d.reset();
        mgr.n_errors = 0;
        sub.n_errors = 0;
        blk.n_errors = 0;
        mgr_d.n_errors = 0;
        blk_d.n_errors = 0;
        mgr_d.up = blk_d;
        isub.clear();
        sink.b.delete();
        sink.r.delete();
        sub.max_delay = 0;
        sub.r_interleave = 0;
        tgt.seen.delete();
        tgt.resp = AXI4_RESP_OKAY;
        tgt.err_lo = '1;
        tgt.err_hi = '0;
        tgt.err_resp = AXI4_RESP_SLVERR;
        tgt.max_delay = 0;
        btgt.log.seen.delete();
        mem.clear();
        xrec.clear();
        rq.clear();
        rs.clear();
    endtask
endmodule
