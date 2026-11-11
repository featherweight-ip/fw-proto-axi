// Bundle suite: what fw_proto derives from axi4_bundle (plan P3), over P_MIN,
// P_DEF and P_WIDE: the field table against the AMBA pin lists worked out by
// hand, a cross-check against axi4_checker's port widths, the typed role
// ports, the inboxes, sprint/compare, and a manager and subordinate linked
// directly (tlm view) through the channel proxies with a listener attached.
// Each check returns "" or the first failure.
`include "svunit_defines.svh"

package bundle_ns_tb_pkg;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;

    // ---- field table -----------------------------------------------------
    class table_chk #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        // "name:width:F|R ..." in table order.
        static function string table_str(fw_sp_base sp);
            string s = "";
            foreach (sp.m_fields[i])
                s = {s, (i != 0) ? " " : "", $sformatf("%s:%0d:%s", sp.m_fields[i].name,
                     sp.m_fields[i].width, (sp.m_fields[i].dir == FW_FWD) ? "F" : "R")};
            return s;
        endfunction

        static function string run(string exp);
            axi4_mgr_sp #(P) m = new("m");
            string got = table_str(m);
            if (got != exp) return {"table\n  got ", got, "\n  exp ", exp};
            if (m.proto() != "axi4" || m.role_name() != "mgr") return "proto/role name";
            return "";
        endfunction

        // axi4_checker.sv carries every signal, an absent one as w1() bits. With
        // every field present (P_WIDE) the table's totals must equal the
        // checker's port widths, computed with the checker's own localparams.
        static function string vs_checker();
            axi4_sub_sp #(P) s = new("s");
            int unsigned IW_ = w1(P.ID_W), AW_ = P.ADDR_W, DW_ = P.DATA_W;
            int unsigned ax = IW_ + AW_ + 8 + 3 + 2 + 1 + 4 + 3 + 4 + 4;
            int unsigned fwd = (ax + w1(P.AWUSER_W)) + (ax + w1(P.ARUSER_W))
                             + (DW_ + DW_ / 8 + 1 + w1(P.WUSER_W))
                             + 3 /* aw/w/ar valid */ + 2 /* b/r ready */;
            int unsigned rev = (IW_ + 2 + w1(P.BUSER_W)) + (IW_ + DW_ + 2 + 1 + w1(P.RUSER_W))
                             + 2 /* b/r valid */ + 3 /* aw/w/ar ready */;
            if (s.bits(FW_FWD) != fwd || s.bits(FW_REV) != rev)
                return $sformatf("fwd %0d/%0d rev %0d/%0d", s.bits(FW_FWD), fwd,
                                 s.bits(FW_REV), rev);
            return "";
        endfunction
    endclass

    // ---- role ports ------------------------------------------------------
    class port_chk #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        static function string run();
            axi4_mgr_sp #(P) m = new("m"), m_in = new("m_in");
            axi4_sub_sp #(P) s = new("s");
            int v = m.field_index("awvalid"), r = m.field_index("awready");
            int bv = s.field_index("bvalid");
            m.link(s);
            if (m.m_peer != s || s.m_peer != m) return "link";
            if (m.sender() != m || s.sender() != m) return "sender";
            if (v < 0 || r < 0 || bv < 0) return "missing valid/ready";
            // The manager drives awvalid and bready; the subordinate awready and bvalid.
            if (m.field_in(v) || !m.field_in(r) || !s.field_in(v) || s.field_in(r))
                return "aw direction";
            if (!m.field_in(bv) || s.field_in(bv)) return "b direction";
            if (m.field_type(v) != "logic" || m.field_type(m.field_index("awaddr"))
                    != $sformatf("logic [%0d:0]", P.ADDR_W - 1))
                return "field_type";
            m.bind_inner(m_in);
            if (m_in.m_outer != m) return "bind_inner";
            if ((P.ID_W == 0) != (m.field_index("awid") < 0)) return "awid presence";
            return "";
        endfunction
    endclass

    // ---- payload helpers -------------------------------------------------
    class payload_chk #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_types #(P) t;
        static function string run();
            t::b_t a = '0, b;
            string diff, s;
            a.id = '1; a.resp = AXI4_RESP_SLVERR; a.user = '1;
            b = a;
            if (!axi4_payloads #(P)::b_compare(a, b, diff) || diff != "") return "equal";
            b.resp = AXI4_RESP_OKAY;
            if (axi4_payloads #(P)::b_compare(a, b, diff) || diff != " resp: 0x2 != 0x0")
                return {"resp diff: '", diff, "'"};
            // An absent field neither prints nor compares.
            b = a; b.user = ~a.user;
            if (axi4_payloads #(P)::b_compare(a, b, diff) != (P.BUSER_W == 0))
                return "user compare";
            s = axi4_payloads #(P)::b_sprint(a);
            if (P.ID_W == 0 && s != "resp=0x2") return {"sprint '", s, "'"};
            if (P.ID_W != 0 && P.BUSER_W == 0
                    && s != $sformatf("id=0x%0h resp=0x2", a.id)) return {"sprint '", s, "'"};
            if (P.BUSER_W != 0 && s != $sformatf("id=0x%0h resp=0x2 user=0x%0h", a.id, a.user))
                return {"sprint '", s, "'"};
            return "";
        endfunction
    endclass

    // ---- tlm link: manager and subordinate through the channel proxies ---
    class log_c;
        string q[$];
        function string str();
            string s = "";
            foreach (q[i]) s = {s, (i != 0 ? " " : ""), q[i]};
            return s;
        endfunction
    endclass

    class req_rec #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_req_if_listener_base #(P);
        log_c log;
        function new(log_c log); this.log = log; endfunction
        virtual function void aw_pre(input aw_t t);  log.q.push_back("aw_pre");  endfunction
        virtual function void aw_post(input aw_t t); log.q.push_back("aw_post"); endfunction
        virtual function void w_post(input w_t t);   log.q.push_back("w_post");  endfunction
    endclass

    class link_chk #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_types #(P) t;
        static task run(output string err);
            // Manager side: sends through req, receives into an rsp inbox.
            // Subordinate side: the mirror image.
            axi4_rsp_if_inbox #(P) mgr_in = new;
            axi4_req_if_inbox #(P) sub_in = new;
            axi4_req_if_proxy #(P) req = new(sub_in);
            axi4_rsp_if_proxy #(P) rsp = new(mgr_in);
            log_c log = new;
            req_rec #(P) rec = new(log);
            t::aw_t aw = '0, aw_got;
            t::w_t w = '0, w_got;
            t::b_t b = '0, b_got;
            string diff;
            bit aw_done;
            err = "";
            req.add_listener(rec);
            aw.addr = t::addr_t'('h1000); aw.len = 0; aw.size = AXI4_SIZE_4;
            aw.burst = AXI4_BURST_INCR;
            w.data = t::data_t'('h1234_5678); w.strb = '1; w.last = 1;

            // A stalled AW holds only AW: W still flows (channels are independent).
            sub_in.aw_in.stall = 1;
            fork begin req.aw(aw); aw_done = 1; end join_none
            #1;                                     // let the AW call reach the stall
            req.w(w);
            #1;
            if (aw_done || sub_in.w_in.size() != 1 || sub_in.idle())
                begin err = "AW stall"; return; end
            sub_in.aw_in.stall = 0;
            wait (aw_done);

            // The subordinate answers on B.
            sub_in.aw_in.get(aw_got);
            sub_in.w_in.get(w_got);
            if (!axi4_payloads #(P)::aw_compare(aw, aw_got, diff)) begin err = {"aw:", diff}; return; end
            if (!axi4_payloads #(P)::w_compare(w, w_got, diff))    begin err = {"w:", diff}; return; end
            b.id = aw_got.id; b.resp = AXI4_RESP_OKAY;
            rsp.b(b);
            mgr_in.b_in.get(b_got);
            if (!axi4_payloads #(P)::b_compare(b, b_got, diff)) begin err = {"b:", diff}; return; end
            if (!sub_in.idle() || !mgr_in.idle()) begin err = "not idle"; return; end
            if (sub_in.aw_in.n_recv != 1 || mgr_in.b_in.n_recv != 1) begin err = "n_recv"; return; end
            // aw_pre runs when the call is made, aw_post when the stalled beat is accepted.
            if (log.str() != "aw_pre w_post aw_post") begin err = {"log: ", log.str()}; return; end
            sub_in.clear();
            if (sub_in.aw_in.n_recv != 0) err = "clear";
        endtask
    endclass
endpackage

module bundle_ns_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_test_params_pkg::*;
    import bundle_ns_tb_pkg::*;

    string name = "bundle_ns_ut";
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

    // The AMBA pin list (A2, Tables A2.2-A2.6) for each P, by hand: absent
    // ID/USER/QOS/REGION have no field.
    `SVTEST(field_table)
        `FAIL_UNLESS_STR_EQUAL(table_chk #(P_MIN)::run({
            "awaddr:32:F awlen:8:F awsize:3:F awburst:2:F awlock:1:F awcache:4:F awprot:3:F ",
            "awvalid:1:F awready:1:R ",
            "wdata:32:F wstrb:4:F wlast:1:F wvalid:1:F wready:1:R ",
            "bresp:2:R bvalid:1:R bready:1:F ",
            "araddr:32:F arlen:8:F arsize:3:F arburst:2:F arlock:1:F arcache:4:F arprot:3:F ",
            "arvalid:1:F arready:1:R ",
            "rdata:32:R rresp:2:R rlast:1:R rvalid:1:R rready:1:F"}), "")
        `FAIL_UNLESS_STR_EQUAL(table_chk #(P_DEF)::run({
            "awid:4:F awaddr:32:F awlen:8:F awsize:3:F awburst:2:F awlock:1:F awcache:4:F ",
            "awprot:3:F awqos:4:F awregion:4:F awvalid:1:F awready:1:R ",
            "wdata:64:F wstrb:8:F wlast:1:F wvalid:1:F wready:1:R ",
            "bid:4:R bresp:2:R bvalid:1:R bready:1:F ",
            "arid:4:F araddr:32:F arlen:8:F arsize:3:F arburst:2:F arlock:1:F arcache:4:F ",
            "arprot:3:F arqos:4:F arregion:4:F arvalid:1:F arready:1:R ",
            "rid:4:R rdata:64:R rresp:2:R rlast:1:R rvalid:1:R rready:1:F"}), "")
        `FAIL_UNLESS_STR_EQUAL(table_chk #(P_WIDE)::run({
            "awid:8:F awaddr:64:F awlen:8:F awsize:3:F awburst:2:F awlock:1:F awcache:4:F ",
            "awprot:3:F awqos:4:F awregion:4:F awuser:4:F awvalid:1:F awready:1:R ",
            "wdata:512:F wstrb:64:F wlast:1:F wuser:2:F wvalid:1:F wready:1:R ",
            "bid:8:R bresp:2:R buser:1:R bvalid:1:R bready:1:F ",
            "arid:8:F araddr:64:F arlen:8:F arsize:3:F arburst:2:F arlock:1:F arcache:4:F ",
            "arprot:3:F arqos:4:F arregion:4:F aruser:3:F arvalid:1:F arready:1:R ",
            "rid:8:R rdata:512:R rresp:2:R rlast:1:R ruser:5:R rvalid:1:R rready:1:F"}), "")
    `SVTEST_END

    `SVTEST(checker_widths)
        `FAIL_UNLESS_STR_EQUAL(table_chk #(P_WIDE)::vs_checker(), "")
    `SVTEST_END

    `SVTEST(role_ports)
        `FAIL_UNLESS_STR_EQUAL(port_chk #(P_MIN)::run(), "")
        `FAIL_UNLESS_STR_EQUAL(port_chk #(P_DEF)::run(), "")
        `FAIL_UNLESS_STR_EQUAL(port_chk #(P_WIDE)::run(), "")
    `SVTEST_END

    `SVTEST(payload_sprint_compare)
        `FAIL_UNLESS_STR_EQUAL(payload_chk #(P_MIN)::run(), "")
        `FAIL_UNLESS_STR_EQUAL(payload_chk #(P_DEF)::run(), "")
        `FAIL_UNLESS_STR_EQUAL(payload_chk #(P_WIDE)::run(), "")
    `SVTEST_END

    `SVTEST(tlm_link)
        string e;
        link_chk #(P_MIN)::run(e);  `FAIL_UNLESS_STR_EQUAL(e, "")
        link_chk #(P_DEF)::run(e);  `FAIL_UNLESS_STR_EQUAL(e, "")
        link_chk #(P_WIDE)::run(e); `FAIL_UNLESS_STR_EQUAL(e, "")
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
