// Signal-level AXI4 manager transactor: axi4_mgr_core with its user streams
// on an axi4_xtor_if. TX: AW, W, AR; RX: B, R. The pins (checker names) face
// a subordinate. The class side is u_if, bound with `fw_root_bind_socket and
// axi4_mgr_xtor_bridge; beats cross u_if in the packed stream layout.
module axi4_mgr_xtor
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
    axi4_xtor_if u_if (.aclk, .aresetn);

    initial u_if.p = P;

    // Streams out of the core, widened to the interface's beat width.
    logic [BB_-1:0] b_data;
    logic [RB_-1:0] r_data;
    assign u_if.rx_data[AXI4_CH_B] = AXI4_STREAM_W_MAX'(b_data);
    assign u_if.rx_data[AXI4_CH_R] = AXI4_STREAM_W_MAX'(r_data);

    // The other direction of each channel is unused: tie it off.
    assign u_if.tx_ready[AXI4_CH_B] = 1'b0;
    assign u_if.tx_ready[AXI4_CH_R] = 1'b0;
    assign u_if.rx_valid[AXI4_CH_AW] = 1'b0;
    assign u_if.rx_data[AXI4_CH_AW]  = '0;
    assign u_if.rx_valid[AXI4_CH_W] = 1'b0;
    assign u_if.rx_data[AXI4_CH_W]  = '0;
    assign u_if.rx_valid[AXI4_CH_AR] = 1'b0;
    assign u_if.rx_data[AXI4_CH_AR]  = '0;

    axi4_mgr_core #(.P(P)) u_core (
        .aw_valid(u_if.tx_valid[AXI4_CH_AW]), .aw_ready(u_if.tx_ready[AXI4_CH_AW]),
        .aw_data(u_if.tx_data[AXI4_CH_AW][AWB_-1:0]),
        .w_valid(u_if.tx_valid[AXI4_CH_W]), .w_ready(u_if.tx_ready[AXI4_CH_W]),
        .w_data(u_if.tx_data[AXI4_CH_W][WB_-1:0]),
        .ar_valid(u_if.tx_valid[AXI4_CH_AR]), .ar_ready(u_if.tx_ready[AXI4_CH_AR]),
        .ar_data(u_if.tx_data[AXI4_CH_AR][ARB_-1:0]),
        .b_valid(u_if.rx_valid[AXI4_CH_B]), .b_ready(u_if.rx_ready[AXI4_CH_B]),
        .b_data,
        .r_valid(u_if.rx_valid[AXI4_CH_R]), .r_ready(u_if.rx_ready[AXI4_CH_R]),
        .r_data,
        .*);
endmodule
