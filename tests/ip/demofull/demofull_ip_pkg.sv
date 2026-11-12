// wb2axip demofull behind the AXI4 class API (plan P6.4): upper-case pin
// names (S_AXI_AWADDR), an active-low reset, and a non-AXI memory port
// (o_we ... o_raddr out, i_rdata in) that is not part of the bundle.
//
//   demo_top
//   +-- dut : demo_api              (class: an axi4_sub_socket)
//   |   +-- core : demo_sys         (RTL structural: emitted as module demo_sys)
//   |   |   +-- slv : demofull_rtl  (extern: demofull)
//   |   +-- s_abs                   abstractor, inserted by core.s.connect(s)
//   +-- tb : demo_tb
//
// The memory port: the outputs are left open and i_rdata is tied to RDATA, so
// every read returns RDATA and writes go nowhere. The tests check the AXI side:
// responses, IDs, beat counts, and the tied value on every active lane.
`include "fw_hdl_macros.svh"

package demofull_ip_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;
    import ip_axi_tb_pkg::*;

    // demofull's pins: QOS but no REGION, no USER.
    localparam axi4_param_t P = '{ADDR_W: 16, DATA_W: 32, ID_W: 4,
                                  AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
                                  HAS_QOS: 1, HAS_REGION: 0};
    localparam logic [31:0] RDATA = 32'h5a5a_5a5a;

    `include "demofull_rtl.svh"

    `include "demo_sys.svh"

    `include "demo_api.svh"
    typedef fw_proto_reg #(demo_api, "demo_api") demo_api_reg;

    `include "demo_tb.svh"

    `include "demo_top.svh"
endpackage
