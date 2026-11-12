virtual class ip_axi_tb #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_component
        implements fw_runnable;
    typedef axi4_types #(P)::aw_t     aw_t;
    typedef axi4_types #(P)::w_t      w_t;
    typedef axi4_types #(P)::b_t      b_t;
    typedef axi4_types #(P)::ar_t     ar_t;
    typedef axi4_types #(P)::r_t      r_t;
    typedef axi4_types #(P)::attr_t   attr_t;
    typedef axi4_types #(P)::addr_t   addr_t;
    typedef axi4_types #(P)::data_t   data_t;
    typedef axi4_types #(P)::strb_t   strb_t;
    typedef logic [w1(P.ID_W)-1:0]    id_t;
    typedef axi4_attr #(P)            at;
    localparam int unsigned BUS = P.DATA_W / 8;

    axi4_mgr_socket #(P)     m;
    axi4_mgr_adapter #(P)    mgr;      // responses up to blk
    axi4_burst_blocking #(P) blk;      // blocking bursts, for the tests
    axi4_xact_on_burst #(P)  xact;
    axi4_mem_model #(P)      ref_m;    // the reference: apply_write/apply_read

    // Read data, when it is not the memory's: every active lane reads this.
    bit          const_rdata;
    data_t       rdata_value;
    // Burst types the IP serves (WRAP is optional in some).
    bit          use_fixed = 1, use_wrap = 0;

    int unsigned n_errors, n_checks;
    bit          done;

    // Teeth: +plant makes the first write burst to the IP differ from the
    // reference's (one data bit of its first strobed lane); with
    // const_rdata, it flips a bit of the value reads are checked against.
    bit          planted;

    function new(string name, fw_component parent);
        super.new(name, parent);
        parent.add_runnable(this);
    endfunction

    function void build();
        mgr   = new();
        blk   = new(mgr);
        mgr.up = blk;
        m     = new("m", this, mgr);
        xact  = new(blk);
        ref_m = new();
    endfunction

    // The tests, after the adapter is joined to the socket.
    pure virtual task tests();

    virtual task run();
        mgr.req = m.t;
        if (const_rdata && $test$plusargs("plant")) rdata_value[0] = ~rdata_value[0];
        tests();
        if (mgr.n_errors != 0) error($sformatf("manager adapter: %0d errors", mgr.n_errors));
        if (blk.n_errors != 0) error($sformatf("blocking shim: %0d errors", blk.n_errors));
        done = 1;
    endtask

    function void error(string msg);
        $display("[%s] error: %s", get_name(), msg);
        n_errors++;
    endfunction

    // One write burst to the IP (and the reference), checked: OKAY, its ID.
    task wr(aw_t aw, w_t w[$]);
        b_t b;
        w_t wd[$] = w;
        if (!planted && $test$plusargs("plant")) begin
            foreach (wd[i]) if (!planted)
                for (int unsigned l = 0; l < BUS; l++)
                    if (!planted && wd[i].strb[l]) begin
                        wd[i].data[8*l] = ~wd[i].data[8*l];
                        planted = 1;
                    end
        end
        blk.write(aw, wd, b);
        void'(ref_m.apply_write(aw, w));
        n_checks++;
        if (b.resp != AXI4_RESP_OKAY || b.id != aw.id)
            error($sformatf("write @%0h id %0h: B id %0h resp %s", aw.addr, aw.id, b.id,
                            b.resp.name()));
    endtask

    // One read burst, checked beat by beat on the active lanes.
    task rd(ar_t ar);
        r_t r[$], rr[$];
        blk.read(ar, r);
        ref_m.apply_read(ar, rr);
        n_checks++;
        if (r.size() != int'(ar.len) + 1) begin
            error($sformatf("read @%0h: %0d beats, expected %0d", ar.addr, r.size(),
                            int'(ar.len) + 1));
            return;
        end
        foreach (r[i]) begin
            strb_t ln = at::lanes(64'(ar.addr), ar.size, ar.len, ar.burst, i);
            data_t exp = const_rdata ? rdata_value : rr[i].data;
            for (int unsigned l = 0; l < BUS; l++)
                if (ln[l] && r[i].data[8*l +: 8] !== exp[8*l +: 8])
                    error($sformatf("read @%0h id %0h beat %0d lane %0d: %02h, expected %02h",
                                    ar.addr, ar.id, i, l, r[i].data[8*l +: 8], exp[8*l +: 8]));
            if (r[i].id != ar.id || r[i].resp != AXI4_RESP_OKAY)
                error($sformatf("read @%0h beat %0d: id %0h resp %s", ar.addr, i, r[i].id,
                                r[i].resp.name()));
        end
    endtask

    // A random burst inside [base, base + 4 KiB): any size up to the bus,
    // random strobes on the active lanes, and the read of the same range.
    function void rand_burst(addr_t base, id_t id, output aw_t aw, output w_t w[$],
                             output ar_t ar);
        axi4_size_e  size  = axi4_size_e'($urandom_range($clog2(BUS), 0));
        int unsigned pick  = $urandom_range(5);
        axi4_burst_e burst = (use_fixed && pick == 0) ? AXI4_BURST_FIXED
                           : (use_wrap && pick == 1)  ? AXI4_BURST_WRAP : AXI4_BURST_INCR;
        int unsigned beats = (burst == AXI4_BURST_WRAP) ? (2 << $urandom_range(3))
                                                        : $urandom_range(16, 1);
        int unsigned span  = beats << size;
        int unsigned off   = $urandom_range(4096 - span) & ~((1 << size) - 1);
        if (burst == AXI4_BURST_WRAP) off = off & ~(span - 1);
        aw = '0;
        aw.id = id; aw.addr = addr_t'(base + off); aw.len = 8'(beats - 1);
        aw.size = size; aw.burst = burst;
        w.delete();
        for (int unsigned i = 0; i < beats; i++) begin
            w_t f = '0;
            strb_t ln = at::lanes(64'(aw.addr), size, aw.len, burst, i);
            for (int unsigned k = 0; k < (P.DATA_W + 31) / 32; k++)
                f.data = (f.data << 32) | data_t'($urandom());
            f.strb = ln & strb_t'($urandom());
            f.last = (i == beats - 1);
            w.push_back(f);
        end
        ar = '0;
        ar.id = id; ar.addr = aw.addr; ar.len = aw.len; ar.size = size; ar.burst = burst;
    endfunction

    // ---- the scenarios
    // One full-width beat through the convenience API.
    task single_write_read(addr_t addr);
        attr_t      a = '0;
        data_t      d[$];
        data_t      v = data_t'(64'hcafe_f00d_1234_5678);
        axi4_resp_e resp;
        a.size = axi4_size_e'($clog2(BUS));
        a.burst = AXI4_BURST_INCR;
        xact.write(addr, '{v}, '{'1}, a, resp);
        if (resp != AXI4_RESP_OKAY) error({"single write: ", resp.name()});
        xact.read(addr, 1, a, d, resp);
        n_checks++;
        if (!const_rdata) begin
            w_t  w[$];
            w_t  f = '0;
            f.data = v; f.strb = '1; f.last = 1;
            w.push_back(f);
            void'(ref_m.apply_write(at::to_aw(addr, 1, a), w));
        end
        if (resp != AXI4_RESP_OKAY || d.size() != 1
                || d[0] !== (const_rdata ? rdata_value : v))
            error($sformatf("single read: %s, %0d beats, %h", resp.name(), d.size(),
                            (d.size() != 0) ? d[0] : '0));
    endtask

    task random_bursts(addr_t base, int unsigned n);
        repeat (n) begin
            aw_t aw;
            w_t  w[$];
            ar_t ar;
            rand_burst(base, id_t'($urandom()), aw, w, ar);
            wr(aw, w);
            rd(ar);
        end
    endtask

    // `k` IDs at once, each in its own 4 KiB page, so the reference's
    // order does not depend on interleaving.
    task concurrent_ids(addr_t base, int unsigned k, int unsigned n);
        for (int unsigned t = 0; t < k; t++) begin
            automatic int unsigned tt = t;
            fork
                repeat (n) begin
                    aw_t aw;
                    w_t  w[$];
                    ar_t ar;
                    rand_burst(addr_t'(base + 4096 * tt), id_t'(tt + 1), aw, w, ar);
                    wr(aw, w);
                    rd(ar);
                end
            join_none
        end
        wait fork;
    endtask
endclass
