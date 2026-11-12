// ------------------------------------------------------------------
// A sparse byte-addressed memory behind the burst API. A request is served
// at once: its response is called back on `rsp` before the request returns.
// apply_write/apply_read are the same, as functions, for a reference model.
//   * each beat moves only its active byte lanes (A3.4.4: narrow and
//     unaligned transfers); a write lane is written only where its strobe
//     is set; inactive read lanes return 0;
//   * bytes never written read as `fill`;
//   * error ranges: a beat whose address falls in one gets that range's
//     response and moves no data; B carries the worst beat's;
//   * exclusive access (A7.2), one reservation per ID: an exclusive read
//     sets it and returns EXOKAY; an exclusive write with the reservation's
//     address, size and len, not overwritten since, writes and returns
//     EXOKAY; otherwise OKAY and nothing is written. A write that changes
//     memory clears the reservations it overlaps. With excl_support = 0,
//     exclusive accesses get OKAY (A7.2.5) and an exclusive write is an
//     ordinary one. A burst breaking A7.2.4 is never exclusive.
// USER is not stored: B and R carry 0.
// ------------------------------------------------------------------
class axi4_mem_model #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_burst_req_if_base #(P);
    typedef axi4_types #(P)::b_t b_t;
    typedef axi4_types #(P)::r_t r_t;
    axi4_burst_rsp_if #(P) rsp;
    typedef axi4_attr #(P) at;
    typedef axi4_types #(P)::data_t data_t;
    typedef axi4_types #(P)::strb_t strb_t;
    typedef logic [w1(P.ID_W)-1:0] id_t;
    localparam int unsigned BUS = P.DATA_W / 8;

    byte unsigned fill = 8'h00;
    bit           excl_support = 1;
    int unsigned  n_excl_ok, n_excl_fail;

    typedef struct {
        axi4_addr64_t lo, hi;
        axi4_resp_e   resp;
    } err_range_t;

    typedef struct {
        axi4_addr64_t addr;
        axi4_size_e   size;
        logic [7:0]   len;
    } resv_t;

    local byte unsigned m_mem[axi4_addr64_t];
    local err_range_t   m_err[$];
    local resv_t        m_resv[id_t];

    // ---- backdoor
    function byte unsigned peek(axi4_addr64_t a);
        return m_mem.exists(a) ? m_mem[a] : fill;
    endfunction

    function void poke(axi4_addr64_t a, byte unsigned v);
        m_mem[a] = v;
    endfunction

    function void add_err(axi4_addr64_t lo, axi4_addr64_t hi,
                          axi4_resp_e resp = AXI4_RESP_SLVERR);
        err_range_t r = '{lo, hi, resp};
        m_err.push_back(r);
    endfunction

    function bit has_resv(id_t id);
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

    // OKAY, or the response of the error range holding a.
    function axi4_resp_e beat_resp(axi4_addr64_t a);
        foreach (m_err[i])
            if (a >= m_err[i].lo && a <= m_err[i].hi) return m_err[i].resp;
        return AXI4_RESP_OKAY;
    endfunction

    // Bytes [a, a+n) overlap reservation r.
    local function bit overlaps(resv_t r, axi4_addr64_t a, int unsigned n);
        axi4_addr64_t rhi = r.addr + (axi4_addr64_t'(axi4_burst_beats(r.len)) << r.size);
        return a < rhi && a + axi4_addr64_t'(n) > r.addr;
    endfunction

    local function void write_byte(axi4_addr64_t a, byte unsigned v);
        id_t ids[$];
        m_mem[a] = v;
        foreach (m_resv[id]) if (overlaps(m_resv[id], a, 1)) ids.push_back(id);
        foreach (ids[i]) m_resv.delete(ids[i]);
    endfunction

    local function bit excl_ok(axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
                               logic lock);
        return excl_support && lock && axi4_excl_legal(addr, size, len);
    endfunction

    // A memory ignores cache, prot, QOS, region and USER.
    /* verilator lint_off UNUSEDSIGNAL */
    function b_t apply_write(aw_t aw, w_t w[$]);
        axi4_addr64_t a = axi4_addr64_t'(aw.addr);
        bit           excl = aw.lock && excl_support;
        b_t           b = '0;
        b.id = aw.id;
        b.resp = AXI4_RESP_OKAY;
        if (excl) begin
            if (!excl_ok(a, aw.size, aw.len, aw.lock) || !m_resv.exists(aw.id)
                    || m_resv[aw.id].addr != a || m_resv[aw.id].size != aw.size
                    || m_resv[aw.id].len != aw.len) begin
                n_excl_fail++;
                return b;               // OKAY, nothing written
            end
            m_resv.delete(aw.id);
        end
        for (int unsigned n = 0; n < axi4_burst_beats(aw.len); n++) begin
            axi4_addr64_t ba = axi4_beat_addr(a, aw.size, aw.len, aw.burst, n);
            axi4_addr64_t base = ba & ~(axi4_addr64_t'(BUS) - 1);
            strb_t        m = at::lanes(a, aw.size, aw.len, aw.burst, n);
            axi4_resp_e   r = beat_resp(ba);
            b.resp = at::worst(b.resp, r);
            if (r != AXI4_RESP_OKAY || n >= w.size()) continue;
            for (int unsigned l = 0; l < BUS; l++)
                if (m[l] && w[n].strb[l] === 1'b1)
                    write_byte(base + axi4_addr64_t'(l), w[n].data[8*l +: 8]);
        end
        if (excl) begin
            if (b.resp == AXI4_RESP_OKAY) begin
                b.resp = AXI4_RESP_EXOKAY;
                n_excl_ok++;
            end else
                n_excl_fail++;
        end
        return b;
    endfunction

    function void apply_read(ar_t ar, output r_t r[$]);
        axi4_addr64_t a = axi4_addr64_t'(ar.addr);
        bit           excl = excl_ok(a, ar.size, ar.len, ar.lock);
        axi4_resp_e   worst = AXI4_RESP_OKAY;
        r = {};
        for (int unsigned n = 0; n < axi4_burst_beats(ar.len); n++) begin
            axi4_addr64_t ba = axi4_beat_addr(a, ar.size, ar.len, ar.burst, n);
            axi4_addr64_t base = ba & ~(axi4_addr64_t'(BUS) - 1);
            strb_t        m = at::lanes(a, ar.size, ar.len, ar.burst, n);
            r_t           f = '0;
            f.id = ar.id;
            f.resp = beat_resp(ba);
            f.last = (n == axi4_burst_beats(ar.len) - 1);
            if (f.resp == AXI4_RESP_OKAY) begin
                for (int unsigned l = 0; l < BUS; l++)
                    if (m[l]) f.data[8*l +: 8] = peek(base + axi4_addr64_t'(l));
                if (excl) f.resp = AXI4_RESP_EXOKAY;
            end
            worst = at::worst(worst, f.resp);
            r.push_back(f);
        end
        if (excl && worst == AXI4_RESP_EXOKAY) begin
            resv_t rv = '{a, ar.size, ar.len};
            m_resv[ar.id] = rv;
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    virtual task write_burst(input aw_t aw, input w_t w[$]);
        rsp.write_resp(apply_write(aw, w));
    endtask

    virtual task read_burst(input ar_t ar);
        r_t r[$];
        apply_read(ar, r);
        foreach (r[i]) rsp.read_resp(r[i]);
    endtask
endclass
