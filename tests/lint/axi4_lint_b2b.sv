// Lint elaboration: axi4_mgr_core -> axi4_sub_core on internal pins.
module axi4_lint_b2b
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
    input  logic aclk, aresetn,
    input  logic m_aw_valid, m_w_valid, m_b_ready, m_ar_valid, m_r_ready,
    output logic m_aw_ready, m_w_ready, m_b_valid, m_ar_ready, m_r_valid,
    input  logic [AWB_-1:0] m_aw_data,
    input  logic [WB_-1:0]  m_w_data,
    output logic [BB_-1:0]  m_b_data,
    input  logic [ARB_-1:0] m_ar_data,
    output logic [RB_-1:0]  m_r_data,
    output logic s_aw_valid, s_w_valid, s_b_ready, s_ar_valid, s_r_ready,
    input  logic s_aw_ready, s_w_ready, s_b_valid, s_ar_ready, s_r_valid,
    output logic [AWB_-1:0] s_aw_data,
    output logic [WB_-1:0]  s_w_data,
    input  logic [BB_-1:0]  s_b_data,
    output logic [ARB_-1:0] s_ar_data,
    input  logic [RB_-1:0]  s_r_data
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

    axi4_mgr_core #(.P(P)) u_mgr (
        .aw_valid(m_aw_valid), .aw_ready(m_aw_ready), .aw_data(m_aw_data),
        .w_valid(m_w_valid),   .w_ready(m_w_ready),   .w_data(m_w_data),
        .b_valid(m_b_valid),   .b_ready(m_b_ready),   .b_data(m_b_data),
        .ar_valid(m_ar_valid), .ar_ready(m_ar_ready), .ar_data(m_ar_data),
        .r_valid(m_r_valid),   .r_ready(m_r_ready),   .r_data(m_r_data),
        .*);

    axi4_sub_core #(.P(P)) u_sub (
        .aw_valid(s_aw_valid), .aw_ready(s_aw_ready), .aw_data(s_aw_data),
        .w_valid(s_w_valid),   .w_ready(s_w_ready),   .w_data(s_w_data),
        .b_valid(s_b_valid),   .b_ready(s_b_ready),   .b_data(s_b_data),
        .ar_valid(s_ar_valid), .ar_ready(s_ar_ready), .ar_data(s_ar_data),
        .r_valid(s_r_valid),   .r_ready(s_r_ready),   .r_data(s_r_data),
        .*);
endmodule
