// fw-proto-axi class layer: the L1 channel APIs and link types, the
// interface configuration and scripted L1 endpoints; the L2 transaction
// API and its manager/subordinate adapters. Built on fw-hdl
// (fw_hdl_pkg, which provides fw_socket/fw_mirror).
`include "axi4_proto_macros.svh"
`include "fw_std_macros.svh"

package fw_proto_axi4_pkg;
    import fw_hdl_pkg::*;
    import fw_std_pkg::*;
    import axi4_types_pkg::*;

    // L1
    `include "axi4_l1_if.svh"
    `include "axi4_cfg.svh"
    `include "axi4_wire.svh"
    `include "axi4_mon.svh"
    `include "axi4_l1_inbox.svh"
    `include "axi4_l1_endpoints.svh"

    // L2
    `include "axi4_xact.svh"
    `include "axi4_mgr_adapter.svh"
    `include "axi4_sub_adapter.svh"
    `include "axi4_mem_model.svh"
    `include "axi4_to_mem.svh"
endpackage
