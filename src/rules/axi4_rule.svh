// Base of the AXI4 rules: a listener of both channel APIs (axi4_req_if: AW, W,
// AR; axi4_rsp_if: B, R) on fw_rule. Rules override the accepted events:
//   on_aw, on_w, on_ar   a request: at its pre (the call is made) from a proxy, at
//                        its post (the handshake) from a pin monitor (m_pins)
//   on_b, on_r           a response: at its post
// A response may come inside its request's call (design §3.4), so from a proxy a
// request counts when the call is made. On pins nothing can answer a beat before
// its handshake, so there it counts at the handshake. A signal-level rule
// overrides the pre/post methods themselves (axi4_rule_rv_hold).
virtual class axi4_rule #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_rule
        implements axi4_req_if_listener #(P), axi4_rsp_if_listener #(P);
    typedef axi4_types #(P)::aw_t   aw_t;
    typedef axi4_types #(P)::w_t    w_t;
    typedef axi4_types #(P)::b_t    b_t;
    typedef axi4_types #(P)::ar_t   ar_t;
    typedef axi4_types #(P)::r_t    r_t;
    typedef axi4_types #(P)::strb_t strb_t;
    // Not w1(): Verilator 5.055 fails to link a function call in a typedef that
    // is then a class's type parameter (fw_any #(id_t)).
    localparam int unsigned ID_BITS = (P.ID_W > 0) ? P.ID_W : 1;
    typedef logic [ID_BITS-1:0]     id_t;
    localparam int unsigned BUS = P.DATA_W / 8;

    function new(string name);
        super.new(name);
    endfunction

    virtual function fw_rule_node new_node();
        axi4_rule_node #(P) n = new;
        return n;
    endfunction

    /* verilator lint_off UNUSEDSIGNAL */
    virtual function void on_aw(aw_t t); endfunction
    virtual function void on_w(w_t t);   endfunction
    virtual function void on_ar(ar_t t); endfunction
    virtual function void on_b(b_t t);   endfunction
    virtual function void on_r(r_t t);   endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    virtual function void aw_pre(input aw_t t);  if (!m_retired && !m_pins) on_aw(t); endfunction
    virtual function void aw_post(input aw_t t); if (!m_retired && m_pins)  on_aw(t); endfunction
    virtual function void w_pre(input w_t t);    if (!m_retired && !m_pins) on_w(t);  endfunction
    virtual function void w_post(input w_t t);   if (!m_retired && m_pins)  on_w(t);  endfunction
    virtual function void ar_pre(input ar_t t);  if (!m_retired && !m_pins) on_ar(t); endfunction
    virtual function void ar_post(input ar_t t); if (!m_retired && m_pins)  on_ar(t); endfunction
    /* verilator lint_off UNUSEDSIGNAL */
    virtual function void b_pre(input b_t t);    endfunction
    virtual function void r_pre(input r_t t);    endfunction
    /* verilator lint_on UNUSEDSIGNAL */
    virtual function void b_post(input b_t t);   if (!m_retired) on_b(t); endfunction
    virtual function void r_post(input r_t t);   if (!m_retired) on_r(t); endfunction

    // The byte lanes beat n of a burst may strobe (A3.4.3).
    function strb_t lanes(axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
                                 axi4_burst_e burst, int unsigned n);
        strb_t m = '0;
        int unsigned lo = axi4_beat_lower_lane(addr, size, len, burst, n, BUS);
        int unsigned hi = axi4_beat_upper_lane(addr, size, len, burst, n, BUS);
        for (int unsigned l = 0; l < BUS; l++) if (l >= lo && l <= hi) m[l] = 1'b1;
        return m;
    endfunction

    // Why a burst is illegal (A3.4.1), "" if it is legal.
    function string burst_why(axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
                                     axi4_burst_e burst);
        int unsigned beats = axi4_burst_beats(len);
        if (burst == AXI4_BURST_RSVD) return "reserved burst type";
        if (axi4_size_bytes(size) > BUS) return "transfer wider than the bus";
        if (burst != AXI4_BURST_INCR && beats > 16) return "FIXED or WRAP longer than 16 beats";
        if (burst == AXI4_BURST_WRAP && !(beats inside {2, 4, 8, 16}))
            return "WRAP length not 2, 4, 8 or 16";
        if (burst == AXI4_BURST_WRAP && axi4_aligned_addr(addr, size) != addr)
            return "WRAP address not aligned";
        if (axi4_crosses_4k(addr, size, len, burst)) return "crosses a 4KB boundary";
        return "";
    endfunction
endclass
