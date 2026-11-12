// AXI4 behaviour, new style (plan P5): hand-written classes on the generated _base
// classes of fw_proto_axi4_core_pkg_woven; no macros.
//
//   axi4_mgr_adapter      burst requests in, channel beats out; B/R beats back up
//                         as burst responses (manager end)
//   axi4_sub_adapter      channel beats in, burst requests out; burst responses back
//                         as B/R beats (subordinate end)
//   axi4_mem_model        a memory behind the burst API
//   axi4_burst_blocking   a blocking call per burst over the burst API, for tests
//   axi4_xact_on_burst    the convenience axi4_xact_if over axi4_burst_blocking
//   axi4_burst_on_xact    an axi4_xact_if target behind the burst API (lossy: no USER,
//                         one response per read)
//   axi4_burst_mgr_socket, axi4_burst_sub_socket
//                         the burst API pair on a component (fw_socket / fw_mirror)
//   axi4_to_mem           fw-hdl's fw_mem_if over an axi4_xact_if
//
// The burst API is two-way (design §3.4, D11): requests return once their beats
// are accepted; responses come back as calls, as they complete. Nothing above the
// transactors waits per outstanding transaction, except the blocking shims.
//
// The adapters pass the channel payloads through unchanged, apart from zeroing the
// fields the parameter set leaves off the pins (the generated axi4_payloads::<ch>_mask),
// so a link with pins and one without deliver the same beats. Only the two shims
// convert between the channel payloads and the convenience API's arguments
// (axi4_attr).
package fw_proto_axi4_behav_pkg;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_std_pkg::fw_mem_if;
    import fw_hdl_pkg::fw_component, fw_hdl_pkg::fw_socket, fw_hdl_pkg::fw_mirror;

    `include "axi4_attr.svh"

    `include "axi4_id_turns.svh"

    `include "axi4_burst_waiter.svh"

    `include "axi4_sub_wr_job.svh"

    `include "axi4_mgr_adapter.svh"

    `include "axi4_sub_adapter.svh"

    `include "axi4_mem_model.svh"

    `include "axi4_burst_blocking.svh"

    `include "axi4_xact_on_burst.svh"

    `include "axi4_burst_on_xact.svh"

    `include "axi4_burst_mgr_socket.svh"

    `include "axi4_burst_sub_socket.svh"

    `include "axi4_to_mem.svh"
endpackage
