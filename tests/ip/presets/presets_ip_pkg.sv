// Pin-map presets (plan P6, design §4.6): each naming style, on a subordinate
// and a manager port, for P_DEF and P_WIDE. The extern modules are stubs whose
// headers follow the AMBA signal names (presets.py writes them, from its own
// table, not the bundle's), so linting the emitted netlist against them checks
// that the preset maps every field of P to a pin of the right name and width.
//
//   presets_top
//   +-- <tag> : preset_api #(P, UC, tag)   (one per P x style; factory-created)
//       +-- core : preset_sys             (RTL structural: emitted as preset_<tag>_sys)
//       |   +-- rtl : preset_rtl          (extern: module preset_<tag>)
//       +-- s_abs, m_abs                  abstractors (core.s/m.connect(s/m))
//   +-- <tag>_ends : preset_ends #(P)      class-side peers of the API sockets
//
// Styles: lc = s_axi_/m_axi_, clk, rst; uc = S_AXI_/M_AXI_ upper case, ACLK,
// ARESETN (active low).
`include "fw_hdl_macros.svh"

package presets_ip_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;
    import axi4_test_params_pkg::*;

    `include "preset_rtl.svh"

    `include "preset_sys.svh"

    `include "preset_api.svh"
    typedef preset_api #(P_DEF,  0, "def_lc")  preset_api_def_lc;
    typedef preset_api #(P_DEF,  1, "def_uc")  preset_api_def_uc;
    typedef preset_api #(P_WIDE, 0, "wide_lc") preset_api_wide_lc;
    typedef preset_api #(P_WIDE, 1, "wide_uc") preset_api_wide_uc;
    typedef fw_proto_reg #(preset_api_def_lc,  "preset_api_def_lc")  preset_api_def_lc_reg;
    typedef fw_proto_reg #(preset_api_def_uc,  "preset_api_def_uc")  preset_api_def_uc_reg;
    typedef fw_proto_reg #(preset_api_wide_lc, "preset_api_wide_lc") preset_api_wide_lc_reg;
    typedef fw_proto_reg #(preset_api_wide_uc, "preset_api_wide_uc") preset_api_wide_uc_reg;

    `include "preset_ends.svh"

    `include "presets_top.svh"
endpackage
