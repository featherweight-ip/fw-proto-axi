// Weave suite: the classes fw_proto derives from the AXI4 core (and from a
// synthetic API), exercised over P_MIN, P_DEF and P_WIDE (plan P1-P3 tests).
// Each check is a parameterized class whose run() returns "" or the first
// failure, so one SVTEST covers all three parameter sets.
`include "svunit_defines.svh"

package weave_ns_tb_pkg;
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import weave_synth_pkg::*;
    import weave_synth_pkg_woven::*;

    class log_c;
        string q[$];
        function string str();
            string s = "";
            foreach (q[i]) s = {s, (i != 0 ? " " : ""), q[i]};
            return s;
        endfunction
    endclass

    // ---- transaction API -------------------------------------------------
    // A listener that overrides only write_pre/write_post (the rest from _base).
    class xact_rec #(axi4_param_t P = AXI4_PARAM_DEFAULT)
            extends axi4_xact_if_listener_base #(P);
        log_c log; string tag;
        function new(log_c log, string tag); this.log = log; this.tag = tag; endfunction
        virtual function void write_pre(input addr_t addr, input data_t data[$],
                                        input strb_t strb[$], input attr_t attr);
            log.q.push_back($sformatf("%s.pre(%0d)", tag, data.size()));
        endfunction
        virtual function void write_post(input addr_t addr, input data_t data[$],
                                         input strb_t strb[$], input attr_t attr,
                                         input axi4_resp_e resp);
            log.q.push_back($sformatf("%s.post(%s)", tag, resp.name()));
        endfunction
    endclass

    // A target that implements only write; read stays the _base default.
    class xact_tgt #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_xact_if_base #(P);
        log_c log;
        function new(log_c log); this.log = log; endfunction
        virtual task write(input addr_t addr, input data_t data[$], input strb_t strb[$],
                           input attr_t attr, output axi4_resp_e resp);
            log.q.push_back("tgt");
            resp = AXI4_RESP_EXOKAY;
        endtask
    endclass

    // Not related to axi4_xact_if: has the methods, so an _imp can wrap it.
    class plain_mem #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_xact_if #(P)::addr_t addr_t;
        typedef axi4_xact_if #(P)::data_t data_t;
        typedef axi4_xact_if #(P)::strb_t strb_t;
        typedef axi4_xact_if #(P)::attr_t attr_t;
        data_t mem[addr_t];
        task write(input addr_t addr, input data_t data[$], input strb_t strb[$],
                   input attr_t attr, output axi4_resp_e resp);
            foreach (data[i]) mem[addr + addr_t'(i)] = data[i];
            resp = AXI4_RESP_OKAY;
        endtask
        task read(input addr_t addr, input int unsigned len, input attr_t attr,
                  output data_t data[$], output axi4_resp_e resp);
            data = {};
            for (int unsigned i = 0; i < len; i++) data.push_back(mem[addr + addr_t'(i)]);
            resp = AXI4_RESP_OKAY;
        endtask
    endclass

    class xact_chk #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_xact_if #(P)::addr_t addr_t;
        typedef axi4_xact_if #(P)::data_t data_t;
        typedef axi4_xact_if #(P)::strb_t strb_t;
        typedef axi4_xact_if #(P)::attr_t attr_t;

        // Proxy: pre (in listener order), forward, post; remove_listener; fan-out.
        static task proxy(output string err);
            log_c log = new;
            xact_tgt #(P) tgt = new(log);
            xact_rec #(P) a = new(log, "a"), b = new(log, "b"), c = new(log, "c");
            axi4_xact_if_proxy #(P) px = new(tgt);
            axi4_xact_if_listener_fanout #(P) fo = new;
            data_t d[$] = '{data_t'(1), data_t'(2)};
            strb_t s[$] = '{strb_t'(0), strb_t'(0)};
            axi4_resp_e r;
            err = "";
            px.add_listener(a);
            px.add_listener(b);
            px.write(addr_t'(0), d, s, attr_t'(0), r);
            if (log.str() != "a.pre(2) b.pre(2) tgt a.post(AXI4_RESP_EXOKAY) b.post(AXI4_RESP_EXOKAY)")
                begin err = {"order: ", log.str()}; return; end
            if (r != AXI4_RESP_EXOKAY) begin err = "resp not returned"; return; end
            log.q.delete();
            px.remove_listener(a);
            px.write(addr_t'(0), d, s, attr_t'(0), r);
            if (log.str() != "b.pre(2) tgt b.post(AXI4_RESP_EXOKAY)")
                begin err = {"remove: ", log.str()}; return; end
            log.q.delete();
            fo.add_listener(a);
            fo.add_listener(c);
            px.remove_listener(b);
            px.add_listener(fo);
            px.write(addr_t'(0), d, s, attr_t'(0), r);
            if (log.str() != "a.pre(2) c.pre(2) tgt a.post(AXI4_RESP_EXOKAY) c.post(AXI4_RESP_EXOKAY)")
                begin err = {"fanout: ", log.str()}; return; end
        endtask

        // Imp: forwards to an unrelated class with the same methods.
        static task imp(output string err);
            plain_mem #(P) m = new;
            axi4_xact_if_imp #(P, plain_mem #(P)) ip = new(m);
            axi4_xact_if #(P) api = ip;
            data_t d[$] = '{data_t'('h11), data_t'('h22), data_t'('h33)};
            strb_t s[$] = '{strb_t'(0), strb_t'(0), strb_t'(0)};
            data_t q[$];
            axi4_resp_e r;
            err = "";
            api.write(addr_t'('h40), d, s, attr_t'(0), r);
            api.read(addr_t'('h41), 2, attr_t'(0), q, r);
            if (q.size() != 2 || q[0] != data_t'('h22) || q[1] != data_t'('h33))
                err = "imp read-back mismatch";
        endtask
    endclass

    // ---- channel APIs (derived from the bundle) -------------------------
    class req_sink #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_req_if_base #(P);
        log_c log;
        function new(log_c log); this.log = log; endfunction
        virtual task aw(input aw_t t); log.q.push_back($sformatf("aw(%0h)", t.addr)); endtask
        virtual task w(input w_t t);   log.q.push_back($sformatf("w(%0d)", t.last)); endtask
        virtual task ar(input ar_t t); log.q.push_back($sformatf("ar(%0h)", t.addr)); endtask
    endclass

    class req_rec #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_req_if_listener_base #(P);
        log_c log;
        function new(log_c log); this.log = log; endfunction
        virtual function void aw_pre(input aw_t t);  log.q.push_back("aw_pre");  endfunction
        virtual function void aw_post(input aw_t t); log.q.push_back("aw_post"); endfunction
    endclass

    class rsp_sink #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rsp_if_base #(P);
        log_c log;
        function new(log_c log); this.log = log; endfunction
        virtual task b(input b_t t); log.q.push_back($sformatf("b(%s)", t.resp.name())); endtask
        virtual task r(input r_t t); log.q.push_back($sformatf("r(%0h)", t.data)); endtask
    endclass

    class chan_chk #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        static task run(output string err);
            log_c log = new;
            req_sink #(P) rq = new(log);
            rsp_sink #(P) rs = new(log);
            req_rec #(P) rec = new(log);
            axi4_req_if_proxy #(P) px = new(rq);
            axi4_rsp_if_proxy #(P) py = new(rs);
            axi4_req_if_proxy #(P)::aw_t awb = '0;
            axi4_req_if_proxy #(P)::w_t wb = '0;
            axi4_rsp_if_proxy #(P)::b_t bb = '0;
            axi4_rsp_if_proxy #(P)::r_t rb = '0;
            err = "";
            px.add_listener(rec);
            awb.addr = 'h100;
            wb.last = 1;
            bb.resp = AXI4_RESP_SLVERR;
            rb.data = 'h5a;
            px.aw(awb);
            px.w(wb);
            py.b(bb);
            py.r(rb);
            if (log.str() != "aw_pre aw(100) aw_post w(1) b(AXI4_RESP_SLVERR) r(5a)")
                err = log.str();
        endtask
    endclass

    // ---- payload widths, worked out by hand ------------------------------
    class width_chk #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_types #(P) t;
        static function string run(int aw, int ar, int w, int b, int r);
            if ($bits(t::aw_t) != aw) return $sformatf("aw %0d != %0d", $bits(t::aw_t), aw);
            if ($bits(t::ar_t) != ar) return $sformatf("ar %0d != %0d", $bits(t::ar_t), ar);
            if ($bits(t::w_t) != w)   return $sformatf("w %0d != %0d", $bits(t::w_t), w);
            if ($bits(t::b_t) != b)   return $sformatf("b %0d != %0d", $bits(t::b_t), b);
            if ($bits(t::r_t) != r)   return $sformatf("r %0d != %0d", $bits(t::r_t), r);
            // The derived channel API carries the same payload types.
            if ($bits(axi4_req_if #(P)::aw_t) != aw || $bits(axi4_rsp_if #(P)::r_t) != r)
                return "channel API payload width differs";
            return "";
        endfunction
    endclass

    // ---- synthetic API: type + int params, outputs, returns, fw_default --
    class syn_tgt extends syn_if_base #(byte, 6);
        int n;
        virtual task put(input byte t, output n_t cnt); n++; cnt = n_t'(n); endtask
        virtual function int sum(input n_t q[$]);
            int s = 0;
            foreach (q[i]) s += int'(q[i]);
            return s;
        endfunction
        // hint() and peek() stay the defaults: hint is fw_default="empty".
    endclass

    class syn_rec extends syn_if_listener_base #(byte, 6);
        log_c log;
        function new(log_c log); this.log = log; endfunction
        virtual function void put_post(input byte t, input n_t cnt);
            log.q.push_back($sformatf("put_post(%0d,%0d)", t, cnt));
        endfunction
        virtual function void sum_post(input n_t q[$], input int __ret);
            log.q.push_back($sformatf("sum_post(%0d)", __ret));
        endfunction
    endclass
endpackage

module weave_ns_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_test_params_pkg::*;
    import weave_ns_tb_pkg::*;
    import weave_synth_pkg_woven::*;

    string name = "weave_ns_ut";
    svunit_testcase svunit_ut;

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    `SVUNIT_TESTS_BEGIN

    `SVTEST(payload_widths)
        `FAIL_UNLESS_STR_EQUAL(width_chk #(P_MIN)::run(63, 63, 38, 4, 37), "")
        `FAIL_UNLESS_STR_EQUAL(width_chk #(P_DEF)::run(66, 66, 74, 7, 72), "")
        `FAIL_UNLESS_STR_EQUAL(width_chk #(P_WIDE)::run(105, 104, 579, 11, 528), "")
    `SVTEST_END

    `SVTEST(xact_proxy_listeners_fanout)
        string e;
        xact_chk #(P_MIN)::proxy(e);  `FAIL_UNLESS_STR_EQUAL(e, "")
        xact_chk #(P_DEF)::proxy(e);  `FAIL_UNLESS_STR_EQUAL(e, "")
        xact_chk #(P_WIDE)::proxy(e); `FAIL_UNLESS_STR_EQUAL(e, "")
    `SVTEST_END

    `SVTEST(xact_imp)
        string e;
        xact_chk #(P_MIN)::imp(e);  `FAIL_UNLESS_STR_EQUAL(e, "")
        xact_chk #(P_DEF)::imp(e);  `FAIL_UNLESS_STR_EQUAL(e, "")
        xact_chk #(P_WIDE)::imp(e); `FAIL_UNLESS_STR_EQUAL(e, "")
    `SVTEST_END

    `SVTEST(channel_apis)
        string e;
        chan_chk #(P_MIN)::run(e);  `FAIL_UNLESS_STR_EQUAL(e, "")
        chan_chk #(P_DEF)::run(e);  `FAIL_UNLESS_STR_EQUAL(e, "")
        chan_chk #(P_WIDE)::run(e); `FAIL_UNLESS_STR_EQUAL(e, "")
    `SVTEST_END

    `SVTEST(synth_api)
        log_c log = new;
        syn_tgt tgt = new;
        syn_rec rec = new(log);
        syn_if_proxy #(byte, 6) px = new(tgt);
        syn_if_proxy #(byte, 6)::n_t cnt;
        syn_if_proxy #(byte, 6)::n_t q[$] = '{6'd3, 6'd4};
        px.add_listener(rec);
        px.put(8'd7, cnt);
        `FAIL_UNLESS_EQUAL(cnt, 1)
        `FAIL_UNLESS_EQUAL(px.sum(q), 7)
        px.hint(8'd1);                       // fw_default="empty": silent
        `FAIL_UNLESS_STR_EQUAL(log.str(), "put_post(7,1) sum_post(7)")
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
