// Static properties of one AXI4 interface: the widths that set the wire
// layout (axi4_param_t). Both ends of a link must agree.
//
// The class layer carries max-width beats (axi4_types_pkg); an interface
// narrower than the maximum delivers each beat MASKED to its configuration.
// The mask_* functions are that projection, and they define the L1 contract
// precisely: what arrives is mask(what was sent). A direct TLM bind does not
// mask, so a test that wants one expectation for every view sends
// pre-masked beats.
class axi4_cfg;
    int unsigned addr_w   = 32;
    int unsigned data_w   = 64;    // 8..1024, power of 2
    int unsigned id_w     = 4;     // 0: no ID signals
    int unsigned awuser_w = 0;
    int unsigned wuser_w  = 0;
    int unsigned buser_w  = 0;
    int unsigned aruser_w = 0;
    int unsigned ruser_w  = 0;

    function new(int unsigned addr_w = 32, int unsigned data_w = 64,
                 int unsigned id_w = 4);
        this.addr_w = addr_w;
        this.data_w = data_w;
        this.id_w   = id_w;
    endfunction

    // The same properties as the parameter struct the cores use.
    static function axi4_cfg from_param(axi4_param_t p);
        axi4_cfg c = new(p.ADDR_W, p.DATA_W, p.ID_W);
        c.awuser_w = p.AWUSER_W;
        c.wuser_w  = p.WUSER_W;
        c.buser_w  = p.BUSER_W;
        c.aruser_w = p.ARUSER_W;
        c.ruser_w  = p.RUSER_W;
        return c;
    endfunction

    function axi4_param_t to_param();
        axi4_param_t p;
        p.ADDR_W   = addr_w;
        p.DATA_W   = data_w;
        p.ID_W     = id_w;
        p.AWUSER_W = awuser_w;
        p.WUSER_W  = wuser_w;
        p.BUSER_W  = buser_w;
        p.ARUSER_W = aruser_w;
        p.RUSER_W  = ruser_w;
        return p;
    endfunction

    // Bytes per beat at full width.
    function int unsigned bus_bytes();
        return data_w / 8;
    endfunction

    // Empty when compatible; else names the first mismatching property.
    function string compatible(axi4_cfg o);
        if (o == null)            return "peer has no axi4_cfg";
        if (addr_w   != o.addr_w)   return "ADDR_W";
        if (data_w   != o.data_w)   return "DATA_W";
        if (id_w     != o.id_w)     return "ID_W";
        if (awuser_w != o.awuser_w) return "AWUSER_W";
        if (wuser_w  != o.wuser_w)  return "WUSER_W";
        if (buser_w  != o.buser_w)  return "BUSER_W";
        if (aruser_w != o.aruser_w) return "ARUSER_W";
        if (ruser_w  != o.ruser_w)  return "RUSER_W";
        return "";
    endfunction

    // Low-w-bit mask, w = 0..1024.
    static function logic [AXI4_DATA_W_MAX-1:0] lo(int unsigned w);
        return (w == 0) ? '0 : ({AXI4_DATA_W_MAX{1'b1}} >> (AXI4_DATA_W_MAX - w));
    endfunction

    // AW and AR share the address struct; only USER width differs.
    function axi4_addr_beat_t mask_ax(axi4_addr_beat_t f, bit rd);
        f.id   &= AXI4_ID_W_MAX'(lo(id_w));
        f.addr &= AXI4_ADDR_W_MAX'(lo(addr_w));
        f.user &= AXI4_USER_W_MAX'(lo(rd ? aruser_w : awuser_w));
        return f;
    endfunction

    function axi4_aw_beat_t mask_aw(axi4_aw_beat_t f);
        return mask_ax(f, 0);
    endfunction

    function axi4_ar_beat_t mask_ar(axi4_ar_beat_t f);
        return mask_ax(f, 1);
    endfunction

    function axi4_w_beat_t mask_w(axi4_w_beat_t f);
        f.data &= lo(data_w);
        f.strb &= AXI4_STRB_W_MAX'(lo(data_w / 8));
        f.user &= AXI4_USER_W_MAX'(lo(wuser_w));
        return f;
    endfunction

    function axi4_b_beat_t mask_b(axi4_b_beat_t f);
        f.id   &= AXI4_ID_W_MAX'(lo(id_w));
        f.user &= AXI4_USER_W_MAX'(lo(buser_w));
        return f;
    endfunction

    function axi4_r_beat_t mask_r(axi4_r_beat_t f);
        f.id   &= AXI4_ID_W_MAX'(lo(id_w));
        f.data &= lo(data_w);
        f.user &= AXI4_USER_W_MAX'(lo(ruser_w));
        return f;
    endfunction
endclass
