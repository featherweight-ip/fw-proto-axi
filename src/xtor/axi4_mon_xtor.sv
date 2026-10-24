// Passive pin-level monitor for one AXI4 link. At every rising edge out of
// reset it queues each channel's beat whose VALID and READY are both high,
// packed in the stream layout of axi4_mgr_core/axi4_sub_core and stamped
// with the time, in its axi4_mon_xtor_if. axi4_mon_xtor_bridge drains the
// queue and publishes through axi4_mon_if. Ties nothing, drives nothing:
// every port is an input, named as on axi4_checker, so `.*` hooks it up.
module axi4_mon_xtor
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
    input  logic             aclk,
    input  logic             aresetn,

    input  logic             awvalid,
    input  logic             awready,
    input  logic [IW_-1:0]   awid,
    input  logic [AW_-1:0]   awaddr,
    input  logic [7:0]       awlen,
    input  logic [2:0]       awsize,
    input  logic [1:0]       awburst,
    input  logic             awlock,
    input  logic [3:0]       awcache,
    input  logic [2:0]       awprot,
    input  logic [3:0]       awqos,
    input  logic [3:0]       awregion,
    input  logic [AUW_-1:0]  awuser,

    input  logic             wvalid,
    input  logic             wready,
    input  logic [DW_-1:0]   wdata,
    input  logic [DW_/8-1:0] wstrb,
    input  logic             wlast,
    input  logic [WUW_-1:0]  wuser,

    input  logic             bvalid,
    input  logic             bready,
    input  logic [IW_-1:0]   bid,
    input  logic [1:0]       bresp,
    input  logic [BUW_-1:0]  buser,

    input  logic             arvalid,
    input  logic             arready,
    input  logic [IW_-1:0]   arid,
    input  logic [AW_-1:0]   araddr,
    input  logic [7:0]       arlen,
    input  logic [2:0]       arsize,
    input  logic [1:0]       arburst,
    input  logic             arlock,
    input  logic [3:0]       arcache,
    input  logic [2:0]       arprot,
    input  logic [3:0]       arqos,
    input  logic [3:0]       arregion,
    input  logic [RAW_-1:0]  aruser,

    input  logic             rvalid,
    input  logic             rready,
    input  logic [IW_-1:0]   rid,
    input  logic [DW_-1:0]   rdata,
    input  logic [1:0]       rresp,
    input  logic             rlast,
    input  logic [RUW_-1:0]  ruser
);
    axi4_mon_xtor_if u_if (.aclk, .aresetn);

    initial u_if.p = P;

    always @(posedge aclk) begin
        if (aresetn) begin
            if (awvalid && awready)
                u_if.push(AXI4_CH_AW, AXI4_STREAM_W_MAX'({awid, awaddr, awlen, awsize, awburst,
                    awlock, awcache, awprot, awqos, awregion, awuser}));
            if (wvalid && wready)
                u_if.push(AXI4_CH_W, AXI4_STREAM_W_MAX'({wdata, wstrb, wlast, wuser}));
            if (bvalid && bready)
                u_if.push(AXI4_CH_B, AXI4_STREAM_W_MAX'({bid, bresp, buser}));
            if (arvalid && arready)
                u_if.push(AXI4_CH_AR, AXI4_STREAM_W_MAX'({arid, araddr, arlen, arsize, arburst,
                    arlock, arcache, arprot, arqos, arregion, aruser}));
            if (rvalid && rready)
                u_if.push(AXI4_CH_R, AXI4_STREAM_W_MAX'({rid, rdata, rresp, rlast, ruser}));
        end
    end
endmodule
