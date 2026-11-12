// ------------------------------------------------------------------
// The convenience API's attributes against the address channels, and the
// burst arithmetic both sides need.
// ------------------------------------------------------------------
class axi4_attr #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    typedef axi4_types #(P)::aw_t   aw_t;
    typedef axi4_types #(P)::ar_t   ar_t;
    typedef axi4_types #(P)::attr_t attr_t;
    typedef axi4_types #(P)::addr_t addr_t;
    typedef axi4_types #(P)::strb_t strb_t;
    localparam int unsigned BUS = P.DATA_W / 8;

    static function aw_t to_aw(addr_t addr, int unsigned beats, attr_t a);
        aw_t f = '0;
        f.id = a.id; f.addr = addr; f.len = 8'(beats - 1); f.size = a.size;
        f.burst = a.burst; f.lock = a.lock; f.cache = a.cache; f.prot = a.prot;
        f.qos = a.qos; f.region = a.region; f.user = a.user[$bits(f.user)-1:0];
        return f;
    endfunction

    static function ar_t to_ar(addr_t addr, int unsigned beats, attr_t a);
        ar_t f = '0;
        f.id = a.id; f.addr = addr; f.len = 8'(beats - 1); f.size = a.size;
        f.burst = a.burst; f.lock = a.lock; f.cache = a.cache; f.prot = a.prot;
        f.qos = a.qos; f.region = a.region; f.user = a.user[$bits(f.user)-1:0];
        return f;
    endfunction

    // Only the attribute fields are taken (not addr, len).
    /* verilator lint_off UNUSEDSIGNAL */
    static function attr_t of_aw(aw_t f);
        attr_t a = '0;
        a.id = f.id; a.size = f.size; a.burst = f.burst; a.lock = f.lock;
        a.cache = f.cache; a.prot = f.prot; a.qos = f.qos; a.region = f.region;
        a.user[$bits(f.user)-1:0] = f.user;
        return a;
    endfunction

    static function attr_t of_ar(ar_t f);
        attr_t a = '0;
        a.id = f.id; a.size = f.size; a.burst = f.burst; a.lock = f.lock;
        a.cache = f.cache; a.prot = f.prot; a.qos = f.qos; a.region = f.region;
        a.user[$bits(f.user)-1:0] = f.user;
        return a;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // The active byte lanes of beat n of a burst (A3.4.3).
    static function strb_t lanes(axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
                                 axi4_burst_e burst, int unsigned n);
        int unsigned lo = axi4_beat_lower_lane(addr, size, len, burst, n, BUS);
        int unsigned hi = axi4_beat_upper_lane(addr, size, len, burst, n, BUS);
        strb_t m = '0;
        for (int unsigned l = lo; l <= hi; l++) m[l] = 1'b1;
        return m;
    endfunction

    // OKAY < EXOKAY < SLVERR < DECERR: a burst's response is its worst beat's.
    static function axi4_resp_e worst(axi4_resp_e a, axi4_resp_e b);
        return (b > a) ? b : a;
    endfunction
endclass
