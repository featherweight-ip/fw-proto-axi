// L2 target: a sparse byte-addressed memory behind axi4_xact_if.
//
//   * each beat moves only its active byte lanes (A3.4.4: narrow and
//     unaligned transfers, lanes from axi4_beat_lower/upper_lane); a write
//     lane is written only where its strobe is set; inactive read lanes
//     return 0;
//   * bytes never written read as `fill`;
//   * error ranges: a beat whose address falls in one gets that range's
//     response (SLVERR/DECERR) and moves no data; B carries the worst beat;
//   * exclusive access (A7.2) with one reservation per ID: an exclusive read
//     sets it and returns EXOKAY; an exclusive write with the same address,
//     size and len as the reservation, not overwritten since, writes and
//     returns EXOKAY; otherwise it returns OKAY and writes nothing. Every
//     write that changes memory clears the reservations it overlaps. With
//     excl_support = 0, exclusive accesses get OKAY (A7.2.5) and an
//     exclusive write is an ordinary write. A burst that breaks the A7.2.4
//     rules is never exclusive: read OKAY, write fails.
class axi4_mem_model extends fw_component;
    `FW_AXI4_XACT_IMP(axi4_mem_model, xact);

    axi4_cfg      cfg;
    byte unsigned fill = 8'h00;
    bit           excl_support = 1;
    int unsigned  n_excl_ok, n_excl_fail;

    typedef struct {
        axi4_addr_t lo, hi;
        axi4_resp_e resp;
    } err_range_t;

    typedef struct {
        axi4_addr_t  addr;
        axi4_size_e  size;
        axi4_len_t   len;
    } resv_t;

    local byte unsigned m_mem[axi4_addr_t];
    local err_range_t   m_err[$];
    local resv_t        m_resv[axi4_id_t];

    function new(string name, fw_component parent, axi4_cfg cfg = null);
        super.new(name, parent);
        this.cfg = cfg;
        if (this.cfg == null) this.cfg = new();
    endfunction

    function void build();
        xact = new(this);
    endfunction

    // ---- backdoor
    function byte unsigned peek(axi4_addr_t a);
        return m_mem.exists(a) ? m_mem[a] : fill;
    endfunction

    function void poke(axi4_addr_t a, byte unsigned b);
        m_mem[a] = b;
    endfunction

    function void add_err(axi4_addr_t lo, axi4_addr_t hi,
                          axi4_resp_e resp = AXI4_RESP_SLVERR);
        err_range_t r = '{lo, hi, resp};
        m_err.push_back(r);
    endfunction

    function bit has_resv(axi4_id_t id);
        return m_resv.exists(id);
    endfunction

    function void clear();
        m_mem.delete();
        m_err.delete();
        m_resv.delete();
        fill = 8'h00;
        excl_support = 1;
        n_excl_ok = 0;
        n_excl_fail = 0;
    endfunction

    // OKAY, or the response of the error range holding `a`.
    function axi4_resp_e beat_resp(axi4_addr_t a);
        foreach (m_err[i])
            if (a >= m_err[i].lo && a <= m_err[i].hi) return m_err[i].resp;
        return AXI4_RESP_OKAY;
    endfunction

    // Bus-aligned address of beat n (lane 0) and its active lanes.
    local function void lanes(axi4_xact x, int unsigned n, output axi4_addr_t base,
                              output int unsigned lo, output int unsigned hi);
        int unsigned bb = cfg.bus_bytes();
        base = x.beat_addr(n) & ~(axi4_addr_t'(bb) - 1);
        lo   = axi4_beat_lower_lane(x.addr, x.size, x.len, x.burst, n, bb);
        hi   = axi4_beat_upper_lane(x.addr, x.size, x.len, x.burst, n, bb);
    endfunction

    // Bytes [a, a+n) overlap reservation r.
    local function bit overlaps(resv_t r, axi4_addr_t a, int unsigned n);
        axi4_addr_t rlo = r.addr;
        axi4_addr_t rhi = r.addr + (axi4_addr_t'(axi4_burst_beats(r.len)) << r.size);
        return a < rhi && a + n > rlo;
    endfunction

    local function void write_byte(axi4_addr_t a, byte unsigned b);
        axi4_id_t ids[$];
        m_mem[a] = b;
        foreach (m_resv[id]) if (overlaps(m_resv[id], a, 1)) ids.push_back(id);
        foreach (ids[i]) m_resv.delete(ids[i]);
    endfunction

    local function bit excl_ok(axi4_xact x);
        return excl_support && x.lock && axi4_excl_legal(x.addr, x.size, x.len);
    endfunction

    task xact_xact(axi4_xact x);
        if (x.write) do_write(x);
        else         do_read(x);
    endtask

    local function void do_read(axi4_xact x);
        bit excl = excl_ok(x);
        x.data.delete();
        x.rresp.delete();
        x.resp = AXI4_RESP_OKAY;
        for (int unsigned n = 0; n < x.n_beats(); n++) begin
            axi4_addr_t  base;
            int unsigned lo, hi;
            axi4_data_t  d = '0;
            axi4_resp_e  r = beat_resp(x.beat_addr(n));
            lanes(x, n, base, lo, hi);
            if (r == AXI4_RESP_OKAY) begin
                for (int unsigned l = lo; l <= hi; l++) d[8*l +: 8] = peek(base + l);
                if (excl) r = AXI4_RESP_EXOKAY;
            end
            x.data.push_back(d);
            x.rresp.push_back(r);
            x.resp = axi4_xact::worst(x.resp, r);
        end
        if (excl && x.resp == AXI4_RESP_EXOKAY) begin
            resv_t rv = '{x.addr, x.size, x.len};
            m_resv[x.id] = rv;
        end
    endfunction

    local function void do_write(axi4_xact x);
        bit excl = x.lock && excl_support;
        x.resp = AXI4_RESP_OKAY;
        if (excl) begin
            if (!excl_ok(x) || !m_resv.exists(x.id) ||
                m_resv[x.id].addr != x.addr || m_resv[x.id].size != x.size ||
                m_resv[x.id].len != x.len) begin
                n_excl_fail++;
                return;                 // OKAY, nothing written
            end
            m_resv.delete(x.id);
        end
        for (int unsigned n = 0; n < x.n_beats(); n++) begin
            axi4_addr_t  base;
            int unsigned lo, hi;
            axi4_resp_e  r = beat_resp(x.beat_addr(n));
            lanes(x, n, base, lo, hi);
            x.resp = axi4_xact::worst(x.resp, r);
            if (r != AXI4_RESP_OKAY || n >= x.data.size()) continue;
            for (int unsigned l = lo; l <= hi; l++)
                if (x.strb[n][l] === 1'b1) write_byte(base + l, x.data[n][8*l +: 8]);
        end
        if (excl) begin
            if (x.resp == AXI4_RESP_OKAY) begin
                x.resp = AXI4_RESP_EXOKAY;
                n_excl_ok++;
            end else
                n_excl_fail++;
        end
    endfunction
endclass
