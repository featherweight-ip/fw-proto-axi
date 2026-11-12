// AXI4: the core specification, class part. Everything else in the package (base
// classes, listeners, proxies, imps, channel APIs, ...) is derived from this file by
// the fw_proto weavers (docs/design-new-style.md §3, §4). The parameter set,
// encodings and burst arithmetic are in fw_proto_axi4_defs_pkg (synthesizable);
// a user of this package imports both.
//
// Attributes read by the weavers:
//   (* fw_api *)                  an API interface class
//   (* fw_opt = "<P member>" *)   a payload field with pins only when P.<member> != 0
//   (* fw_proto_bundle, fw_roles *), (* fw_fwd *), (* fw_rev *)   the port bundle
//   (* fw_clock, fw_reset_n *)    the bundle's clock and reset pins
//   (* fw_defs_pkg *)             the bundle's synthesizable package (for the RTL cores)
package fw_proto_axi4_core_pkg;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    /* verilator lint_off UNUSEDPARAM */

    `include "axi4_types.svh"

    `include "axi4_bundle.svh"

    // ------------------------------------------------------------------
    // The transaction-level APIs, the only APIs written by hand (the channel
    // APIs come from the bundle).
    //
    // The burst API is the protocol's own: a transaction is its address beat,
    // its data beats and its response beat(s), in the channel payload types, so
    // nothing on the channels is lost and a field added to a payload reaches it
    // with no other edit. Two interfaces, one per direction (design §3.4, D11):
    // the manager calls axi4_burst_req_if, the subordinate calls
    // axi4_burst_rsp_if back as responses complete. The adapters, the memory
    // model and wrapped IPs speak it.
    // ------------------------------------------------------------------
    // Prototype arguments are neither read nor written here.
    /* verilator lint_off UNUSEDSIGNAL */
    /* verilator lint_off UNDRIVEN */
    `include "axi4_burst_req_if.svh"

    `include "axi4_burst_rsp_if.svh"

    `include "axi4_xact_if.svh"
    /* verilator lint_on UNDRIVEN */
    /* verilator lint_on UNUSEDSIGNAL */

    /* verilator lint_on UNUSEDPARAM */
endpackage
