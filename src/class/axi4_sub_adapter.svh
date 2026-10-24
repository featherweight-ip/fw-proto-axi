// L1 -> L2, subordinate side: assembles AW/W and AR beats from the link
// mirror into axi4_xact calls on a target (port `tgt`), and returns the
// target's response as B / R beats.
//
//   * W beats are joined to AWs in order; W may arrive ahead of its AW
//     (A3.3.1). WLAST must fall on beat len+1;
//   * per ID (and direction), transactions are served one at a time in
//     arrival order, so same-ID responses return in order (A5/A6);
//   * different IDs are served concurrently; with max_delay != 0 each
//     transaction first waits a random 0..max_delay ticks, so responses to
//     different IDs come back reordered;
//   * a read's R beats go out back to back (no interleaving across IDs).
class axi4_sub_adapter extends fw_component;
    `FW_AXI4_SUB_MIRROR_IMP(axi4_sub_adapter, axi);
    fw_port #(axi4_xact_if) tgt;

    axi4_cfg          cfg;
    int unsigned      max_delay;     // ticks; 0: serve at once
    int unsigned      n_errors;

    local axi4_xact     m_aw[$];     // writes waiting for their W beats
    local axi4_w_beat_t m_w[$];      // W beats ahead of their AW
    local axi4_id_turns m_wr_turns = new();
    local axi4_id_turns m_rd_turns = new();
    local semaphore     m_b_sem = new(1);
    local semaphore     m_r_sem = new(1);
    local int unsigned  m_n_active;

    function new(string name, fw_component parent, axi4_cfg cfg = null);
        super.new(name, parent);
        this.cfg = cfg;
        if (this.cfg == null) this.cfg = new();
    endfunction

    function void build();
        axi = new(this);
        tgt = new("tgt", this);
    endfunction

    function void error(string msg);
        n_errors++;
        $display("%0t axi4_sub_adapter %s: ERROR %s", $time, get_full_name(), msg);
    endfunction

    function bit idle();
        return m_aw.size() == 0 && m_w.size() == 0 && m_n_active == 0;
    endfunction

    task axi_aw(input axi4_aw_beat_t f);
        m_aw.push_back(axi4_xact::from_ax(f, 1));
        join_w();
    endtask

    task axi_w(input axi4_w_beat_t f);
        m_w.push_back(f);
        join_w();
    endtask

    task axi_ar(input axi4_ar_beat_t f);
        axi4_xact x = axi4_xact::from_ax(f, 0);
        launch(x, m_rd_turns.ticket(x.id));
    endtask

    // Hand W beats to the oldest write still short of data.
    local task join_w();
        while (m_aw.size() != 0 && m_w.size() != 0) begin
            axi4_xact     x = m_aw[0];
            axi4_w_beat_t w = m_w.pop_front();
            bit           full;
            x.data.push_back(w.data);
            x.strb.push_back(w.strb);
            x.wuser.push_back(w.user);
            full = (x.data.size() == x.n_beats());
            if (w.last != full)
                error($sformatf("WLAST=%0b on beat %0d of %0d (AWID 0x%0h)",
                    w.last, x.data.size(), x.n_beats(), x.id));
            if (full) begin
                void'(m_aw.pop_front());
                launch(x, m_wr_turns.ticket(x.id));
            end
        end
    endtask

    local task launch(axi4_xact x, int unsigned t);
        m_n_active++;
        fork serve(x, t); join_none
    endtask

    local task serve(axi4_xact x, int unsigned t);
        axi4_id_turns turns = x.write ? m_wr_turns : m_rd_turns;
        if (max_delay != 0) tick($urandom_range(max_delay));
        turns.wait_turn(x.id, t);
        x.resp = AXI4_RESP_OKAY;
        tgt.t.xact(x);
        if (x.write) begin
            m_b_sem.get();
            axi.t.b(cfg.mask_b(x.to_b()));
            m_b_sem.put();
        end else begin
            if (x.data.size() != x.n_beats())
                error($sformatf("target returned %0d read beats, len %0d",
                    x.data.size(), x.len));
            m_r_sem.get();
            for (int unsigned n = 0; n < x.n_beats(); n++)
                axi.t.r(cfg.mask_r(x.to_r(n)));
            m_r_sem.put();
        end
        turns.release_turn(x.id);
        m_n_active--;
    endtask
endclass
