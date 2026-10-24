// `xtor` view harness body, shared by every level; the including file
// defines AXI4_HARNESS, AXI4_ENV_T, AXI4_EP_MGR and AXI4_EP_SUB exactly as
// for axi4_tlm_harness.svh. The link goes through a bridge, a signal-level
// transactor, real AXI4 pins, the opposite transactor and its bridge. The
// unit tests are the same files as in `tlm`.
//
//   mgr side -> axi4_mgr_xtor_bridge -> u_mgr ==pins== u_sub -> axi4_sub_xtor_bridge -> sub side
//
// An axi4_checker (all rules asserted) sits on the pins unless the including
// file defines AXI4_NO_CHECK (L1 tests drive streams that are not protocol
// consistent).
`include "fw_hdl_macros.svh"

module `AXI4_HARNESS;
    import fw_hdl_pkg::*;
    import axi4_types_pkg::*;
    import fw_proto_axi4_xtor_pkg::*;
    import axi4_test_pkg::*;

    class axi4_env_xtor extends `AXI4_ENV_T;
        function new(string name, fw_component parent); super.new(name, parent); endfunction
    endclass

    localparam axi4_param_t P = axi4_test_pkg::AXI4_TEST_PARAM;
    localparam int unsigned AW_  = P.ADDR_W;
    localparam int unsigned DW_  = P.DATA_W;
    localparam int unsigned IW_  = axi4_w1(P.ID_W);
    localparam int unsigned AUW_ = axi4_w1(P.AWUSER_W);
    localparam int unsigned WUW_ = axi4_w1(P.WUSER_W);
    localparam int unsigned BUW_ = axi4_w1(P.BUSER_W);
    localparam int unsigned RAW_ = axi4_w1(P.ARUSER_W);
    localparam int unsigned RUW_ = axi4_w1(P.RUSER_W);

    reg clock = 0, reset = 1;
    always #5 clock = ~clock;
    initial begin
        repeat (2) @(posedge clock);
        reset = 0;
    end

    wire aclk = clock;
    wire aresetn = !reset;

    // ---- the pins
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

    axi4_mgr_xtor #(.P(P)) u_mgr (.*);
    axi4_sub_xtor #(.P(P)) u_sub (.*);
`ifndef AXI4_NO_CHECK
    axi4_checker #(.P(P), .MAX_OUT(16)) u_chk (.*);
`endif

    // ---- the class tree, bound to the pins
    `fw_root_begin(axi4_env_xtor, u_root, clock, reset)
        `fw_root_bind_socket(`AXI4_EP_MGR, u_mgr.u_if, axi4_mgr_xtor_bridge)
        `fw_root_bind_mirror(`AXI4_EP_SUB, u_sub.u_if, axi4_sub_xtor_bridge)
    `fw_root_end
endmodule
