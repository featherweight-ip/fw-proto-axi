// The L1 link, view `xtor` (see axi4_l1_ns_cell.sv for the members every view
// has): through pins, with RTL in the middle.
//
//   req -> axi4_mgr_xtor_bridge -> axi4_mgr_xtor ==A== axi4_sub_core
//            -> axi4_mgr_core ==B== axi4_sub_xtor -> axi4_sub_xtor_bridge -> sub_in
//
// and back for B and R. The cores are the old slice-based ones (one
// axi4_slice per channel each way), joined by their packed user streams. Each
// pin segment has an axi4_checker (COUNT_ONLY); axi4_mon_xtor on segment A
// is the observation. Knobs by path: "mgr.<ch>.<knob>" reaches the manager
// transactor, "sub.<ch>.<knob>" the subordinate's.
module axi4_l1_ns_link
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) ();
    // The checker and the cores take the old package's parameter struct.
    localparam axi4_types_pkg::axi4_param_t CP = '{
        ADDR_W: P.ADDR_W, DATA_W: P.DATA_W, ID_W: P.ID_W, AWUSER_W: P.AWUSER_W,
        WUSER_W: P.WUSER_W, BUSER_W: P.BUSER_W, ARUSER_W: P.ARUSER_W, RUSER_W: P.RUSER_W};
    localparam int unsigned AWB_ = axi4_types_pkg::axi4_ax_bits(CP, 1'b0);
    localparam int unsigned WB_  = axi4_types_pkg::axi4_wd_bits(CP);
    localparam int unsigned BB_  = axi4_types_pkg::axi4_b_bits(CP);
    localparam int unsigned ARB_ = axi4_types_pkg::axi4_ax_bits(CP, 1'b1);
    localparam int unsigned RB_  = axi4_types_pkg::axi4_r_bits(CP);

    bit   aclk = 0;
    logic aresetn = 0;
    always #5 aclk = ~aclk;

    // The cores' user streams, sub_core (segment A) to mgr_core (segment B).
    logic            aw_valid, aw_ready, w_valid, w_ready, b_valid, b_ready;
    logic            ar_valid, ar_ready, r_valid, r_ready;
    logic [AWB_-1:0] aw_data;
    logic [WB_-1:0]  w_data;
    logic [BB_-1:0]  b_data;
    logic [ARB_-1:0] ar_data;
    logic [RB_-1:0]  r_data;

    axi4_l1_ns_seg_a #(P, CP) u_a (.*);
    axi4_l1_ns_seg_b #(P, CP) u_b (.*);

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
`define AXI4_L1_NS_PINS \
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

// Segment A: the generated manager transactor and monitor, the checker, and
// the subordinate core that turns the pins into user streams.
module axi4_l1_ns_seg_a
    import fw_proto_axi4_defs_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT,
  axi4_types_pkg::axi4_param_t CP = axi4_types_pkg::AXI4_PARAM_DEFAULT,
  localparam int unsigned AWB_ = axi4_types_pkg::axi4_ax_bits(CP, 1'b0),
  localparam int unsigned WB_  = axi4_types_pkg::axi4_wd_bits(CP),
  localparam int unsigned BB_  = axi4_types_pkg::axi4_b_bits(CP),
  localparam int unsigned ARB_ = axi4_types_pkg::axi4_ax_bits(CP, 1'b1),
  localparam int unsigned RB_  = axi4_types_pkg::axi4_r_bits(CP)) (
    input  logic            aclk,
    input  logic            aresetn,
    output logic            aw_valid, w_valid, ar_valid, b_ready, r_ready,
    input  logic            aw_ready, w_ready, ar_ready, b_valid, r_valid,
    output logic [AWB_-1:0] aw_data,
    output logic [WB_-1:0]  w_data,
    output logic [ARB_-1:0] ar_data,
    input  logic [BB_-1:0]  b_data,
    input  logic [RB_-1:0]  r_data
);
    `AXI4_L1_NS_PINS
    axi4_mgr_xtor #(P) u_mgr (.*);
    axi4_mon_xtor #(P) u_mon (.*);
    axi4_checker #(.P(CP), .MAX_OUT(32), .COUNT_ONLY(1)) u_chk (.*);
    axi4_sub_core #(.P(CP)) u_core (.*);
endmodule

// Segment B: the manager core driving the pins from the user streams, the
// checker, and the generated subordinate transactor.
module axi4_l1_ns_seg_b
    import fw_proto_axi4_defs_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT,
  axi4_types_pkg::axi4_param_t CP = axi4_types_pkg::AXI4_PARAM_DEFAULT,
  localparam int unsigned AWB_ = axi4_types_pkg::axi4_ax_bits(CP, 1'b0),
  localparam int unsigned WB_  = axi4_types_pkg::axi4_wd_bits(CP),
  localparam int unsigned BB_  = axi4_types_pkg::axi4_b_bits(CP),
  localparam int unsigned ARB_ = axi4_types_pkg::axi4_ax_bits(CP, 1'b1),
  localparam int unsigned RB_  = axi4_types_pkg::axi4_r_bits(CP)) (
    input  logic            aclk,
    input  logic            aresetn,
    input  logic            aw_valid, w_valid, ar_valid, b_ready, r_ready,
    output logic            aw_ready, w_ready, ar_ready, b_valid, r_valid,
    input  logic [AWB_-1:0] aw_data,
    input  logic [WB_-1:0]  w_data,
    input  logic [ARB_-1:0] ar_data,
    output logic [BB_-1:0]  b_data,
    output logic [RB_-1:0]  r_data
);
    `AXI4_L1_NS_PINS
    axi4_mgr_core #(.P(CP)) u_core (.*);
    axi4_checker #(.P(CP), .MAX_OUT(32), .COUNT_ONLY(1)) u_chk (.*);
    axi4_sub_xtor #(P) u_sub (.*);
endmodule
`undef AXI4_L1_NS_PINS
