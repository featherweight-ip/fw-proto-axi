// L2: one burst per call.
//
// An axi4_xact is a whole AXI4 transaction: the address-channel fields, the
// write data (one entry per beat, as it sits on the bus lanes) and, once it
// completes, the response. The caller fills the request half and calls
// axi4_xact_if::xact(); the call returns with the response half filled.
class axi4_xact;
    // ---- request (A2: AW/AR and W fields)
    bit                write;
    axi4_id_t          id;
    axi4_addr_t        addr;
    axi4_len_t         len;     // beats - 1
    axi4_size_e        size;
    axi4_burst_e       burst = AXI4_BURST_INCR;
    `AXI4_LOGIC        lock;    // 1: exclusive (A7.2)
    `AXI4_LOGIC [3:0]  cache;
    `AXI4_LOGIC [2:0]  prot;
    `AXI4_LOGIC [3:0]  qos;
    `AXI4_LOGIC [3:0]  region;
    axi4_user_t        auser;
    axi4_data_t        data[$];   // write: len+1 beats in; read: len+1 beats out
    axi4_strb_t        strb[$];   // write only
    axi4_user_t        wuser[$];  // write only

    // ---- response
    axi4_resp_e        resp;      // BRESP, or the worst RRESP of the burst
    axi4_resp_e        rresp[$];  // read: per beat
    axi4_user_t        ruser[$];  // read: per beat
    axi4_user_t        buser;     // write
    bit                done;      // set when the response is complete

    static function axi4_xact new_read(axi4_addr_t addr, axi4_size_e size,
            axi4_len_t len = 0, axi4_burst_e burst = AXI4_BURST_INCR,
            axi4_id_t id = 0);
        axi4_xact x = new;
        x.addr = addr; x.size = size; x.len = len; x.burst = burst; x.id = id;
        return x;
    endfunction

    // Data/strobes are the caller's: push len+1 beats onto data/strb.
    static function axi4_xact new_write(axi4_addr_t addr, axi4_size_e size,
            axi4_len_t len = 0, axi4_burst_e burst = AXI4_BURST_INCR,
            axi4_id_t id = 0);
        axi4_xact x = new_read(addr, size, len, burst, id);
        x.write = 1;
        return x;
    endfunction

    function int unsigned n_beats();
        return axi4_burst_beats(len);
    endfunction

    function axi4_addr_t beat_addr(int unsigned n);
        return axi4_beat_addr(addr, size, len, burst, n);
    endfunction

    // ---- conversion to and from L1 beats
    function axi4_addr_beat_t to_ax();
        axi4_addr_beat_t f = '0;
        f.id = id; f.addr = addr; f.len = len; f.size = size; f.burst = burst;
        f.lock = lock; f.cache = cache; f.prot = prot; f.qos = qos;
        f.region = region; f.user = auser;
        return f;
    endfunction

    static function axi4_xact from_ax(axi4_addr_beat_t f, bit write);
        axi4_xact x = new;
        x.write = write;
        x.id = f.id; x.addr = f.addr; x.len = f.len; x.size = f.size;
        x.burst = f.burst; x.lock = f.lock; x.cache = f.cache; x.prot = f.prot;
        x.qos = f.qos; x.region = f.region; x.auser = f.user;
        return x;
    endfunction

    function axi4_w_beat_t to_w(int unsigned n);
        axi4_w_beat_t f = '0;
        f.data = (n < data.size())  ? data[n]  : '0;
        f.strb = (n < strb.size())  ? strb[n]  : '0;
        f.user = (n < wuser.size()) ? wuser[n] : '0;
        f.last = (n == len);
        return f;
    endfunction

    function axi4_r_beat_t to_r(int unsigned n);
        axi4_r_beat_t f = '0;
        f.id   = id;
        f.data = (n < data.size())  ? data[n]  : '0;
        f.resp = (n < rresp.size()) ? rresp[n] : resp;
        f.user = (n < ruser.size()) ? ruser[n] : '0;
        f.last = (n == len);
        return f;
    endfunction

    function axi4_b_beat_t to_b();
        axi4_b_beat_t f = '0;
        f.id = id; f.resp = resp; f.user = buser;
        return f;
    endfunction

    // OKAY < EXOKAY < SLVERR < DECERR: the burst's response is the worst beat's.
    static function axi4_resp_e worst(axi4_resp_e a, axi4_resp_e b);
        return (b > a) ? b : a;
    endfunction

    function string convert2string();
        return $sformatf("%s id=0x%0h addr=0x%0h len=%0d size=%0d %s%s resp=%s",
            write ? "WR" : "RD", id, addr, len, size, burst.name(),
            lock ? " excl" : "", resp.name());
    endfunction
endclass

// The L2 API: issue one transaction, return when it has completed.
interface class axi4_xact_if;
    pure virtual task xact(axi4_xact x);
endclass

// In-order service per AXI ID: a ticket is taken in arrival order; holders
// of the same ID take turns in ticket order (A5/A6: same ID completes in
// order, different IDs are independent).
class axi4_id_turns;
    local int unsigned m_next[axi4_id_t];
    local int unsigned m_serving[axi4_id_t];
    local int unsigned m_n_release;

    function int unsigned ticket(axi4_id_t id);
        if (!m_next.exists(id)) begin
            m_next[id]    = 0;
            m_serving[id] = 0;
        end
        return m_next[id]++;
    endfunction

    task wait_turn(axi4_id_t id, int unsigned t);
        while (m_serving[id] != t) begin
            int unsigned n = m_n_release;
            wait (m_n_release != n);
        end
    endtask

    function void release_turn(axi4_id_t id);
        m_serving[id]++;
        m_n_release++;
    endfunction

    function bit idle();
        foreach (m_next[id]) if (m_next[id] != m_serving[id]) return 0;
        return 1;
    endfunction
endclass
