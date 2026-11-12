// One parameter set of the RTL lint top (axi4_lint_rtl): the pin checker on
// every AXI4 pin, and an axi4_slice carrying the AW stream. The pins come from
// a shift register fed by `din`, so every input is driven and Verilator's
// elaboration-time checks (width, latch, unused, undriven) see real logic; the
// slice's outputs fold into `dout`.
module axi4_lint_rtl_p
    import fw_proto_axi4_defs_pkg::*;
#(
    parameter axi4_param_t P = AXI4_PARAM_DEFAULT
) (
    input  logic aclk,
    input  logic aresetn,
    input  logic din,
    output logic dout
);
    localparam int unsigned AXW = axi4_ax_bits(P, 1'b0);
    localparam int unsigned ARW = axi4_ax_bits(P, 1'b1);
    localparam int unsigned WDW = axi4_wd_bits(P);
    localparam int unsigned BW  = axi4_b_bits(P);
    localparam int unsigned RW  = axi4_r_bits(P);
    // Each channel: its stream (the pins in order) plus valid and ready.
    localparam int unsigned PW  = AXW + WDW + BW + ARW + RW + 10;

    localparam int unsigned AW_  = P.ADDR_W;
    localparam int unsigned DW_  = P.DATA_W;
    localparam int unsigned IW_  = w1(P.ID_W);
    localparam int unsigned AUW_ = w1(P.AWUSER_W);
    localparam int unsigned WUW_ = w1(P.WUSER_W);
    localparam int unsigned BUW_ = w1(P.BUSER_W);
    localparam int unsigned RAW_ = w1(P.ARUSER_W);
    localparam int unsigned RUW_ = w1(P.RUSER_W);

    logic [PW-1:0] pins;
    always_ff @(posedge aclk) pins <= {pins[PW-2:0], din};

    logic             awvalid, awready, awlock;
    logic [IW_-1:0]   awid;
    logic [AW_-1:0]   awaddr;
    logic [7:0]       awlen;
    logic [2:0]       awsize, awprot;
    logic [1:0]       awburst;
    logic [3:0]       awcache, awqos, awregion;
    logic [AUW_-1:0]  awuser;
    logic             wvalid, wready, wlast;
    logic [DW_-1:0]   wdata;
    logic [DW_/8-1:0] wstrb;
    logic [WUW_-1:0]  wuser;
    logic             bvalid, bready;
    logic [IW_-1:0]   bid;
    logic [1:0]       bresp;
    logic [BUW_-1:0]  buser;
    logic             arvalid, arready, arlock;
    logic [IW_-1:0]   arid;
    logic [AW_-1:0]   araddr;
    logic [7:0]       arlen;
    logic [2:0]       arsize, arprot;
    logic [1:0]       arburst;
    logic [3:0]       arcache, arqos, arregion;
    logic [RAW_-1:0]  aruser;
    logic             rvalid, rready, rlast;
    logic [IW_-1:0]   rid;
    logic [DW_-1:0]   rdata;
    logic [1:0]       rresp;
    logic [RUW_-1:0]  ruser;

    assign {awvalid, awready,
            awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser,
            wvalid, wready, wdata, wstrb, wlast, wuser,
            bvalid, bready, bid, bresp, buser,
            arvalid, arready,
            arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser,
            rvalid, rready, rid, rdata, rresp, rlast, ruser} = pins;

    axi4_checker #(.P(P)) u_checker (.*);

    logic           s_in_ready, s_out_valid;
    logic [AXW-1:0] s_out_data;

    axi4_slice #(.W(AXW)) u_slice (
        .aclk, .aresetn,
        .in_valid(awvalid), .in_ready(s_in_ready),
        .in_data({awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos,
                  awregion, awuser}),
        .out_valid(s_out_valid), .out_ready(awready), .out_data(s_out_data));

    assign dout = ^{s_in_ready, s_out_valid, s_out_data};
endmodule
