// Signal-level AXI4 subordinate transactor: axi4_sub_core with its user
// streams on an axi4_xtor_if. TX: B, R; RX: AW, W, AR. The pins (checker
// names) face a manager. The class side is u_if, bound with
// `fw_root_bind_mirror and axi4_sub_xtor_bridge.
module axi4_sub_xtor
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
    axi4_xtor_if u_if (.aclk, .aresetn);

    initial u_if.p = P;

    // Streams out of the core, widened to the interface's beat width.
    logic [AWB_-1:0] aw_data;
    logic [WB_-1:0] w_data;
    logic [ARB_-1:0] ar_data;
    assign u_if.rx_data[AXI4_CH_AW] = AXI4_STREAM_W_MAX'(aw_data);
    assign u_if.rx_data[AXI4_CH_W] = AXI4_STREAM_W_MAX'(w_data);
    assign u_if.rx_data[AXI4_CH_AR] = AXI4_STREAM_W_MAX'(ar_data);

    // The other direction of each channel is unused: tie it off.
    assign u_if.tx_ready[AXI4_CH_AW] = 1'b0;
    assign u_if.tx_ready[AXI4_CH_W] = 1'b0;
    assign u_if.tx_ready[AXI4_CH_AR] = 1'b0;
    assign u_if.rx_valid[AXI4_CH_B] = 1'b0;
    assign u_if.rx_data[AXI4_CH_B]  = '0;
    assign u_if.rx_valid[AXI4_CH_R] = 1'b0;
    assign u_if.rx_data[AXI4_CH_R]  = '0;

    axi4_sub_core #(.P(P)) u_core (
        .b_valid(u_if.tx_valid[AXI4_CH_B]), .b_ready(u_if.tx_ready[AXI4_CH_B]),
        .b_data(u_if.tx_data[AXI4_CH_B][BB_-1:0]),
        .r_valid(u_if.tx_valid[AXI4_CH_R]), .r_ready(u_if.tx_ready[AXI4_CH_R]),
        .r_data(u_if.tx_data[AXI4_CH_R][RB_-1:0]),
        .aw_valid(u_if.rx_valid[AXI4_CH_AW]), .aw_ready(u_if.rx_ready[AXI4_CH_AW]),
        .aw_data,
        .w_valid(u_if.rx_valid[AXI4_CH_W]), .w_ready(u_if.rx_ready[AXI4_CH_W]),
        .w_data,
        .ar_valid(u_if.rx_valid[AXI4_CH_AR]), .ar_ready(u_if.rx_ready[AXI4_CH_AR]),
        .ar_data,
        .*);
endmodule
