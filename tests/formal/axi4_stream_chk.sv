// axi4_checker on a core's user side: the five packed channel streams
// (axi4_types_pkg layout) unpacked onto checker pins. ASSUME_MGR /
// ASSUME_SUB as in axi4_checker.
module axi4_stream_chk
    import axi4_types_pkg::*;
#(
    parameter axi4_param_t P          = AXI4_PARAM_DEFAULT,
    parameter int unsigned MAX_OUT    = 8,
    parameter bit          ASSUME_MGR = 1'b0,
    parameter bit          ASSUME_SUB = 1'b0,
    localparam int unsigned AW_  = P.ADDR_W,
    localparam int unsigned DW_  = P.DATA_W,
    localparam int unsigned IW_  = axi4_w1(P.ID_W),
    localparam int unsigned AUW_ = axi4_w1(P.AWUSER_W),
    localparam int unsigned WUW_ = axi4_w1(P.WUSER_W),
    localparam int unsigned BUW_ = axi4_w1(P.BUSER_W),
    localparam int unsigned RAW_ = axi4_w1(P.ARUSER_W),
    localparam int unsigned RUW_ = axi4_w1(P.RUSER_W),
    localparam int unsigned AWB_ = axi4_ax_bits(P, 1'b0),
    localparam int unsigned WB_  = axi4_wd_bits(P),
    localparam int unsigned BB_  = axi4_b_bits(P),
    localparam int unsigned ARB_ = axi4_ax_bits(P, 1'b1),
    localparam int unsigned RB_  = axi4_r_bits(P)
) (
    input logic            aclk,
    input logic            aresetn,
    input logic            aw_valid, aw_ready,
    input logic [AWB_-1:0] aw_data,
    input logic            w_valid, w_ready,
    input logic [WB_-1:0]  w_data,
    input logic            b_valid, b_ready,
    input logic [BB_-1:0]  b_data,
    input logic            ar_valid, ar_ready,
    input logic [ARB_-1:0] ar_data,
    input logic            r_valid, r_ready,
    input logic [RB_-1:0]  r_data
);
    logic awlock, wlast, arlock, rlast;
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

    assign {awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
            awqos, awregion, awuser} = aw_data;
    assign {wdata, wstrb, wlast, wuser} = w_data;
    assign {bid, bresp, buser} = b_data;
    assign {arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
            arqos, arregion, aruser} = ar_data;
    assign {rid, rdata, rresp, rlast, ruser} = r_data;

    axi4_checker #(.P(P), .MAX_OUT(MAX_OUT), .ASSUME_MGR(ASSUME_MGR),
                   .ASSUME_SUB(ASSUME_SUB)) u_checker (
        .aclk, .aresetn,
        .awvalid(aw_valid), .awready(aw_ready), .awid, .awaddr, .awlen,
        .awsize, .awburst, .awlock, .awcache, .awprot, .awqos, .awregion,
        .awuser,
        .wvalid(w_valid), .wready(w_ready), .wdata, .wstrb, .wlast, .wuser,
        .bvalid(b_valid), .bready(b_ready), .bid, .bresp, .buser,
        .arvalid(ar_valid), .arready(ar_ready), .arid, .araddr, .arlen,
        .arsize, .arburst, .arlock, .arcache, .arprot, .arqos, .arregion,
        .aruser,
        .rvalid(r_valid), .rready(r_ready), .rid, .rdata, .rresp, .rlast,
        .ruser);
endmodule
