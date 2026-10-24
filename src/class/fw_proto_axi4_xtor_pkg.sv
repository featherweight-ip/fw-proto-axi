// The bridges reference the transactor interface (axi4_xtor_if), so they
// live in their own package, compiled after it (export `xtor-class`).
package fw_proto_axi4_xtor_pkg;
    import fw_hdl_pkg::*;
    import axi4_types_pkg::*;
    import fw_proto_axi4_pkg::*;

    `include "axi4_xtor_bridges.svh"
endpackage
