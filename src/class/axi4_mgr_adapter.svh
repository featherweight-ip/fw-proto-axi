// L2 -> L1, manager side: turns axi4_xact calls into AW/W/AR beats on the
// link socket and routes B/R beats back to their transactions.
//
//   * any number of callers may be in xact() at once;
//   * a write sends AW then all its W beats with no other write's beats in
//     between (AXI4 has no WID: W data follows AW order, A5.2);
//   * responses are matched per ID in issue order (A5/A6: the subordinate
//     returns same-ID responses in order; different IDs may reorder).
class axi4_mgr_adapter extends fw_component;
    `FW_AXI4_MGR_SOCKET_IMP(axi4_mgr_adapter, axi);
    `FW_AXI4_XACT_IMP(axi4_mgr_adapter, xact);    // what callers use

    axi4_cfg          cfg;
    int unsigned      n_errors;

    local semaphore   m_wr_sem = new(1);
    local semaphore   m_rd_sem = new(1);
    local axi4_xact   m_wr[axi4_id_t][$];
    local axi4_xact   m_rd[axi4_id_t][$];
    local int unsigned m_n_out;

    function new(string name, fw_component parent, axi4_cfg cfg = null);
        super.new(name, parent);
        this.cfg = cfg;
        if (this.cfg == null) this.cfg = new();
    endfunction

    function void build();
        axi  = new(this);
        xact = new(this);
    endfunction

    function void error(string msg);
        n_errors++;
        $display("%0t axi4_mgr_adapter %s: ERROR %s", $time, get_full_name(), msg);
    endfunction

    function bit idle();
        return m_n_out == 0;
    endfunction

    // Responses come back with the ID as the link carries it (masked to
    // cfg), so outstanding transactions are keyed by that.
    task xact_xact(axi4_xact x);
        axi4_addr_beat_t ax = cfg.mask_ax(x.to_ax(), !x.write);
        x.done = 0;
        x.resp = AXI4_RESP_OKAY;
        m_n_out++;
        if (x.write) begin
            if (x.data.size() != x.n_beats())
                error($sformatf("write with %0d data beats, len %0d", x.data.size(), x.len));
            m_wr_sem.get();
            m_wr[ax.id].push_back(x);
            axi.t.aw(ax);
            for (int unsigned n = 0; n < x.n_beats(); n++)
                axi.t.w(cfg.mask_w(x.to_w(n)));
            m_wr_sem.put();
        end else begin
            x.data.delete(); x.rresp.delete(); x.ruser.delete();
            m_rd_sem.get();
            m_rd[ax.id].push_back(x);
            axi.t.ar(ax);
            m_rd_sem.put();
        end
        wait (x.done);
        m_n_out--;
    endtask

    task axi_b(input axi4_b_beat_t f);
        axi4_xact x;
        if (!m_wr.exists(f.id) || m_wr[f.id].size() == 0) begin
            error($sformatf("B for ID 0x%0h with no write outstanding", f.id));
            return;
        end
        x = m_wr[f.id].pop_front();
        x.resp  = f.resp;
        x.buser = f.user;
        x.done  = 1;
    endtask

    task axi_r(input axi4_r_beat_t f);
        axi4_xact x;
        if (!m_rd.exists(f.id) || m_rd[f.id].size() == 0) begin
            error($sformatf("R for ID 0x%0h with no read outstanding", f.id));
            return;
        end
        x = m_rd[f.id][0];
        x.data.push_back(f.data);
        x.rresp.push_back(f.resp);
        x.ruser.push_back(f.user);
        x.resp = axi4_xact::worst(x.resp, f.resp);
        if (f.last != (x.data.size() == x.n_beats()))
            error($sformatf("RLAST=%0b on beat %0d of %0d (ID 0x%0h)",
                f.last, x.data.size(), x.n_beats(), f.id));
        if (f.last || x.data.size() == x.n_beats()) begin
            void'(m_rd[f.id].pop_front());
            x.done = 1;
        end
    endtask
endclass
