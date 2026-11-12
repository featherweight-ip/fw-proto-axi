// Back-to-back formal harness for the generated transactors' cores (plan P4.3):
// axi4_mgr_xtor_core -> AXI4 pins -> axi4_sub_xtor_core, the synthesizable part of
// the generated axi4_{mgr,sub}_xtor (fw-hdl rv cores, payloads spliced onto the
// pins). The cores' class-side links are free inputs, with three checkers:
//   u_chk_m  manager link: manager rules ASSUMED (legal requests in),
//            subordinate rules asserted (responses out are legal);
//   u_chk_p  the pins: every rule asserted;
//   u_chk_s  subordinate link: subordinate rules ASSUMED (legal responses in),
//            manager rules asserted (requests out are legal).
// The links carry the payload structs' packing, which is the defs package's
// stream layout, so axi4_stream_chk reads them; the widths are cross-checked at
// elaboration. A single reset at the start. `dfm run fv` (BMC); with FV_COVER,
// the covers at the end (`dfm run fv-cover`).
module axi4_fv
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_defs_pkg_woven::*;
#(
    localparam axi4_param_t P = '{ADDR_W: 12, DATA_W: 8, ID_W: 1,
        AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
        HAS_QOS: 1, HAS_REGION: 1},
    localparam int unsigned MAX_OUT = 2,
    localparam int unsigned AWB_ = axi4_aw_t_bits(P),
    localparam int unsigned WB_  = axi4_w_t_bits(P),
    localparam int unsigned BB_  = axi4_b_t_bits(P),
    localparam int unsigned ARB_ = axi4_ar_t_bits(P),
    localparam int unsigned RB_  = axi4_r_t_bits(P)
) (
    input logic            aclk,
    input logic            aresetn,
    // Manager core link (requests in, response readies).
    input logic            m_aw_valid, m_w_valid, m_b_ready, m_ar_valid, m_r_ready,
    input logic [AWB_-1:0] m_aw_data,
    input logic [WB_-1:0]  m_w_data,
    input logic [ARB_-1:0] m_ar_data,
    // Subordinate core link (request readies, responses in).
    input logic            s_aw_ready, s_w_ready, s_b_valid, s_ar_ready, s_r_valid,
    input logic [BB_-1:0]  s_b_data,
    input logic [RB_-1:0]  s_r_data
);
    // The generated widths must be the stream layout's (elaboration error if not).
    if (AWB_ != axi4_ax_bits(P, 1'b0) || WB_ != axi4_wd_bits(P) || BB_ != axi4_b_bits(P)
            || ARB_ != axi4_ax_bits(P, 1'b1) || RB_ != axi4_r_bits(P)) begin : g_layout
        width_mismatch_with_stream_layout u_err ();
    end

    logic init = 1'b1;
    always_ff @(posedge aclk) init <= 1'b0;
    always_comb if (init) assume (!aresetn);
    always_comb if (!init) assume (aresetn);

    // Core outputs on the links.
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
    logic [P.ADDR_W-1:0] awaddr, araddr;
    logic [7:0]  awlen, arlen;
    logic [P.DATA_W/8-1:0] wstrb;
    logic [2:0]  awsize, arsize, awprot, arprot;
    logic [1:0]  awburst, arburst, bresp, rresp;
    logic [3:0]  awcache, arcache, awqos, arqos, awregion, arregion;
    logic        awuser, wuser, buser, aruser, ruser;
    logic [P.DATA_W-1:0] wdata, rdata;

    axi4_mgr_xtor_core #(P) u_mgr (
        .aw_up_valid(m_aw_valid), .aw_up_ready(m_aw_ready), .aw_up_data(m_aw_data),
        .w_up_valid(m_w_valid),   .w_up_ready(m_w_ready),   .w_up_data(m_w_data),
        .b_up_valid(m_b_valid),   .b_up_ready(m_b_ready),   .b_up_data(m_b_data),
        .ar_up_valid(m_ar_valid), .ar_up_ready(m_ar_ready), .ar_up_data(m_ar_data),
        .r_up_valid(m_r_valid),   .r_up_ready(m_r_ready),   .r_up_data(m_r_data),
        .*);

    axi4_sub_xtor_core #(P) u_sub (
        .aw_up_valid(s_aw_valid), .aw_up_ready(s_aw_ready), .aw_up_data(s_aw_data),
        .w_up_valid(s_w_valid),   .w_up_ready(s_w_ready),   .w_up_data(s_w_data),
        .b_up_valid(s_b_valid),   .b_up_ready(s_b_ready),   .b_up_data(s_b_data),
        .ar_up_valid(s_ar_valid), .ar_up_ready(s_ar_ready), .ar_up_data(s_ar_data),
        .r_up_valid(s_r_valid),   .r_up_ready(s_r_ready),   .r_up_data(s_r_data),
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
`ifdef FV_COVER
    // Reachability (`dfm run fv-cover`): the assumptions leave the
    // interesting traffic possible, so the BMC is not vacuous.
    logic wr_long, rd_long, ar0, ar1_after0, r_seen;
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            wr_long <= 1'b0; rd_long <= 1'b0;
            ar0 <= 1'b0; ar1_after0 <= 1'b0; r_seen <= 1'b0;
        end else begin
            if (awvalid && awready && awlen != 8'd0) wr_long <= 1'b1;
            if (arvalid && arready && arlen != 8'd0) rd_long <= 1'b1;
            if (arvalid && arready && arid == 1'b0) ar0 <= 1'b1;
            if (arvalid && arready && arid == 1'b1 && ar0) ar1_after0 <= 1'b1;
            if (rvalid && rready) r_seen <= 1'b1;
        end
    end

    // r_data = {id, data, resp, last, user}: bit 1 is RLAST.
    always_comb if (!init && aresetn) begin
        // A burst write (len > 0) completes with B at the manager link.
        c_wr_burst: cover (wr_long && m_b_valid && m_b_ready);
        // A burst read ends with RLAST at the manager link.
        c_rd_burst: cover (rd_long && m_r_valid && m_r_ready && m_r_data[1]);
        // Out of order across IDs: the first R returned is for the later AR.
        c_rd_reorder: cover (ar1_after0 && !r_seen && rvalid && rready && rid == 1'b1);
        // Backpressure through both cores: a pin channel held, a link refused.
        c_pin_aw_held: cover (awvalid && !awready);
        c_mgr_w_busy: cover (m_w_valid && !m_w_ready);
        c_sub_r_busy: cover (s_r_valid && !s_r_ready);
    end
`endif
endmodule
