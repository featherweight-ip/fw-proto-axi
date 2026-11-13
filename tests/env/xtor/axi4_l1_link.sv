// The L1 link, view `xtor` (see axi4_l1_cell.sv for the members every view
// has): through pins, with RTL in the middle.
//
//   req -> axi4_mgr_xtor_bridge -> axi4_mgr_xtor ==A== axi4_slice (AW, W, AR)
//            ==B== axi4_sub_xtor -> axi4_sub_xtor_bridge -> sub_in
//
// and back for B and R through one axi4_slice each, B to A. Each segment packs a
// channel's pins into one vector for its slice (the defs package's stream
// layout). Each pin segment has an axi4_checker (COUNT_ONLY); axi4_mon_xtor on
// segment A is the observation. Knobs by path: "mgr.<ch>.<knob>" reaches the
// manager transactor, "sub.<ch>.<knob>" the subordinate's.
module axi4_l1_link
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    localparam int unsigned AWB_ = axi4_ax_bits(P, 1'b0);
    localparam int unsigned WB_  = axi4_wd_bits(P);
    localparam int unsigned BB_  = axi4_b_bits(P);
    localparam int unsigned ARB_ = axi4_ax_bits(P, 1'b1);
    localparam int unsigned RB_  = axi4_r_bits(P);

    bit   aclk = 0;
    logic aresetn = 0;
    always #5 aclk = ~aclk;

    // The packed channels, segment A's side (a_*) and segment B's (b_*) of the slices.
    logic            a_aw_valid, a_aw_ready, a_w_valid, a_w_ready, a_b_valid, a_b_ready;
    logic            a_ar_valid, a_ar_ready, a_r_valid, a_r_ready;
    logic [AWB_-1:0] a_aw_data, b_aw_data;
    logic [WB_-1:0]  a_w_data, b_w_data;
    logic [BB_-1:0]  a_b_data, b_b_data;
    logic [ARB_-1:0] a_ar_data, b_ar_data;
    logic [RB_-1:0]  a_r_data, b_r_data;
    logic            b_aw_valid, b_aw_ready, b_w_valid, b_w_ready, b_b_valid, b_b_ready;
    logic            b_ar_valid, b_ar_ready, b_r_valid, b_r_ready;

    axi4_l1_seg_a #(P) u_a (.*);
    axi4_l1_seg_b #(P) u_b (.*);

    axi4_slice #(AWB_) u_aw_sl (.aclk, .aresetn,
        .in_valid(a_aw_valid), .in_ready(a_aw_ready), .in_data(a_aw_data),
        .out_valid(b_aw_valid), .out_ready(b_aw_ready), .out_data(b_aw_data));
    axi4_slice #(WB_) u_w_sl (.aclk, .aresetn,
        .in_valid(a_w_valid), .in_ready(a_w_ready), .in_data(a_w_data),
        .out_valid(b_w_valid), .out_ready(b_w_ready), .out_data(b_w_data));
    axi4_slice #(BB_) u_b_sl (.aclk, .aresetn,
        .in_valid(b_b_valid), .in_ready(b_b_ready), .in_data(b_b_data),
        .out_valid(a_b_valid), .out_ready(a_b_ready), .out_data(a_b_data));
    axi4_slice #(ARB_) u_ar_sl (.aclk, .aresetn,
        .in_valid(a_ar_valid), .in_ready(a_ar_ready), .in_data(a_ar_data),
        .out_valid(b_ar_valid), .out_ready(b_ar_ready), .out_data(b_ar_data));
    axi4_slice #(RB_) u_r_sl (.aclk, .aresetn,
        .in_valid(b_r_valid), .in_ready(b_r_ready), .in_data(b_r_data),
        .out_valid(a_r_valid), .out_ready(a_r_ready), .out_data(a_r_data));

    axi4_mgr_xtor_bridge #(P) mb;
    axi4_sub_xtor_bridge #(P) sb;
    axi4_mon_xtor_bridge #(P) monb;
    axi4_req_if_inbox #(P)    sub_in = new;
    axi4_rsp_if_inbox #(P)    mgr_in = new;
    axi4_req_if #(P)          req;
    axi4_rsp_if #(P)          rsp;
    bit                       up;

    initial begin
        mb = new(u_a.u_mgr.u_if, mgr_in);
        sb = new(u_b.u_sub.u_if, sub_in);
        monb = new(u_a.u_mon.u_if);
        req = mb;
        rsp = sb;
        fork
            mb.run();
            sb.run();
            monb.run();
        join_none
        repeat (4) @(posedge aclk);
        aresetn = 1;
        @(posedge aclk);
        up = 1;
    end

    // Replace the far ends (the inboxes) with other receivers, e.g. L2 adapters.
    function void attach(axi4_rsp_if #(P) mgr_end, axi4_req_if #(P) sub_end);
        mb.m_rsp = mgr_end;
        sb.m_req = sub_end;
    endfunction

    // The listeners' events come from the pin monitor (rules count a request at
    // its handshake).
    function bit at_pins(); return 1; endfunction
    // Segment A's checker (where the monitor is): failures counted on the manager
    // side and the subordinate side, since reset.
    function void chk_counts(output int unsigned m, output int unsigned s);
        m = u_a.u_chk.n_err_m;
        s = u_a.u_chk.n_err_s;
    endfunction
    function bit has_checker(); return 1; endfunction

    function void add_req_listener(axi4_req_if_listener #(P) l); monb.req.add_listener(l); endfunction
    function void add_rsp_listener(axi4_rsp_if_listener #(P) l); monb.rsp.add_listener(l); endfunction

    // "<role>.<ch>.<knob>": role mgr or sub; the rest goes to that transactor.
    function automatic bit set_knob(string path, int unsigned v);
        int dot = -1;
        string role, rest;
        foreach (path[i]) if (path[i] == ".") begin dot = i; break; end
        if (dot <= 0) return 0;
        role = path.substr(0, dot - 1);
        rest = path.substr(dot + 1, path.len() - 1);
        if (role == "mgr") return u_a.u_mgr.u_if.chans.set_knob(rest, v);
        if (role == "sub") return u_b.u_sub.u_if.chans.set_knob(rest, v);
        return 0;
    endfunction

    // The checkers' findings since the last call (each test asks once, at its end).
    int unsigned seen[4];
    function automatic string errors();
        int unsigned n[4] = '{u_a.u_chk.n_err_m, u_a.u_chk.n_err_s, u_b.u_chk.n_err_m, u_b.u_chk.n_err_s};
        int unsigned d[4];
        foreach (n[i]) d[i] = n[i] - seen[i];
        seen = n;
        if (d[0] + d[1] + d[2] + d[3] == 0) return "";
        return $sformatf("checker violations: A %0d mgr %0d sub, B %0d mgr %0d sub",
                         d[0], d[1], d[2], d[3]);
    endfunction

    // Long enough for the last handshakes to reach the checkers' counts.
    task settle();
        repeat (8) @(posedge aclk);
    endtask
endmodule

// The pins of one segment, named as on axi4_checker (`.*` connects).
`define AXI4_L1_PINS \
    localparam int unsigned IW_ = w1(P.ID_W), AW_ = P.ADDR_W, DW_ = P.DATA_W; \
    localparam int unsigned AUW_ = w1(P.AWUSER_W), WUW_ = w1(P.WUSER_W), BUW_ = w1(P.BUSER_W); \
    localparam int unsigned RAW_ = w1(P.ARUSER_W), RUW_ = w1(P.RUSER_W); \
    logic awvalid, awready, awlock, wvalid, wready, wlast; \
    logic bvalid, bready, arvalid, arready, arlock, rvalid, rready, rlast; \
    logic [IW_-1:0]   awid, bid, arid, rid; \
    logic [AW_-1:0]   awaddr, araddr; \
    logic [7:0]       awlen, arlen; \
    logic [2:0]       awsize, arsize, awprot, arprot; \
    logic [1:0]       awburst, arburst, bresp, rresp; \
    logic [3:0]       awcache, arcache, awqos, arqos, awregion, arregion; \
    logic [AUW_-1:0]  awuser; \
    logic [WUW_-1:0]  wuser; \
    logic [BUW_-1:0]  buser; \
    logic [RAW_-1:0]  aruser; \
    logic [RUW_-1:0]  ruser; \
    logic [DW_-1:0]   wdata, rdata; \
    logic [DW_/8-1:0] wstrb;

// Each channel's pins as one vector, in the defs package's stream layout.
`define AXI4_L1_AW {awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, \
    awqos, awregion, awuser}
`define AXI4_L1_W  {wdata, wstrb, wlast, wuser}
`define AXI4_L1_B  {bid, bresp, buser}
`define AXI4_L1_AR {arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, \
    arqos, arregion, aruser}
`define AXI4_L1_R  {rid, rdata, rresp, rlast, ruser}

// Segment A: the generated manager transactor and monitor and the checker on
// its pins; the subordinate end of the slices (requests out, responses in).
module axi4_l1_seg_a
    import fw_proto_axi4_defs_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT,
  localparam int unsigned AWB_ = axi4_ax_bits(P, 1'b0),
  localparam int unsigned WB_  = axi4_wd_bits(P),
  localparam int unsigned BB_  = axi4_b_bits(P),
  localparam int unsigned ARB_ = axi4_ax_bits(P, 1'b1),
  localparam int unsigned RB_  = axi4_r_bits(P)) (
    input  logic            aclk,
    input  logic            aresetn,
    output logic            a_aw_valid, a_w_valid, a_ar_valid, a_b_ready, a_r_ready,
    input  logic            a_aw_ready, a_w_ready, a_ar_ready, a_b_valid, a_r_valid,
    output logic [AWB_-1:0] a_aw_data,
    output logic [WB_-1:0]  a_w_data,
    output logic [ARB_-1:0] a_ar_data,
    input  logic [BB_-1:0]  a_b_data,
    input  logic [RB_-1:0]  a_r_data
);
    `AXI4_L1_PINS
    axi4_mgr_xtor #(P) u_mgr (.clock(aclk), .reset(!aresetn), .*);
    axi4_mon_xtor #(P) u_mon (.clock(aclk), .reset(!aresetn), .*);
    axi4_checker #(.P(P), .MAX_OUT(32), .COUNT_ONLY(1)) u_chk (.*);

    assign a_aw_valid = awvalid;  assign awready = a_aw_ready;  assign a_aw_data = `AXI4_L1_AW;
    assign a_w_valid  = wvalid;   assign wready  = a_w_ready;   assign a_w_data  = `AXI4_L1_W;
    assign a_ar_valid = arvalid;  assign arready = a_ar_ready;  assign a_ar_data = `AXI4_L1_AR;
    assign bvalid = a_b_valid;    assign a_b_ready = bready;    assign `AXI4_L1_B = a_b_data;
    assign rvalid = a_r_valid;    assign a_r_ready = rready;    assign `AXI4_L1_R = a_r_data;
endmodule

// Segment B: the manager end of the slices (requests in, responses out), the
// checker on its pins, and the generated subordinate transactor.
module axi4_l1_seg_b
    import fw_proto_axi4_defs_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT,
  localparam int unsigned AWB_ = axi4_ax_bits(P, 1'b0),
  localparam int unsigned WB_  = axi4_wd_bits(P),
  localparam int unsigned BB_  = axi4_b_bits(P),
  localparam int unsigned ARB_ = axi4_ax_bits(P, 1'b1),
  localparam int unsigned RB_  = axi4_r_bits(P)) (
    input  logic            aclk,
    input  logic            aresetn,
    input  logic            b_aw_valid, b_w_valid, b_ar_valid, b_b_ready, b_r_ready,
    output logic            b_aw_ready, b_w_ready, b_ar_ready, b_b_valid, b_r_valid,
    input  logic [AWB_-1:0] b_aw_data,
    input  logic [WB_-1:0]  b_w_data,
    input  logic [ARB_-1:0] b_ar_data,
    output logic [BB_-1:0]  b_b_data,
    output logic [RB_-1:0]  b_r_data
);
    `AXI4_L1_PINS
    axi4_checker #(.P(P), .MAX_OUT(32), .COUNT_ONLY(1)) u_chk (.*);
    axi4_sub_xtor #(P) u_sub (.clock(aclk), .reset(!aresetn), .*);

    assign awvalid = b_aw_valid;  assign b_aw_ready = awready;  assign `AXI4_L1_AW = b_aw_data;
    assign wvalid  = b_w_valid;   assign b_w_ready  = wready;   assign `AXI4_L1_W  = b_w_data;
    assign arvalid = b_ar_valid;  assign b_ar_ready = arready;  assign `AXI4_L1_AR = b_ar_data;
    assign b_b_valid = bvalid;    assign bready = b_b_ready;    assign b_b_data = `AXI4_L1_B;
    assign b_r_valid = rvalid;    assign rready = b_r_ready;    assign b_r_data = `AXI4_L1_R;
endmodule
`undef AXI4_L1_PINS
`undef AXI4_L1_AW
`undef AXI4_L1_W
`undef AXI4_L1_B
`undef AXI4_L1_AR
`undef AXI4_L1_R
