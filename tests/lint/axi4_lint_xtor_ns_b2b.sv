// One P of axi4_lint_xtor_ns: the generated transactors back to back, with bridges,
// and the behavioural classes on top (fw_proto_axi4_behav_pkg), each specialized so
// that the linter checks its body; and the abstractor glue (sockets, abstractors,
// handles), declared for the same reason.
module axi4_lint_xtor_ns_b2b
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_core_pkg::*, fw_proto_axi4_core_pkg_woven::*,
           fw_proto_axi4_behav_pkg::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) (
    input  logic aclk, aresetn
);
    localparam int unsigned IW_ = w1(P.ID_W), AW_ = P.ADDR_W, DW_ = P.DATA_W;
    localparam int unsigned AUW_ = w1(P.AWUSER_W), WUW_ = w1(P.WUSER_W), BUW_ = w1(P.BUSER_W);
    localparam int unsigned RAW_ = w1(P.ARUSER_W), RUW_ = w1(P.RUSER_W);
    logic awvalid, awready, awlock, wvalid, wready, wlast;
    logic bvalid, bready, arvalid, arready, arlock, rvalid, rready, rlast;
    logic [IW_-1:0]   awid, bid, arid, rid;
    logic [AW_-1:0]   awaddr, araddr;
    logic [7:0]       awlen, arlen;
    logic [2:0]       awsize, arsize, awprot, arprot;
    logic [1:0]       awburst, arburst, bresp, rresp;
    logic [3:0]       awcache, arcache, awqos, arqos, awregion, arregion;
    logic [AUW_-1:0]  awuser;
    logic [WUW_-1:0]  wuser;
    logic [BUW_-1:0]  buser;
    logic [RAW_-1:0]  aruser;
    logic [RUW_-1:0]  ruser;
    logic [DW_-1:0]   wdata, rdata;
    logic [DW_/8-1:0] wstrb;

    axi4_mgr_xtor #(P) u_mgr (.*);
    axi4_sub_xtor #(P) u_sub (.*);
    axi4_mon_xtor #(P) u_mon (.*);

    axi4_rsp_if_inbox #(P)    m_in = new;
    axi4_req_if_inbox #(P)    s_in = new;
    axi4_mgr_xtor_bridge #(P) mb = new(u_mgr.u_if, m_in);
    axi4_sub_xtor_bridge #(P) sb = new(u_sub.u_if, s_in);
    axi4_mon_xtor_bridge #(P) monb = new(u_mon.u_if);

    // manager: convenience shim -> blocking shim -> adapter -> bridge, responses
    // back up the same way; subordinate: bridge -> adapter -> memory, or -> a
    // plain-API target behind the other shim, responses back to the adapter.
    axi4_mgr_adapter #(P)     mgr = new(mb);
    axi4_burst_blocking #(P)  blk = new(mgr);
    axi4_xact_on_burst #(P)   xs = new(blk);
    axi4_mem_model #(P)       mem = new;
    axi4_sub_adapter #(P)     sub = new(sb, mem);
    axi4_burst_on_xact #(P)   bx = new(xs, sub);
    initial begin
        mgr.up = blk;
        mem.rsp = sub;
    end
    axi4_to_mem #(P, logic [31:0], logic [31:0], logic [3:0])    m32 = new(xs);
    axi4_to_mem #(P, logic [31:0], logic [127:0], logic [15:0])  m128 = new(xs);

    axi4_mgr_socket #(P) msock;
    axi4_sub_socket #(P) ssock;
    axi4_mgr_abs #(P)    mabs;
    axi4_sub_abs #(P)    sabs;
    axi4_mgr_abs_h #(P)  mh;
    axi4_sub_abs_h #(P)  sh;
    axi4_burst_mgr_socket #(P) bms;
    axi4_burst_sub_socket #(P) bss;
endmodule
