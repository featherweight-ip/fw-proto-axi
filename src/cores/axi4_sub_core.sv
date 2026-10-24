// AXI4 subordinate (target) channel core: the mirror of axi4_mgr_core.
// IHI0022H A2, A3.2. Synthesizable.
//
// Pin side: the AXI4 subordinate pins (the checker's names, `.*`). User
// side: five packed valid/ready streams in axi4_types_pkg's channel layout
// -- AW, W, AR requests out; B, R responses in. One axi4_slice per channel.
// No ordering logic: the user side must answer by the protocol (B after the
// write, RLAST, IDs); the core only times it.
module axi4_sub_core
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
    output logic             aw_valid,
    input  logic             aw_ready,
    output logic [AWB_-1:0]  aw_data,
    output logic             w_valid,
    input  logic             w_ready,
    output logic [WB_-1:0]   w_data,
    input  logic             b_valid,
    output logic             b_ready,
    input  logic [BB_-1:0]   b_data,
    output logic             ar_valid,
    input  logic             ar_ready,
    output logic [ARB_-1:0]  ar_data,
    input  logic             r_valid,
    output logic             r_ready,
    input  logic [RB_-1:0]   r_data,

    // AXI4 subordinate pins.
    input  logic             awvalid,
    output logic             awready,
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
    output logic             wready,
    input  logic [DW_-1:0]   wdata,
    input  logic [DW_/8-1:0] wstrb,
    input  logic             wlast,
    input  logic [WUW_-1:0]  wuser,

    output logic             bvalid,
    input  logic             bready,
    output logic [IW_-1:0]   bid,
    output logic [1:0]       bresp,
    output logic [BUW_-1:0]  buser,

    input  logic             arvalid,
    output logic             arready,
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

    output logic             rvalid,
    input  logic             rready,
    output logic [IW_-1:0]   rid,
    output logic [DW_-1:0]   rdata,
    output logic [1:0]       rresp,
    output logic             rlast,
    output logic [RUW_-1:0]  ruser
);
    axi4_slice #(.W(AWB_)) u_aw (
        .aclk, .aresetn,
        .in_valid(awvalid), .in_ready(awready),
        .in_data({awid, awaddr, awlen, awsize, awburst, awlock, awcache,
                  awprot, awqos, awregion, awuser}),
        .out_valid(aw_valid), .out_ready(aw_ready), .out_data(aw_data));

    axi4_slice #(.W(WB_)) u_w (
        .aclk, .aresetn,
        .in_valid(wvalid), .in_ready(wready), .in_data({wdata, wstrb, wlast, wuser}),
        .out_valid(w_valid), .out_ready(w_ready), .out_data(w_data));

    axi4_slice #(.W(BB_)) u_b (
        .aclk, .aresetn,
        .in_valid(b_valid), .in_ready(b_ready), .in_data(b_data),
        .out_valid(bvalid), .out_ready(bready), .out_data({bid, bresp, buser}));

    axi4_slice #(.W(ARB_)) u_ar (
        .aclk, .aresetn,
        .in_valid(arvalid), .in_ready(arready),
        .in_data({arid, araddr, arlen, arsize, arburst, arlock, arcache,
                  arprot, arqos, arregion, aruser}),
        .out_valid(ar_valid), .out_ready(ar_ready), .out_data(ar_data));

    axi4_slice #(.W(RB_)) u_r (
        .aclk, .aresetn,
        .in_valid(r_valid), .in_ready(r_ready), .in_data(r_data),
        .out_valid(rvalid), .out_ready(rready),
        .out_data({rid, rdata, rresp, rlast, ruser}));
endmodule
