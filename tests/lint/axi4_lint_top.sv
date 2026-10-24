// Lint elaboration top: every synthesizable unit of the kit, at the default
// interface configuration, so Verilator's elaboration-time checks (width,
// latch, unused, undriven) see all of it. For now: the types package, through
// its burst helpers; the pin checker on free inputs; the manager and
// subordinate cores back to back (axi4_lint_b2b); the manager and
// subordinate transactors back to back (axi4_lint_xtor).
module axi4_lint_top
    import axi4_types_pkg::*;
(
    input  axi4_addr_beat_t ax,
    input  logic [7:0]      n,
    output axi4_addr_t      beat_addr,
    output logic [7:0]      lower_lane,
    output logic [7:0]      upper_lane,
    output logic            legal,
    // Checker pins, at the default configuration (USER absent: 1 bit).
    input  logic aclk, aresetn,
    input  logic awvalid, awready, awlock, wvalid, wready, wlast,
    input  logic bvalid, bready, arvalid, arready, arlock, rvalid, rready, rlast,
    input  logic [3:0]  awid, bid, arid, rid,
    input  logic [31:0] awaddr, araddr,
    input  logic [7:0]  awlen, arlen, wstrb,
    input  logic [2:0]  awsize, arsize, awprot, arprot,
    input  logic [1:0]  awburst, arburst, bresp, rresp,
    input  logic [3:0]  awcache, arcache, awqos, arqos, awregion, arregion,
    input  logic        awuser, wuser, buser, aruser, ruser,
    input  logic [63:0] wdata, rdata,
    // Back-to-back cores: manager user side (m_*), subordinate user side (s_*).
    input  logic m_aw_valid, m_w_valid, m_b_ready, m_ar_valid, m_r_ready,
    output logic m_aw_ready, m_w_ready, m_b_valid, m_ar_ready, m_r_valid,
    input  logic [axi4_ax_bits(AXI4_PARAM_DEFAULT, 1'b0)-1:0] m_aw_data,
    input  logic [axi4_wd_bits(AXI4_PARAM_DEFAULT)-1:0]       m_w_data,
    output logic [axi4_b_bits(AXI4_PARAM_DEFAULT)-1:0]        m_b_data,
    input  logic [axi4_ax_bits(AXI4_PARAM_DEFAULT, 1'b1)-1:0] m_ar_data,
    output logic [axi4_r_bits(AXI4_PARAM_DEFAULT)-1:0]        m_r_data,
    output logic s_aw_valid, s_w_valid, s_b_ready, s_ar_valid, s_r_ready,
    input  logic s_aw_ready, s_w_ready, s_b_valid, s_ar_ready, s_r_valid,
    output logic [axi4_ax_bits(AXI4_PARAM_DEFAULT, 1'b0)-1:0] s_aw_data,
    output logic [axi4_wd_bits(AXI4_PARAM_DEFAULT)-1:0]       s_w_data,
    input  logic [axi4_b_bits(AXI4_PARAM_DEFAULT)-1:0]        s_b_data,
    output logic [axi4_ax_bits(AXI4_PARAM_DEFAULT, 1'b1)-1:0] s_ar_data,
    input  logic [axi4_r_bits(AXI4_PARAM_DEFAULT)-1:0]        s_r_data
);
    localparam axi4_param_t P = AXI4_PARAM_DEFAULT;
    localparam int unsigned BUS_BYTES = P.DATA_W / 8;

    /* verilator lint_off UNUSEDSIGNAL */
    // Only the address fields feed the helpers.
    axi4_addr_beat_t ax_q;
    /* verilator lint_on UNUSEDSIGNAL */
    assign ax_q = ax;

    always_comb begin
        beat_addr  = axi4_beat_addr(ax_q.addr, ax_q.size, ax_q.len, ax_q.burst, 32'(n));
        lower_lane = 8'(axi4_beat_lower_lane(ax_q.addr, ax_q.size, ax_q.len, ax_q.burst,
                                             32'(n), BUS_BYTES));
        upper_lane = 8'(axi4_beat_upper_lane(ax_q.addr, ax_q.size, ax_q.len, ax_q.burst,
                                             32'(n), BUS_BYTES));
        legal      = axi4_burst_legal(ax_q.addr, ax_q.size, ax_q.len, ax_q.burst, BUS_BYTES);
    end

    axi4_checker #(.P(P)) u_checker (.*);

    axi4_lint_b2b #(.P(P)) u_b2b (
        .aclk, .aresetn,
        .m_aw_valid, .m_aw_ready, .m_aw_data, .m_w_valid, .m_w_ready, .m_w_data,
        .m_b_valid, .m_b_ready, .m_b_data, .m_ar_valid, .m_ar_ready, .m_ar_data,
        .m_r_valid, .m_r_ready, .m_r_data,
        .s_aw_valid, .s_aw_ready, .s_aw_data, .s_w_valid, .s_w_ready, .s_w_data,
        .s_b_valid, .s_b_ready, .s_b_data, .s_ar_valid, .s_ar_ready, .s_ar_data,
        .s_r_valid, .s_r_ready, .s_r_data);

    axi4_lint_xtor #(.P(P)) u_xtor (.aclk, .aresetn);
endmodule
