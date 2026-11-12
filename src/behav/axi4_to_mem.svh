// ------------------------------------------------------------------
// fw-hdl's protocol-independent fw_mem_if over an axi4_xact_if (`xact`,
// e.g. an axi4_xact_on_burst over a manager adapter). Each access is one
// INCR transaction: one beat of the access's own size when DATA is no wider
// than the bus, else full-width beats covering DATA. Data and strobes go on
// the lanes the address selects (A3.4.4). err = 1 on SLVERR or DECERR. An
// access should be aligned to its size.
// ------------------------------------------------------------------
class axi4_to_mem #(axi4_param_t P = AXI4_PARAM_DEFAULT, type ADDR = logic [31:0],
                    type DATA = logic [63:0], type STRB = logic [7:0])
        implements fw_mem_if #(ADDR, DATA, STRB);
    typedef axi4_types #(P)::attr_t attr_t;
    typedef axi4_types #(P)::addr_t addr_t;
    typedef axi4_types #(P)::data_t data_t;
    typedef axi4_types #(P)::strb_t strb_t;
    localparam int unsigned BUS = P.DATA_W / 8;
    localparam int unsigned BYTES = $bits(DATA) / 8;

    axi4_xact_if #(P) xact;
    attr_t            attr;      // id, cache, prot, ...; size and burst are set per access
    // Bytes per beat. A variable, not a localparam: Verilator 5.055 faults on the
    // constant form when DATA is narrower than the bus.
    local int unsigned m_bpb;

    function new(axi4_xact_if #(P) xact_ = null);
        xact = xact_;
        attr = '0;
        m_bpb = (BYTES < BUS) ? BYTES : BUS;
    endfunction

    local function attr_t mk_attr();
        attr_t a = attr;
        a.size = axi4_size_e'($clog2(m_bpb));
        a.burst = AXI4_BURST_INCR;
        a.lock = 1'b0;
        return a;
    endfunction

    local function int unsigned lane0(ADDR addr, int unsigned n);
        return axi4_beat_lower_lane(axi4_addr64_t'(addr), axi4_size_e'($clog2(m_bpb)),
                                    8'(BYTES / m_bpb - 1), AXI4_BURST_INCR, n, BUS);
    endfunction

    virtual task write(output bit err, input ADDR addr, input DATA data, input STRB strb);
        data_t      d[$];
        strb_t      s[$];
        axi4_resp_e resp;
        for (int unsigned n = 0; n < BYTES / m_bpb; n++) begin
            data_t       dn = '0;
            strb_t       sn = '0;
            int unsigned off = lane0(addr, n);
            for (int unsigned i = 0; i < m_bpb; i++) begin
                dn[8*(off + i) +: 8] = data[8*(n*m_bpb + i) +: 8];
                sn[off + i] = strb[n*m_bpb + i];
            end
            d.push_back(dn);
            s.push_back(sn);
        end
        xact.write(addr_t'(addr), d, s, mk_attr(), resp);
        err = (resp inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR});
    endtask

    virtual task read(output DATA data, output bit err, input ADDR addr);
        data_t      d[$];
        axi4_resp_e resp;
        xact.read(addr_t'(addr), BYTES / m_bpb, mk_attr(), d, resp);
        data = '0;
        for (int unsigned n = 0; n < BYTES / m_bpb && n < d.size(); n++) begin
            int unsigned off = lane0(addr, n);
            for (int unsigned i = 0; i < m_bpb; i++)
                data[8*(n*m_bpb + i) +: 8] = d[n][8*(off + i) +: 8];
        end
        err = (resp inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR});
    endtask
endclass
