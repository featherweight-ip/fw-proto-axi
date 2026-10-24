// Observation of an AXI4 link: one axi4_mon_msg per handshake (VALID and
// READY high at a rising edge) on one channel, published through
// axi4_mon_if. Publishers are pin monitors (axi4_mon_xtor_bridge, in
// fw_proto_axi4_xtor_pkg); subscribers are checkers, scoreboards and
// axi4_mon_recorder.

// One beat seen on the link. Only the member for `ch` is meaningful.
class axi4_mon_msg;
    axi4_ch_e      ch;
    time           t;      // when it was on the pins
    axi4_aw_beat_t aw;
    axi4_w_beat_t  w;
    axi4_b_beat_t  b;
    axi4_ar_beat_t ar;
    axi4_r_beat_t  r;

    function new(axi4_ch_e ch);
        this.ch = ch;
    endfunction

    function string sprint();
        case (ch)
            AXI4_CH_AW: return $sformatf("%0t AW id=%0h addr=%0h len=%0d size=%0d burst=%0d",
                                         t, aw.id, aw.addr, aw.len, aw.size, aw.burst);
            AXI4_CH_W:  return $sformatf("%0t W  data=%0h strb=%0h last=%0b", t, w.data, w.strb, w.last);
            AXI4_CH_B:  return $sformatf("%0t B  id=%0h resp=%0d", t, b.id, b.resp);
            AXI4_CH_AR: return $sformatf("%0t AR id=%0h addr=%0h len=%0d size=%0d burst=%0d",
                                         t, ar.id, ar.addr, ar.len, ar.size, ar.burst);
            default:    return $sformatf("%0t R  id=%0h data=%0h resp=%0d last=%0b",
                                         t, r.id, r.data, r.resp, r.last);
        endcase
    endfunction
endclass

// A function: observing never consumes time and never blocks the link.
interface class axi4_mon_if;
    pure virtual function void observe(axi4_mon_msg m);
endclass

// One-to-many: fw ports bind to a single provider, so a publisher that
// several subscribers want binds to a fanout. (Many publishers into one
// subscriber need nothing: many ports may bind one export.)
class axi4_mon_fanout extends fw_component implements axi4_mon_if;
    fw_export #(axi4_mon_if) in;
    local axi4_mon_if        m_subs[$];

    function new(string name, fw_component parent);
        super.new(name, parent);
        in = new("in", this, this);
    endfunction

    // Call in the connect phase with each subscriber's imp.
    function void subscribe(axi4_mon_if s);
        m_subs.push_back(s);
    endfunction

    virtual function void observe(axi4_mon_msg m);
        foreach (m_subs[i]) m_subs[i].observe(m);
    endfunction
endclass

// A subscriber that keeps everything: for tests and trace dumps
// (+axi4_mon_trace prints each message).
class axi4_mon_recorder extends fw_component implements axi4_mon_if;
    fw_export #(axi4_mon_if) in;
    axi4_mon_msg             msgs[$];
    bit                      verbose;

    function new(string name, fw_component parent);
        super.new(name, parent);
        in = new("in", this, this);
        verbose = $test$plusargs("axi4_mon_trace");
    endfunction

    virtual function void observe(axi4_mon_msg m);
        msgs.push_back(m);
        if (verbose) $display("AXI4-MON %s", m.sprint());
    endfunction

    // The messages seen on one channel, in order.
    function void select(ref axi4_mon_msg out[$], input axi4_ch_e ch);
        out.delete();
        foreach (msgs[i])
            if (msgs[i].ch == ch) out.push_back(msgs[i]);
    endfunction

    function int unsigned count(axi4_ch_e ch);
        int unsigned n = 0;
        foreach (msgs[i]) if (msgs[i].ch == ch) n++;
        return n;
    endfunction

    function void clear(); msgs.delete(); endfunction
endclass
