// Back-to-back formal harness: axi4_mgr_core -> AXI4 pins -> axi4_sub_core.
// The manager core's user side and the subordinate core's user side are
// free inputs. Three checkers:
//   u_chk_m  manager user side: manager rules ASSUMED (legal requests in),
//            subordinate rules asserted (responses out are legal);
//   u_chk_p  the pins: every rule asserted;
//   u_chk_s  subordinate user side: subordinate rules ASSUMED (legal
//            responses in), manager rules asserted (requests out are legal).
// A single reset at the start. `dfm run fv` (BMC).
//
// Checker capacity grows downstream: each core's AW slice holds up to 2
// addresses while W data flows past, so the pins can see 2 more write-data
// bursts ahead of their AW than the manager user side, and the subordinate
// user side 2 more again.
module axi4_fv
    import axi4_types_pkg::*;
#(
    localparam axi4_param_t P = '{ADDR_W: 16, DATA_W: 32, ID_W: 1,
        AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0},
    localparam int unsigned MAX_OUT = 2,
    localparam int unsigned AWB_ = axi4_ax_bits(P, 1'b0),
    localparam int unsigned WB_  = axi4_wd_bits(P),
    localparam int unsigned BB_  = axi4_b_bits(P),
    localparam int unsigned ARB_ = axi4_ax_bits(P, 1'b1),
    localparam int unsigned RB_  = axi4_r_bits(P)
) (
    input logic            aclk,
    input logic            aresetn,
    // Manager core user side (requests in, response readies).
    input logic            m_aw_valid, m_w_valid, m_b_ready, m_ar_valid, m_r_ready,
    input logic [AWB_-1:0] m_aw_data,
    input logic [WB_-1:0]  m_w_data,
    input logic [ARB_-1:0] m_ar_data,
    // Subordinate core user side (request readies, responses in).
    input logic            s_aw_ready, s_w_ready, s_b_valid, s_ar_ready, s_r_valid,
    input logic [BB_-1:0]  s_b_data,
    input logic [RB_-1:0]  s_r_data
);
    logic init = 1'b1;
    always_ff @(posedge aclk) init <= 1'b0;
    always_comb if (init) assume (!aresetn);
    always_comb if (!init) assume (aresetn);

    // Core outputs on the user sides.
    logic            m_aw_ready, m_w_ready, m_b_valid, m_ar_ready, m_r_valid;
    logic [BB_-1:0]  m_b_data;
    logic [RB_-1:0]  m_r_data;
    logic            s_aw_valid, s_w_valid, s_b_ready, s_ar_valid, s_r_ready;
    logic [AWB_-1:0] s_aw_data;
    logic [WB_-1:0]  s_w_data;
    logic [ARB_-1:0] s_ar_data;

    // The pins.
    logic awvalid, awready, awlock, wvalid, wready, wlast;
    logic bvalid, bready, arvalid, arready, arlock, rvalid, rready, rlast;
    logic [0:0]  awid, bid, arid, rid;
    logic [15:0] awaddr, araddr;
    logic [7:0]  awlen, arlen;
    logic [3:0]  wstrb;
    logic [2:0]  awsize, arsize, awprot, arprot;
    logic [1:0]  awburst, arburst, bresp, rresp;
    logic [3:0]  awcache, arcache, awqos, arqos, awregion, arregion;
    logic        awuser, wuser, buser, aruser, ruser;
    logic [31:0] wdata, rdata;

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

    axi4_stream_chk #(.P(P), .MAX_OUT(MAX_OUT), .ASSUME_MGR(1'b1)) u_chk_m (
        .aclk, .aresetn,
        .aw_valid(m_aw_valid), .aw_ready(m_aw_ready), .aw_data(m_aw_data),
        .w_valid(m_w_valid),   .w_ready(m_w_ready),   .w_data(m_w_data),
        .b_valid(m_b_valid),   .b_ready(m_b_ready),   .b_data(m_b_data),
        .ar_valid(m_ar_valid), .ar_ready(m_ar_ready), .ar_data(m_ar_data),
        .r_valid(m_r_valid),   .r_ready(m_r_ready),   .r_data(m_r_data));

    axi4_checker #(.P(P), .MAX_OUT(MAX_OUT + 2)) u_chk_p (.*);

    axi4_stream_chk #(.P(P), .MAX_OUT(MAX_OUT + 4), .ASSUME_SUB(1'b1)) u_chk_s (
        .aclk, .aresetn,
        .aw_valid(s_aw_valid), .aw_ready(s_aw_ready), .aw_data(s_aw_data),
        .w_valid(s_w_valid),   .w_ready(s_w_ready),   .w_data(s_w_data),
        .b_valid(s_b_valid),   .b_ready(s_b_ready),   .b_data(s_b_data),
        .ar_valid(s_ar_valid), .ar_ready(s_ar_ready), .ar_data(s_ar_data),
        .r_valid(s_r_valid),   .r_ready(s_r_ready),   .r_data(s_r_data));
endmodule
