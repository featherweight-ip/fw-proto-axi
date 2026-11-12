// Rule teeth for one P (plan P7, rules_teeth): each
// case drives the L1 link of the image's view with traffic that is legal but for
// one planted bug, from a misbehaving model (a subordinate on axi4_req_if_base,
// tsub) or a manager calling the link directly. The rules on the link must fire
// exactly the rule the bug breaks, with a report that names the API event. With
// pins (the xtor view) the link's pin checker (axi4_checker, segment A) must
// agree: it counts failures on the side the rule binds and none on the other.
//
// Signal-level cases (rv_hold) cannot come from the transactors, which always
// hold VALID; they feed a pin monitor's events to a second rule set directly.
module axi4_rules_teeth_cell
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*,
           fw_proto_axi4_rules_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    typedef axi4_types #(P)::aw_t   aw_t;
    typedef axi4_types #(P)::w_t    w_t;
    typedef axi4_types #(P)::b_t    b_t;
    typedef axi4_types #(P)::ar_t   ar_t;
    typedef axi4_types #(P)::r_t    r_t;
    typedef axi4_types #(P)::strb_t strb_t;
    localparam int unsigned BUS = P.DATA_W / 8;
    // The capacity the rules are told (the checker's MAX_OUT on the link).
    localparam int unsigned CAP = 32;

    axi4_l1_link #(P) u_link ();

    // The subordinate: answers every write (B once its AW and last W beat are in,
    // in AW order) and every read (its beats, in AR order), EXOKAY for an
    // exclusive access, OKAY otherwise; responses go out from their own loops.
    // `bug` plants one fault.
    class tsub extends axi4_req_if_base #(P);
        axi4_rsp_if #(P) rsp;
        string           bug;
        aw_t             aws[$];
        bit              b_sent[$];     // B already sent (b_early)
        int unsigned     n_wlast;       // write-data bursts not yet matched to an AW
        bit              hold_r;        // keep reads until answer_held()
        ar_t             held[$];
        b_t              bq[$];
        r_t              rq[$];

        function void clear();
            bug = "";
            aws.delete();
            b_sent.delete();
            n_wlast = 0;
            hold_r = 0;
            held.delete();
        endfunction

        function bit idle();
            return bq.size() == 0 && rq.size() == 0;
        endfunction

        function void send_b(aw_t a);
            b_t b = '0;
            b.id = a.id;
            b.resp = (a.lock || bug == "exokay") ? AXI4_RESP_EXOKAY : AXI4_RESP_OKAY;
            bq.push_back(b);
        endfunction

        function void match();
            while (aws.size() != 0 && n_wlast != 0) begin
                aw_t a = aws.pop_front();
                bit  sent = b_sent.pop_front();
                n_wlast--;
                if (!sent) send_b(a);
                if (bug == "b_twice") send_b(a);
            end
        endfunction

        function void answer(ar_t a);
            int unsigned beats = int'(a.len) + 1;
            if (bug == "rlast_early" && beats > 2) beats = 2;
            for (int unsigned n = 0; n < beats; n++) begin
                r_t r = '0;
                r.id = a.id;
                r.data = {(P.DATA_W + 31) / 32{$urandom}};
                r.resp = a.lock ? AXI4_RESP_EXOKAY : AXI4_RESP_OKAY;
                r.last = (n == beats - 1);
                rq.push_back(r);
            end
        endfunction

        // Answer the held reads: in AR order, or reversed (r_order).
        function void answer_held();
            if (bug == "r_order") foreach (held[i]) answer(held[held.size() - 1 - i]);
            else foreach (held[i]) answer(held[i]);
            held.delete();
            hold_r = 0;
        endfunction

        virtual task aw(input aw_t t);
            aws.push_back(t);
            b_sent.push_back(bug == "b_early");
            if (bug == "b_early") send_b(t);
            if (bug == "r_spurious") begin
                r_t r = '0;
                r.id = t.id;
                r.last = 1;
                rq.push_back(r);
            end
            match();
        endtask

        virtual task w(input w_t t);
            if (t.last) begin
                n_wlast++;
                match();
            end
        endtask

        virtual task ar(input ar_t t);
            if (hold_r) held.push_back(t);
            else answer(t);
        endtask

        task run();
            fork
                forever begin
                    wait (bq.size() != 0);
                    rsp.b(bq[0]);
                    void'(bq.pop_front());
                end
                forever begin
                    wait (rq.size() != 0);
                    rsp.r(rq[0]);
                    void'(rq.pop_front());
                end
            join_none
        endtask
    endclass

    tsub            sub = new;
    axi4_rules #(P) rules;      // on the link
    axi4_rules #(P) ev;         // fed directly, as from a pin monitor
    bit             ready;

    initial begin
        wait (u_link.up);
        sub.rsp = u_link.rsp;
        u_link.attach(u_link.mgr_in, sub);
        rules = new("link", u_link.at_pins(), CAP, CAP);
        rules.set_quiet(1);
        u_link.add_req_listener(rules.req);
        u_link.add_rsp_listener(rules.rsp);
        ev = new("events", 1);
        ev.set_quiet(1);
        sub.run();
        ready = 1;
    end

    // ---- the manager's side

    function automatic aw_t mk_aw(int unsigned id, axi4_addr64_t addr, int unsigned len,
                                  axi4_size_e size = axi4_size_e'($clog2(BUS)),
                                  axi4_burst_e burst = AXI4_BURST_INCR, bit lock = 0);
        aw_t a = '0;
        a.id = id[$bits(a.id)-1:0];
        a.addr = addr[P.ADDR_W-1:0];
        a.len = 8'(len);
        a.size = size;
        a.burst = burst;
        a.lock = lock;
        return a;
    endfunction

    function automatic ar_t mk_ar(int unsigned id, axi4_addr64_t addr, int unsigned len,
                                  axi4_size_e size = axi4_size_e'($clog2(BUS)),
                                  axi4_burst_e burst = AXI4_BURST_INCR, bit lock = 0);
        ar_t a = '0;
        a.id = id[$bits(a.id)-1:0];
        a.addr = addr[P.ADDR_W-1:0];
        a.len = 8'(len);
        a.size = size;
        a.burst = burst;
        a.lock = lock;
        return a;
    endfunction

    // The lanes beat n of a's burst may strobe.
    function automatic strb_t lanes(aw_t a, int unsigned n);
        strb_t m = '0;
        int unsigned lo = axi4_beat_lower_lane(axi4_addr64_t'(a.addr), a.size, a.len, a.burst, n, BUS);
        int unsigned hi = axi4_beat_upper_lane(axi4_addr64_t'(a.addr), a.size, a.len, a.burst, n, BUS);
        for (int unsigned l = 0; l < BUS; l++) if (l >= lo && l <= hi) m[l] = 1'b1;
        return m;
    endfunction

    // A write: AW, then after w_delay its W beats; or (w_first) the W beats, then
    // after w_delay the AW. `beats` W beats (default AWLEN+1), WLAST on the last of
    // them; strb_xor flips strobes of beat 0.
    task automatic write(aw_t a, int beats = -1, bit w_first = 0, time w_delay = 0,
                         strb_t strb_xor = '0);
        int unsigned nb = (beats < 0) ? int'(a.len) + 1 : beats;
        if (!w_first) begin
            u_link.req.aw(a);
            #(w_delay);
        end
        for (int unsigned n = 0; n < nb; n++) begin
            w_t w = '0;
            w.data = {(P.DATA_W + 31) / 32{$urandom}};
            w.strb = lanes(a, n) ^ ((n == 0) ? strb_xor : '0);
            w.last = (n == nb - 1);
            u_link.req.w(w);
        end
        if (w_first) begin
            #(w_delay);
            u_link.req.aw(a);
        end
    endtask

    // Until the manager has nb B beats and nr R beats, then the link quiet.
    task automatic wait_rsp(int unsigned nb, int unsigned nr, output string err);
        fork : wt
            wait (u_link.mgr_in.b_in.n_recv >= nb && u_link.mgr_in.r_in.n_recv >= nr && sub.idle());
            #200_000;
        join_any
        disable wt;
        err = (u_link.mgr_in.b_in.n_recv >= nb && u_link.mgr_in.r_in.n_recv >= nr && sub.idle()) ? ""
            : $sformatf("responses: %0d B of %0d, %0d R of %0d", u_link.mgr_in.b_in.n_recv, nb,
                        u_link.mgr_in.r_in.n_recv, nr);
        u_link.settle();
        #100;
    endtask

    // ---- the cases. Each returns the responses to wait for.

    task automatic legal(output int unsigned nb, output int unsigned nr);
        write(mk_aw(1, 'h1000, 3));
        write(mk_aw(2, 'h2000, 0));
        write(mk_aw(3, 'h3000, 1), -1, 1);                                     // W ahead of AW
        write(mk_aw(1, 'h1100, 2, AXI4_SIZE_1, AXI4_BURST_INCR));              // narrow
        write(mk_aw(4, 'h4008, 1, AXI4_SIZE_4, AXI4_BURST_INCR, 1));           // exclusive
        write(mk_aw(5, 'h5000, 2, axi4_size_e'($clog2(BUS)), AXI4_BURST_FIXED));
        u_link.req.ar(mk_ar(1, 'h1000, 2));
        u_link.req.ar(mk_ar(2, 'h2000, 5));
        u_link.req.ar(mk_ar(1, 'h1200, 0));
        u_link.req.ar(mk_ar(6, 'h6000, 3, axi4_size_e'($clog2(BUS)), AXI4_BURST_WRAP));
        u_link.req.ar(mk_ar(7, 'h7008, 1, AXI4_SIZE_4, AXI4_BURST_INCR, 1)); // exclusive
        nb = 6;
        nr = 3 + 6 + 1 + 4 + 2;
    endtask

    task automatic run_case(string name, output int unsigned nb, output int unsigned nr);
        nb = 0;
        nr = 0;
        case (name)
        "legal": legal(nb, nr);
        // Subordinate faults
        "b_twice": begin       // two Bs for one write
            sub.bug = "b_twice";
            write(mk_aw(3, 'h100, 1));
            nb = 2;
        end
        "r_spurious": begin    // an R beat with no read outstanding
            sub.bug = "r_spurious";
            write(mk_aw(5, 'h100, 0));
            nb = 1;
            nr = 1;
        end
        "rlast_early": begin   // RLAST on beat 2 of 4
            sub.bug = "rlast_early";
            u_link.req.ar(mk_ar(2, 'h200, 3));
            nr = 2;
        end
        "r_order": begin       // two reads of one ID answered in the other order
            sub.bug = "r_order";
            sub.hold_r = 1;
            u_link.req.ar(mk_ar(4, 'h200, 0));
            u_link.req.ar(mk_ar(4, 'h300, 3));
            wait (sub.held.size() == 2);
            sub.answer_held();
            nr = 5;
        end
        "b_early": begin       // B after the AW, before the write's data
            sub.bug = "b_early";
            write(mk_aw(6, 'h100, 1), -1, 0, 500);
            nb = 1;
        end
        "exokay": begin        // EXOKAY for a write that is not exclusive
            sub.bug = "exokay";
            write(mk_aw(1, 'h100, 0));
            nb = 1;
        end
        // Manager faults
        "wlast_early": begin   // WLAST on beat 2 of 4
            write(mk_aw(1, 'h100, 3), 2);
            nb = 1;
        end
        "w_ahead_long": begin  // 3 beats sent ahead of an AW of 2 (all on the pins first)
            write(mk_aw(1, 'h100, 1), 3, 1, 500);
            nb = 1;
        end
        "burst_4k": begin      // INCR across a 4KB boundary
            u_link.req.ar(mk_ar(2, 'h1000 - BUS, 1));
            nr = 2;
        end
        "wrap_len": begin      // WRAP of 3 beats
            u_link.req.ar(mk_ar(2, 'h100, 2, axi4_size_e'($clog2(BUS)), AXI4_BURST_WRAP));
            nr = 3;
        end
        "excl_illegal": begin  // exclusive access of 32 beats
            u_link.req.ar(mk_ar(2, 'h0, 31, AXI4_SIZE_1, AXI4_BURST_INCR, 1));
            nr = 32;
        end
        "wstrb_lane": begin    // a strobe outside beat 0's lanes
            aw_t a = mk_aw(1, 'h100, 1, AXI4_SIZE_1);
            write(a, -1, 0, 0, ~lanes(a, 0) & strb_t'(1 << (BUS - 1)));
            nb = 1;
        end
        "capacity": begin      // CAP + 1 reads outstanding
            sub.hold_r = 1;
            for (int unsigned i = 0; i <= CAP; i++) u_link.req.ar(mk_ar(i % 2, 'h100 * i, 0));
            wait (sub.held.size() == CAP + 1);
            sub.answer_held();
            nr = CAP + 1;
        end
        default: $fatal(1, "axi4_rules_teeth_cell: no case %s", name);
        endcase
    endtask

    function automatic bit has(string s, string sub_s);
        if (sub_s.len() == 0) return 1;
        for (int i = 0; i + sub_s.len() <= s.len(); i++)
            if (s.substr(i, i + sub_s.len() - 1) == sub_s) return 1;
        return 0;
    endfunction

    // The verdict on rule set rs: `rule` failed (or none did, rule == ""), with a
    // first report containing `msg`; no other rule failed.
    function automatic string verdict(axi4_rules #(P) rs, string rule, string msg);
        foreach (rs.sets[i]) begin
            string nm = rs.sets[i].m_proto.m_name;
            int unsigned n = rs.sets[i].n_fail;
            if (nm == rule && n == 0) return $sformatf("%s did not fire", rule);
            if (nm != rule && n != 0)
                return $sformatf("%s fired (%0d): %s", nm, n, rs.sets[i].m_fails[0]);
        end
        if (rule != "" && !has(rs.first(), msg))
            return $sformatf("report '%s' does not name '%s'", rs.first(), msg);
        if (rule != "") $display("[rules_teeth] %s", rs.first());
        return "";
    endfunction

    // One case over the link: `rule` must fire alone, its report naming `msg`; with
    // pins the checker must count on `side` ("m" or "s", "" for none) and, unless
    // `either`, not on the other.
    task automatic t_case(string name, string rule, string msg, string side, bit either,
                          output string err);
        int unsigned nb, nr, m0, s0, m1, s1;
        wait (ready);
        rules.reset();
        sub.clear();
        u_link.mgr_in.clear();
        u_link.chk_counts(m0, s0);
        run_case(name, nb, nr);
        wait_rsp(nb, nr, err);
        if (err != "") return;
        err = verdict(rules, rule, msg);
        if (err != "" || !u_link.has_checker()) return;
        u_link.chk_counts(m1, s1);
        m1 -= m0;
        s1 -= s0;
        if (side == "m" && m1 == 0) err = "checker: no manager-side failure";
        else if (side == "s" && s1 == 0) err = "checker: no subordinate-side failure";
        else if (side != "m" && m1 != 0 && !either) err = $sformatf("checker: %0d manager-side failures", m1);
        else if (side != "s" && s1 != 0 && !either) err = $sformatf("checker: %0d subordinate-side failures", s1);
        void'(u_link.errors());    // consume the link's own count
    endtask

    // Signal level, from a pin monitor's events (fed directly).
    task automatic t_rv(string name, output string err);
        aw_t a = mk_aw(1, 'h100, 0);
        w_t  w0 = '0, w1 = '0;
        ev.reset();
        w0.last = 1;
        w1.last = 1;
        w1.data = 1;
        if (name == "rv_legal") begin
            ev.req.aw_pre(a);
            ev.req.aw_post(a);
            ev.req.w_pre(w0);
            ev.req.w_post(w0);
            err = verdict(ev, "", "");
        end else if (name == "rv_drop") begin         // a second first-VALID before the handshake
            ev.req.aw_pre(a);
            ev.req.aw_pre(a);
            ev.req.aw_post(a);
            err = verdict(ev, "rv_hold", "aw: VALID dropped");
        end else begin                                  // payload changed while stalled
            ev.req.w_pre(w0);
            ev.req.w_post(w1);
            err = verdict(ev, "rv_hold", "w: payload changed");
        end
    endtask
endmodule
