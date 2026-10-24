// Lint elaboration: axi4_mgr_xtor -> axi4_sub_xtor on internal pins, with
// an axi4_mon_xtor on them. The class-facing streams are left to the
// (absent) bridges.
module axi4_lint_xtor
    import axi4_types_pkg::*;
#(
    parameter axi4_param_t P = AXI4_PARAM_DEFAULT,
    localparam int unsigned AW_  = P.ADDR_W,
    localparam int unsigned DW_  = P.DATA_W,
    localparam int unsigned IW_  = axi4_w1(P.ID_W),
    localparam int unsigned AUW_ = axi4_w1(P.AWUSER_W),
    localparam int unsigned WUW_ = axi4_w1(P.WUSER_W),
    localparam int unsigned BUW_ = axi4_w1(P.BUSER_W),
    localparam int unsigned RAW_ = axi4_w1(P.ARUSER_W),
    localparam int unsigned RUW_ = axi4_w1(P.RUSER_W)
) (
    input  logic aclk, aresetn
);
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

    axi4_mgr_xtor #(.P(P)) u_mgr (.*);
    axi4_sub_xtor #(.P(P)) u_sub (.*);
    axi4_mon_xtor #(.P(P)) u_mon (.*);
endmodule
