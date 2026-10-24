// Lint elaboration top: every synthesizable unit of the kit, at the default
// interface configuration, so Verilator's elaboration-time checks (width,
// latch, unused, undriven) see all of it. For now: the types package, through
// its burst helpers; the pin checker on free inputs.
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
    input  logic [63:0] wdata, rdata
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
endmodule
