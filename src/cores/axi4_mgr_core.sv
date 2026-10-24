// AXI4 manager (initiator) channel core. IHI0022H A2, A3.2.
// Synthesizable.
//
// User side: five packed valid/ready streams in axi4_types_pkg's channel
// layout -- AW, W, AR requests in; B, R responses out. Pin side: the AXI4
// manager pins (the checker's names, so both connect with `.*`). One
// axi4_slice per channel, so the pins are registered and VALID/payload
// stable while stalled. No ordering logic: the user side must already obey
// the protocol (burst legality, WLAST, ...); the core only times it.
module axi4_mgr_core
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
    localparam int unsigned RUW_ = axi4_w1(P.RUSER_W),
    localparam int unsigned AWB_ = axi4_ax_bits(P, 1'b0),
    localparam int unsigned WB_  = axi4_wd_bits(P),
    localparam int unsigned BB_  = axi4_b_bits(P),
    localparam int unsigned ARB_ = axi4_ax_bits(P, 1'b1),
    localparam int unsigned RB_  = axi4_r_bits(P)
) (
    input  logic             aclk,
    input  logic             aresetn,

    // User side.
    input  logic             aw_valid,
    output logic             aw_ready,
    input  logic [AWB_-1:0]  aw_data,
    input  logic             w_valid,
    output logic             w_ready,
    input  logic [WB_-1:0]   w_data,
    output logic             b_valid,
    input  logic             b_ready,
    output logic [BB_-1:0]   b_data,
    input  logic             ar_valid,
    output logic             ar_ready,
    input  logic [ARB_-1:0]  ar_data,
    output logic             r_valid,
    input  logic             r_ready,
    output logic [RB_-1:0]   r_data,

    // AXI4 manager pins.
    output logic             awvalid,
    input  logic             awready,
    output logic [IW_-1:0]   awid,
    output logic [AW_-1:0]   awaddr,
    output logic [7:0]       awlen,
    output logic [2:0]       awsize,
    output logic [1:0]       awburst,
    output logic             awlock,
    output logic [3:0]       awcache,
    output logic [2:0]       awprot,
    output logic [3:0]       awqos,
    output logic [3:0]       awregion,
    output logic [AUW_-1:0]  awuser,

    output logic             wvalid,
    input  logic             wready,
    output logic [DW_-1:0]   wdata,
    output logic [DW_/8-1:0] wstrb,
    output logic             wlast,
    output logic [WUW_-1:0]  wuser,

    input  logic             bvalid,
    output logic             bready,
    input  logic [IW_-1:0]   bid,
    input  logic [1:0]       bresp,
    input  logic [BUW_-1:0]  buser,

    output logic             arvalid,
    input  logic             arready,
    output logic [IW_-1:0]   arid,
    output logic [AW_-1:0]   araddr,
    output logic [7:0]       arlen,
    output logic [2:0]       arsize,
    output logic [1:0]       arburst,
    output logic             arlock,
    output logic [3:0]       arcache,
    output logic [2:0]       arprot,
    output logic [3:0]       arqos,
    output logic [3:0]       arregion,
    output logic [RAW_-1:0]  aruser,

    input  logic             rvalid,
    output logic             rready,
    input  logic [IW_-1:0]   rid,
    input  logic [DW_-1:0]   rdata,
    input  logic [1:0]       rresp,
    input  logic             rlast,
    input  logic [RUW_-1:0]  ruser
);
    axi4_slice #(.W(AWB_)) u_aw (
        .aclk, .aresetn,
        .in_valid(aw_valid), .in_ready(aw_ready), .in_data(aw_data),
        .out_valid(awvalid), .out_ready(awready),
        .out_data({awid, awaddr, awlen, awsize, awburst, awlock, awcache,
                   awprot, awqos, awregion, awuser}));

    axi4_slice #(.W(WB_)) u_w (
        .aclk, .aresetn,
        .in_valid(w_valid), .in_ready(w_ready), .in_data(w_data),
        .out_valid(wvalid), .out_ready(wready),
        .out_data({wdata, wstrb, wlast, wuser}));

    axi4_slice #(.W(BB_)) u_b (
        .aclk, .aresetn,
        .in_valid(bvalid), .in_ready(bready), .in_data({bid, bresp, buser}),
        .out_valid(b_valid), .out_ready(b_ready), .out_data(b_data));

    axi4_slice #(.W(ARB_)) u_ar (
        .aclk, .aresetn,
        .in_valid(ar_valid), .in_ready(ar_ready), .in_data(ar_data),
        .out_valid(arvalid), .out_ready(arready),
        .out_data({arid, araddr, arlen, arsize, arburst, arlock, arcache,
                   arprot, arqos, arregion, aruser}));

    axi4_slice #(.W(RB_)) u_r (
        .aclk, .aresetn,
        .in_valid(rvalid), .in_ready(rready),
        .in_data({rid, rdata, rresp, rlast, ruser}),
        .out_valid(r_valid), .out_ready(r_ready), .out_data(r_data));
endmodule
