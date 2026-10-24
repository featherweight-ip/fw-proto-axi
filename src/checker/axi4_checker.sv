// Passive AXI4 interface checker, pins only. IHI0022H A3.1.2, A3.2.1,
// A3.3.1, A3.4.1, A5, A7.2.4. Synthesizable immediate assertions on
// registered history, so the same file serves sim and formal (SymbiYosys,
// through sv2v).
//
// Each rule binds one side of the interface. ASSUME_MGR / ASSUME_SUB turn
// that side's rules into assumptions, for a formal harness whose inputs on
// that side are free.
//
// Bookkeeping is bounded: at most MAX_OUT write bursts (AW accepted, B not
// yet) and MAX_OUT read bursts (AR accepted, last R not yet) are tracked,
// and at most MAX_OUT write-data bursts may run ahead of their AW. Going
// past that is a checker-capacity failure, reported on the manager side.
module axi4_checker
    import axi4_types_pkg::*;
#(
    parameter axi4_param_t P          = AXI4_PARAM_DEFAULT,
    parameter int unsigned MAX_OUT    = 8,
    parameter bit          ASSUME_MGR = 1'b0,
    parameter bit          ASSUME_SUB = 1'b0,
    // Field widths, from P. A width of 0 (signal absent) is carried as one
    // bit, tied off by the user.
    localparam int unsigned AW_  = P.ADDR_W,
    localparam int unsigned DW_  = P.DATA_W,
    localparam int unsigned IW_  = (P.ID_W     > 0) ? P.ID_W     : 1,
    localparam int unsigned AUW_ = (P.AWUSER_W > 0) ? P.AWUSER_W : 1,
    localparam int unsigned WUW_ = (P.WUSER_W  > 0) ? P.WUSER_W  : 1,
    localparam int unsigned BUW_ = (P.BUSER_W  > 0) ? P.BUSER_W  : 1,
    localparam int unsigned RAW_ = (P.ARUSER_W > 0) ? P.ARUSER_W : 1,
    localparam int unsigned RUW_ = (P.RUSER_W  > 0) ? P.RUSER_W  : 1
) (
    input logic             aclk,
    input logic             aresetn,
    // AW
    input logic             awvalid,
    input logic             awready,
    input logic [IW_-1:0]   awid,
    input logic [AW_-1:0]   awaddr,
    input logic [7:0]       awlen,
    input logic [2:0]       awsize,
    input logic [1:0]       awburst,
    input logic             awlock,
    input logic [3:0]       awcache,
    input logic [2:0]       awprot,
    input logic [3:0]       awqos,
    input logic [3:0]       awregion,
    input logic [AUW_-1:0]  awuser,
    // W
    input logic             wvalid,
    input logic             wready,
    input logic [DW_-1:0]   wdata,
    input logic [DW_/8-1:0] wstrb,
    input logic             wlast,
    input logic [WUW_-1:0]  wuser,
    // B
    input logic             bvalid,
    input logic             bready,
    input logic [IW_-1:0]   bid,
    input logic [1:0]       bresp,
    input logic [BUW_-1:0]  buser,
    // AR
    input logic             arvalid,
    input logic             arready,
    input logic [IW_-1:0]   arid,
    input logic [AW_-1:0]   araddr,
    input logic [7:0]       arlen,
    input logic [2:0]       arsize,
    input logic [1:0]       arburst,
    input logic             arlock,
    input logic [3:0]       arcache,
    input logic [2:0]       arprot,
    input logic [3:0]       arqos,
    input logic [3:0]       arregion,
    input logic [RAW_-1:0]  aruser,
    // R
    input logic             rvalid,
    input logic             rready,
    input logic [IW_-1:0]   rid,
    input logic [DW_-1:0]   rdata,
    input logic [1:0]       rresp,
    input logic             rlast,
    input logic [RUW_-1:0]  ruser
);
    localparam int unsigned N         = MAX_OUT;
    localparam int unsigned CW        = $clog2(N + 1);  // counts 0..N
    localparam int unsigned XW        = $clog2(N);      // indexes 0..N-1
    localparam int unsigned BUS_BYTES = DW_ / 8;

    // A manager-side and a subordinate-side rule. Used as statements only
    // (never directly before an `else`). The inner begin/end keep an `else`
    // from binding to the assertion as its fail action.
`define AXI4_CHK_M(c) begin if (ASSUME_MGR) begin assume (c); end else begin assert (c); end end
`define AXI4_CHK_S(c) begin if (ASSUME_SUB) begin assume (c); end else begin assert (c); end end

    // ------------------------------------------------------------------
    // Payloads, for the stability rules
    // ------------------------------------------------------------------
    wire [IW_+AW_+8+3+2+1+4+3+4+4+AUW_-1:0] aw_pl = {awid, awaddr, awlen, awsize,
        awburst, awlock, awcache, awprot, awqos, awregion, awuser};
    wire [DW_+DW_/8+1+WUW_-1:0] w_pl = {wdata, wstrb, wlast, wuser};
    wire [IW_+2+BUW_-1:0] b_pl = {bid, bresp, buser};
    wire [IW_+AW_+8+3+2+1+4+3+4+4+RAW_-1:0] ar_pl = {arid, araddr, arlen, arsize,
        arburst, arlock, arcache, arprot, arqos, arregion, aruser};
    wire [IW_+DW_+2+1+RUW_-1:0] r_pl = {rid, rdata, rresp, rlast, ruser};

    logic past_aresetn;
    logic past_awvalid, past_awready, past_wvalid, past_wready;
    logic past_bvalid, past_bready, past_arvalid, past_arready;
    logic past_rvalid, past_rready;
    logic [$bits(aw_pl)-1:0] past_aw_pl;
    logic [$bits(w_pl)-1:0]  past_w_pl;
    logic [$bits(b_pl)-1:0]  past_b_pl;
    logic [$bits(ar_pl)-1:0] past_ar_pl;
    logic [$bits(r_pl)-1:0]  past_r_pl;

    always_ff @(posedge aclk) begin
        past_aresetn <= aresetn;
        past_awvalid <= awvalid;  past_awready <= awready;  past_aw_pl <= aw_pl;
        past_wvalid  <= wvalid;   past_wready  <= wready;   past_w_pl  <= w_pl;
        past_bvalid  <= bvalid;   past_bready  <= bready;   past_b_pl  <= b_pl;
        past_arvalid <= arvalid;  past_arready <= arready;  past_ar_pl <= ar_pl;
        past_rvalid  <= rvalid;   past_rready  <= rready;   past_r_pl  <= r_pl;
    end

    wire aw_hs = awvalid && awready;
    wire w_hs  = wvalid  && wready;
    wire b_hs  = bvalid  && bready;
    wire ar_hs = arvalid && arready;
    wire r_hs  = rvalid  && rready;

    // ------------------------------------------------------------------
    // Write tracking. wq: accepted AW bursts in age order (compacted),
    // each with its ID, AWLEN and whether its last W beat has passed.
    // W data goes to the oldest entry without it (no interleaving in
    // AXI4). we: completed write-data bursts that ran ahead of their AW
    // (A3.3.1 lets W precede AW), by beat count - 1. wcur: beats of the
    // write-data burst in progress.
    // ------------------------------------------------------------------
    logic [N-1:0]          wq_v, wq_done;
    logic [N-1:0][IW_-1:0] wq_id;
    logic [N-1:0][7:0]     wq_len;
    logic [N-1:0][7:0]     we_len;
    logic [CW-1:0]         we_n;
    logic [7:0]            wcur;

    logic                  w_tgt_ok;    // a wq entry awaits write data
    logic [XW-1:0]         w_tgt;
    logic                  b_ok;        // an entry with BID is complete
    logic [XW-1:0]         b_idx;

    always_comb begin
        w_tgt_ok = 1'b0;  w_tgt = '0;
        b_ok     = 1'b0;  b_idx = '0;
        for (int i = N - 1; i >= 0; i--) begin
            if (wq_v[i] && !wq_done[i]) begin
                w_tgt_ok = 1'b1;  w_tgt = XW'(i);
            end
            if (wq_v[i] && wq_done[i] && wq_id[i] == bid) begin
                b_ok = 1'b1;  b_idx = XW'(i);
            end
        end
    end

    // The W beat of this cycle: to an existing entry, to the AW accepted
    // this cycle (nothing pending, nothing ahead), or ahead of its AW.
    wire w_to_tgt  = w_tgt_ok;
    wire w_to_new  = !w_tgt_ok && aw_hs && we_n == '0;
    wire w_ahead   = !w_tgt_ok && !w_to_new;
    // The AW of this cycle pairs with a write-data burst already done.
    wire aw_paired = aw_hs && we_n != '0;

    logic [N-1:0]          nwq_v, nwq_done;
    logic [N-1:0][IW_-1:0] nwq_id;
    logic [N-1:0][7:0]     nwq_len;
    logic [N-1:0][7:0]     nwe_len;
    logic [CW-1:0]         nwe_n;
    logic [7:0]            nwcur;
    logic                  new_done;
    logic [CW-1:0]         wq_cnt;

    always_comb begin
        logic [N-1:0] d;
        logic         rm;
        int unsigned  src;
        logic [CW-1:0] pos;
        d        = wq_done;
        new_done = aw_paired;
        nwcur    = wcur;
        nwe_len  = we_len;
        nwe_n    = we_n;
        wq_cnt   = '0;
        for (int i = 0; i < N; i++)
            if (wq_v[i]) wq_cnt = wq_cnt + 1'b1;

        if (w_hs) begin
            nwcur = wlast ? 8'd0 : wcur + 8'd1;
            if (wlast && w_to_tgt) d[w_tgt] = 1'b1;
            if (wlast && w_to_new) new_done = 1'b1;
        end

        // we: pop the head when an AW pairs with it, push a completed
        // ahead-of-AW burst.
        if (aw_paired) begin
            for (int i = 0; i < N - 1; i++) nwe_len[i] = we_len[i + 1];
            nwe_n = we_n - 1'b1;
        end
        if (w_hs && wlast && w_ahead && nwe_n < CW'(N)) begin
            nwe_len[XW'(nwe_n)] = wcur;
            nwe_n          = nwe_n + 1'b1;
        end

        // wq: remove the entry the B completes, compact, append the new AW.
        rm = b_hs && b_ok;
        for (int i = 0; i < N; i++) begin
            src = (rm && XW'(i) >= b_idx) ? i + 1 : i;
            if (src < N) begin
                nwq_v[i]    = wq_v[src];
                nwq_done[i] = d[src];
                nwq_id[i]   = wq_id[src];
                nwq_len[i]  = wq_len[src];
            end else begin
                nwq_v[i]    = 1'b0;
                nwq_done[i] = 1'b0;
                nwq_id[i]   = '0;
                nwq_len[i]  = '0;
            end
        end
        pos = wq_cnt - CW'(rm);
        if (aw_hs && pos < CW'(N)) begin
            nwq_v[XW'(pos)]    = 1'b1;
            nwq_done[XW'(pos)] = new_done;
            nwq_id[XW'(pos)]   = awid;
            nwq_len[XW'(pos)]  = awlen;
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            wq_v <= '0;  wq_done <= '0;  wq_id <= '0;  wq_len <= '0;
            we_len <= '0;  we_n <= '0;  wcur <= '0;
        end else begin
            wq_v <= nwq_v;  wq_done <= nwq_done;  wq_id <= nwq_id;  wq_len <= nwq_len;
            we_len <= nwe_len;  we_n <= nwe_n;  wcur <= nwcur;
        end
    end

    // ------------------------------------------------------------------
    // Read tracking. rq: accepted AR bursts in age order (compacted), each
    // with its ID, ARLEN and beats returned. An R beat goes to the oldest
    // entry with its RID (same-ID order, A5.3; different IDs interleave).
    // ------------------------------------------------------------------
    logic [N-1:0]          rq_v;
    logic [N-1:0][IW_-1:0] rq_id;
    logic [N-1:0][7:0]     rq_len, rq_cnt;
    logic                  r_ok;
    logic [XW-1:0]         r_idx;
    logic [CW-1:0]         rq_cnt_n;

    always_comb begin
        r_ok = 1'b0;  r_idx = '0;  rq_cnt_n = '0;
        for (int i = N - 1; i >= 0; i--)
            if (rq_v[i] && rq_id[i] == rid) begin
                r_ok = 1'b1;  r_idx = XW'(i);
            end
        for (int i = 0; i < N; i++)
            if (rq_v[i]) rq_cnt_n = rq_cnt_n + 1'b1;
    end

    logic [N-1:0]          nrq_v;
    logic [N-1:0][IW_-1:0] nrq_id;
    logic [N-1:0][7:0]     nrq_len, nrq_cnt;

    always_comb begin
        logic [N-1:0][7:0] c;
        logic              rm;
        int unsigned       src;
        logic [CW-1:0]     pos;
        c  = rq_cnt;
        rm = r_hs && r_ok && rlast;
        if (r_hs && r_ok && !rlast) c[r_idx] = rq_cnt[r_idx] + 8'd1;
        for (int i = 0; i < N; i++) begin
            src = (rm && XW'(i) >= r_idx) ? i + 1 : i;
            if (src < N) begin
                nrq_v[i]   = rq_v[src];
                nrq_id[i]  = rq_id[src];
                nrq_len[i] = rq_len[src];
                nrq_cnt[i] = c[src];
            end else begin
                nrq_v[i]   = 1'b0;
                nrq_id[i]  = '0;
                nrq_len[i] = '0;
                nrq_cnt[i] = '0;
            end
        end
        pos = rq_cnt_n - CW'(rm);
        if (ar_hs && pos < CW'(N)) begin
            nrq_v[XW'(pos)]   = 1'b1;
            nrq_id[XW'(pos)]  = arid;
            nrq_len[XW'(pos)] = arlen;
            nrq_cnt[XW'(pos)] = '0;
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rq_v <= '0;  rq_id <= '0;  rq_len <= '0;  rq_cnt <= '0;
        end else begin
            rq_v <= nrq_v;  rq_id <= nrq_id;  rq_len <= nrq_len;  rq_cnt <= nrq_cnt;
        end
    end

    // ------------------------------------------------------------------
    // Rules
    // ------------------------------------------------------------------
    // In reset, or in the first cycle after it.
    wire run = past_aresetn && aresetn;

    always_ff @(posedge aclk) begin
        // A3.1.2: VALIDs LOW during reset and in the first cycle after it.
        if (!run) begin
            `AXI4_CHK_M(!awvalid)
            `AXI4_CHK_M(!wvalid)
            `AXI4_CHK_M(!arvalid)
            `AXI4_CHK_S(!bvalid)
            `AXI4_CHK_S(!rvalid)
        end
        if (run) begin
            // A3.2.1: once VALID is HIGH it stays HIGH, with the payload
            // unchanged, until the handshake.
            if (past_awvalid && !past_awready) `AXI4_CHK_M(awvalid && aw_pl == past_aw_pl)
            if (past_wvalid  && !past_wready)  `AXI4_CHK_M(wvalid  && w_pl  == past_w_pl)
            if (past_arvalid && !past_arready) `AXI4_CHK_M(arvalid && ar_pl == past_ar_pl)
            if (past_bvalid  && !past_bready)  `AXI4_CHK_S(bvalid  && b_pl  == past_b_pl)
            if (past_rvalid  && !past_rready)  `AXI4_CHK_S(rvalid  && r_pl  == past_r_pl)

            // A3.4.1 burst rules; A7.2.4 exclusive-access rules.
            if (awvalid) begin
                `AXI4_CHK_M(axi4_burst_legal(axi4_addr_t'(awaddr), axi4_size_e'(awsize),
                    awlen, axi4_burst_e'(awburst), BUS_BYTES))
                if (awlock)
                    `AXI4_CHK_M(axi4_excl_legal(axi4_addr_t'(awaddr), axi4_size_e'(awsize), awlen))
            end
            if (arvalid) begin
                `AXI4_CHK_M(axi4_burst_legal(axi4_addr_t'(araddr), axi4_size_e'(arsize),
                    arlen, axi4_burst_e'(arburst), BUS_BYTES))
                if (arlock)
                    `AXI4_CHK_M(axi4_excl_legal(axi4_addr_t'(araddr), axi4_size_e'(arsize), arlen))
            end

            // A3.4.1 / A2.3: WLAST on, and only on, beat AWLEN+1 of each
            // write-data burst, in AW order.
            if (w_hs && w_to_tgt) `AXI4_CHK_M(wlast == (wcur == wq_len[w_tgt]))
            if (w_hs && w_to_new) `AXI4_CHK_M(wlast == (wcur == awlen))
            if (w_hs && w_ahead && wcur == 8'd255) `AXI4_CHK_M(wlast)
            if (aw_paired) `AXI4_CHK_M(awlen == we_len[0])
            // Data that ran ahead of this AW must fit it (with or without a
            // W beat this cycle).
            if (aw_hs && !w_tgt_ok && we_n == '0) `AXI4_CHK_M(wcur <= awlen)

            // Checker capacity (MAX_OUT).
            if (awvalid) `AXI4_CHK_M(wq_cnt < CW'(N))
            if (arvalid) `AXI4_CHK_M(rq_cnt_n < CW'(N))
            if (w_hs && wlast && w_ahead) `AXI4_CHK_M(we_n < CW'(N))

            // A3.3.1, A5: B only for a write whose AW and last W beat have
            // both been accepted, with that write's ID.
            if (bvalid) `AXI4_CHK_S(b_ok)

            // A5: R only for an outstanding read with that ID; A3.4.1:
            // RLAST on, and only on, beat ARLEN+1.
            if (rvalid) `AXI4_CHK_S(r_ok)
            if (rvalid && r_ok) `AXI4_CHK_S(rlast == (rq_cnt[r_idx] == rq_len[r_idx]))
        end
`ifndef FORMAL
        // No X on the controls out of reset, nor on a payload while VALID.
        if (run) begin
            `AXI4_CHK_M(!$isunknown({awvalid, wvalid, arvalid, bready, rready}))
            `AXI4_CHK_S(!$isunknown({bvalid, rvalid, awready, wready, arready}))
            if (awvalid) `AXI4_CHK_M(!$isunknown(aw_pl))
            if (wvalid)  `AXI4_CHK_M(!$isunknown(w_pl))
            if (arvalid) `AXI4_CHK_M(!$isunknown(ar_pl))
            if (bvalid)  `AXI4_CHK_S(!$isunknown(b_pl))
            if (rvalid)  `AXI4_CHK_S(!$isunknown(r_pl))
        end
`endif
    end

`undef AXI4_CHK_M
`undef AXI4_CHK_S
endmodule
