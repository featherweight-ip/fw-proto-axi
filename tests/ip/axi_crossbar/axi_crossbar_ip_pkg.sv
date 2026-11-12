// verilog-axi axi_crossbar (2x2) behind the AXI4 class API (plan P6.4): ports
// in slots of packed-vector pins, ID widening, out-of-order responses.
//
//   xbar_top
//   +-- dut : xbar_api                (class: two axi4_sub_sockets, two axi4_mgr_sockets)
//   |   +-- core : xbar_sys           (RTL structural: emitted as module xbar_sys)
//   |   |   +-- xbar : xbar_rtl       (extern: axi_crossbar, S_COUNT = M_COUNT = 2)
//   |   +-- s0_abs, s1_abs            manager abstractors (core.s<i>.connect(s<i>))
//   |   +-- m0_abs, m1_abs            subordinate abstractors (core.m<i>.connect(m<i>))
//   +-- tb0, tb1 : xbar_tb            (managers, on dut.s0 and dut.s1, at once)
//   +-- mem0, mem1 : ip_axi_mem       (memories, on dut.m0 and dut.m1)
//
// The address map: m0 is 0x0000-0x7fff, m1 0x8000-0xffff (M_ADDR_WIDTH 15 each).
// The master ports' IDs are one bit wider: the crossbar adds the slave port.
`include "fw_hdl_macros.svh"

package axi_crossbar_ip_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;
    import ip_axi_tb_pkg::*;

    // Slave ports: QOS, no REGION. Master ports: QOS and REGION, one more ID bit.
    localparam axi4_param_t PS = '{ADDR_W: 16, DATA_W: 32, ID_W: 4,
                                   AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
                                   HAS_QOS: 1, HAS_REGION: 0};
    localparam axi4_param_t PM = '{ADDR_W: 16, DATA_W: 32, ID_W: 5,
                                   AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
                                   HAS_QOS: 1, HAS_REGION: 1};

    `include "xbar_rtl.svh"

    `include "xbar_sys.svh"

    `include "xbar_api.svh"
    typedef fw_proto_reg #(xbar_api, "xbar_api") xbar_api_reg;

    `include "xbar_tb.svh"

    `include "xbar_top.svh"
endpackage
