// ------------------------------------------------------------------
// The convenience API over the burst API: axi4_xact_if calls in, blocking
// bursts out on `blk`.
// ------------------------------------------------------------------
class axi4_xact_on_burst #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_xact_if_base #(P);
    typedef axi4_attr #(P) at;
    typedef axi4_types #(P)::aw_t aw_t;
    typedef axi4_types #(P)::w_t  w_t;
    typedef axi4_types #(P)::b_t  b_t;
    typedef axi4_types #(P)::r_t  r_t;

    axi4_burst_blocking #(P) blk;

    function new(axi4_burst_blocking #(P) blk_ = null);
        blk = blk_;
    endfunction

    // Of B only the response is reported.
    /* verilator lint_off UNUSEDSIGNAL */
    virtual task write(input addr_t addr, input data_t data[$], input strb_t strb[$],
                       input attr_t attr, output axi4_resp_e resp);
        aw_t aw;
        w_t  w[$];
        b_t  b;
        if (data.size() == 0 || data.size() > 256) begin
            $error("axi4_xact_on_burst: write with %0d data beats", data.size());
            resp = AXI4_RESP_SLVERR;
            return;
        end
        aw = at::to_aw(addr, data.size(), attr);
        foreach (data[n]) begin
            w_t f = '0;
            f.data = data[n];
            f.strb = (n < strb.size()) ? strb[n]
                   : at::lanes(axi4_addr64_t'(addr), aw.size, aw.len, aw.burst, n);
            f.last = (n == data.size() - 1);
            w.push_back(f);
        end
        blk.write(aw, w, b);
        resp = b.resp;
    endtask
    /* verilator lint_on UNUSEDSIGNAL */

    virtual task read(input addr_t addr, input int unsigned beats, input attr_t attr,
                      output data_t data[$], output axi4_resp_e resp);
        r_t r[$];
        data = {};
        resp = AXI4_RESP_OKAY;
        if (beats == 0 || beats > 256) begin
            $error("axi4_xact_on_burst: read of %0d beats", beats);
            resp = AXI4_RESP_SLVERR;
            return;
        end
        blk.read(at::to_ar(addr, beats, attr), r);
        foreach (r[n]) begin
            data.push_back(r[n].data);
            resp = at::worst(resp, r[n].resp);
        end
    endtask
endclass
