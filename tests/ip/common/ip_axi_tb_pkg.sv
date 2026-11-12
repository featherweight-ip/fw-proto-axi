// What every reference-IP test shares (tests/ip): a manager component on an
// axi4_mgr_socket, burst-level write and read with checks, and random bursts.
//
// A read is checked against axi4_mem_model as the reference (a memory IP), or,
// with const_rdata set, against one constant on every active lane (an IP whose
// read data comes from a tied input pin).
//
// ip_axi_mem is the other end: a memory component on an axi4_sub_socket, for an
// IP whose manager ports leave the module tree (a crossbar's).
//
// ip_axi_rules puts the AXI4 rules on the inserted abstractors, by path.
`include "fw_hdl_macros.svh"

package ip_axi_tb_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;
    import fw_proto_axi4_rules_pkg::*;

    `include "ip_axi_tb.svh"

    `include "ip_axi_id_mem.svh"

    `include "ip_axi_mem.svh"

    `include "ip_axi_rules.svh"
endpackage
