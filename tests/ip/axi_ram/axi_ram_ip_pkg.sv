// verilog-axi axi_ram behind the AXI4 class API (plan P6.4).
//
// The description, written once:
//
//   ram_top                        (class: the testbench root)
//   +-- dut : ram_api              (class: the RAM behind an axi4_sub_socket)
//   |   +-- core : ram_sys         (RTL structural: emitted as module ram_sys)
//   |   |   +-- ram : axi_ram_rtl  (extern: axi_ram, one pin-map line)
//   |   +-- s_abs                  abstractor, inserted by core.s.connect(s)
//   +-- tb : ram_tb                (class: an axi4_mgr_socket; the tests)
//
// Pass 1 (ip_gen) builds this and emits ram_sys.sv and ram_top_sim.sv. Pass 2
// (axi_ram_tb) runs the emitted files: dut is then ram_api_shell, whose s is
// bound to the s_abs handle and the axi4_mgr_xtor in the module tree.
`include "fw_hdl_macros.svh"

package axi_ram_ip_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;
    import ip_axi_tb_pkg::*;

    // axi_ram's pins: no QOS, REGION or USER.
    localparam axi4_param_t P = '{ADDR_W: 16, DATA_W: 32, ID_W: 8,
                                  AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
                                  HAS_QOS: 0, HAS_REGION: 0};

    `include "axi_ram_rtl.svh"

    `include "ram_sys.svh"

    `include "ram_api.svh"
    typedef fw_proto_reg #(ram_api, "ram_api") ram_api_reg;

    `include "ram_tb.svh"

    `include "ram_top.svh"
endpackage
