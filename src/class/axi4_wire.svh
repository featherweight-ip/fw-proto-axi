// Class-level beat <-> packed stream beat for one interface configuration:
// the layout of the cores' user streams (axi4_types_pkg), the channel's pins
// in order, MSB first, so packed here LSB first from the last field:
//   AW/AR {id, addr, len, size, burst, lock, cache, prot, qos, region, user}
//   W     {data, strb, last, user}
//   B     {id, resp, user}
//   R     {id, data, resp, last, user}
// An absent ID/USER (width 0) is one bit on the stream, carried as 0.
//
// For every beat b:  unpack(pack(b)) == cfg.mask(b).
class axi4_wire;
    typedef logic [AXI4_STREAM_W_MAX-1:0] stream_t;
    typedef logic [AXI4_DATA_W_MAX-1:0]   field_t;

    // Append `w` bits of v at `pos`.
    static function void put(ref stream_t s, ref int pos, input field_t v, input int w);
        for (int i = 0; i < w; i++) s[pos + i] = v[i];
        pos += w;
    endfunction

    // Take `w` bits at `pos`.
    static function field_t get(input stream_t s, ref int pos, input int w);
        field_t v = '0;
        for (int i = 0; i < w; i++) v[i] = s[pos + i];
        pos += w;
        return v;
    endfunction

    // An optional field: w bits, or one 0 bit when absent.
    static function void put_opt(ref stream_t s, ref int pos, input field_t v, input int w);
        put(s, pos, (w > 0) ? v : '0, (w > 0) ? w : 1);
    endfunction

    static function field_t get_opt(input stream_t s, ref int pos, input int w);
        field_t v = get(s, pos, (w > 0) ? w : 1);
        return (w > 0) ? v : '0;
    endfunction

    static function void check_w(string ch, int pos, int want);
        if (pos != want)
            $fatal(1, "axi4_wire: %s packed to %0d bits, configuration says %0d", ch, pos, want);
    endfunction

    // ---- AW / AR
    static function stream_t pack_ax(axi4_cfg c, axi4_addr_beat_t a, bit rd);
        stream_t s = '0; int p = 0;
        put_opt(s, p, a.user, rd ? c.aruser_w : c.awuser_w);
        put(s, p, a.region, 4);   put(s, p, a.qos, 4);     put(s, p, a.prot, 3);
        put(s, p, a.cache, 4);    put(s, p, a.lock, 1);    put(s, p, a.burst, 2);
        put(s, p, a.size, AXI4_SIZE_W);  put(s, p, a.len, AXI4_LEN_W);
        put(s, p, a.addr, c.addr_w);
        put_opt(s, p, a.id, c.id_w);
        check_w(rd ? "AR" : "AW", p, axi4_ax_bits(c.to_param(), rd));
        return s;
    endfunction

    static function axi4_addr_beat_t unpack_ax(axi4_cfg c, stream_t s, bit rd);
        axi4_addr_beat_t a = '0; int p = 0;
        a.user   = get_opt(s, p, rd ? c.aruser_w : c.awuser_w);
        a.region = get(s, p, 4);  a.qos = get(s, p, 4);     a.prot = get(s, p, 3);
        a.cache  = get(s, p, 4);  a.lock = get(s, p, 1);
        a.burst  = axi4_burst_e'(get(s, p, 2));
        a.size   = axi4_size_e'(get(s, p, AXI4_SIZE_W));
        a.len    = get(s, p, AXI4_LEN_W);
        a.addr   = get(s, p, c.addr_w);
        a.id     = get_opt(s, p, c.id_w);
        return a;
    endfunction

    static function stream_t pack_aw(axi4_cfg c, axi4_aw_beat_t a);
        return pack_ax(c, a, 1'b0);
    endfunction

    static function axi4_aw_beat_t unpack_aw(axi4_cfg c, stream_t s);
        return unpack_ax(c, s, 1'b0);
    endfunction

    static function stream_t pack_ar(axi4_cfg c, axi4_ar_beat_t a);
        return pack_ax(c, a, 1'b1);
    endfunction

    static function axi4_ar_beat_t unpack_ar(axi4_cfg c, stream_t s);
        return unpack_ax(c, s, 1'b1);
    endfunction

    // ---- W
    static function stream_t pack_w(axi4_cfg c, axi4_w_beat_t w);
        stream_t s = '0; int p = 0;
        put_opt(s, p, w.user, c.wuser_w);
        put(s, p, w.last, 1);
        put(s, p, w.strb, c.data_w / 8);
        put(s, p, w.data, c.data_w);
        check_w("W", p, axi4_wd_bits(c.to_param()));
        return s;
    endfunction

    static function axi4_w_beat_t unpack_w(axi4_cfg c, stream_t s);
        axi4_w_beat_t w = '0; int p = 0;
        w.user = get_opt(s, p, c.wuser_w);
        w.last = get(s, p, 1);
        w.strb = get(s, p, c.data_w / 8);
        w.data = get(s, p, c.data_w);
        return w;
    endfunction

    // ---- B
    static function stream_t pack_b(axi4_cfg c, axi4_b_beat_t b);
        stream_t s = '0; int p = 0;
        put_opt(s, p, b.user, c.buser_w);
        put(s, p, b.resp, 2);
        put_opt(s, p, b.id, c.id_w);
        check_w("B", p, axi4_b_bits(c.to_param()));
        return s;
    endfunction

    static function axi4_b_beat_t unpack_b(axi4_cfg c, stream_t s);
        axi4_b_beat_t b = '0; int p = 0;
        b.user = get_opt(s, p, c.buser_w);
        b.resp = axi4_resp_e'(get(s, p, 2));
        b.id   = get_opt(s, p, c.id_w);
        return b;
    endfunction

    // ---- R
    static function stream_t pack_r(axi4_cfg c, axi4_r_beat_t r);
        stream_t s = '0; int p = 0;
        put_opt(s, p, r.user, c.ruser_w);
        put(s, p, r.last, 1);
        put(s, p, r.resp, 2);
        put(s, p, r.data, c.data_w);
        put_opt(s, p, r.id, c.id_w);
        check_w("R", p, axi4_r_bits(c.to_param()));
        return s;
    endfunction

    static function axi4_r_beat_t unpack_r(axi4_cfg c, stream_t s);
        axi4_r_beat_t r = '0; int p = 0;
        r.user = get_opt(s, p, c.ruser_w);
        r.last = get(s, p, 1);
        r.resp = axi4_resp_e'(get(s, p, 2));
        r.data = get(s, p, c.data_w);
        r.id   = get_opt(s, p, c.id_w);
        return r;
    endfunction
endclass
