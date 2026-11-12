// fw_proto runtime: the protocol-agnostic SV that protocol cores and the code
// derived from them build on. Names no protocol.
//
//   fw_dir_e, fw_field_t   one pin-level field of a bundle and its direction
//   fw_sp_base             a struct port: a bundle's field table, plus its
//                          link (to the peer role) and bind (to a parent's port)
//   fw_rv_ch #(T)          the ready/valid channel family a bundle declares
//                          its channels with
//   fw_inbox #(T)          a per-channel inbound queue for scripted endpoints
//   fw_realized ...        components the emitter realizes: externs, RTL
//                          structurals, abstractors (fw_proto_abs.svh)
//   fw_rule ...            protocol rules in the restricted form (fw_rule.svh):
//                          fw_count, fw_flag, fw_value, fw_any; fw_rule_set runs
//                          one in simulation; fw_rv_hold is the ready/valid
//                          family's signal-level rule
//
// The protocol-specific parts (which fields, which roles, the typed link and
// bind, the abstractors) are generated from the bundle by the fw-proto weaver.
package fw_proto_pkg;
    import fw_hdl_pkg::*;

    typedef class fw_realized;
    typedef class fw_emitter;
    typedef class fw_rule;
    typedef class fw_rule_node;
    typedef class fw_rule_set;

    // Path below the root, e.g. "dut" or "dut.core".
    function automatic string fw_rel_path(fw_component c);
        string p;
        if (c.get_parent() == null) return "";
        p = fw_rel_path(c.get_parent());
        return (p == "") ? c.get_name() : {p, ".", c.get_name()};
    endfunction

    // A path as an identifier: "dut.core" -> "dut_core".
    function automatic string fw_ident(string path);
        foreach (path[i]) if (path[i] == ".") path[i] = "_";
        return path;
    endfunction

    // Pin direction of a field, relative to the bundle's first role: FW_FWD is
    // driven by the first role (e.g. the manager), FW_REV by the second.
    typedef enum bit { FW_FWD = 1'b0, FW_REV = 1'b1 } fw_dir_e;

    function automatic fw_dir_e fw_dir_flip(fw_dir_e d);
        return (d == FW_FWD) ? FW_REV : FW_FWD;
    endfunction

    typedef struct {
        string       name;          // pin name without prefix, e.g. "awaddr"
        int unsigned width;
        fw_dir_e     dir;
    } fw_field_t;

    `include "fw_sp_base.svh"

    `include "fw_rv_ch.svh"

    `include "fw_inbox.svh"

    `include "fw_proto_abs.svh"

    `include "fw_rule_state.svh"

    `include "fw_count.svh"

    `include "fw_flag.svh"

    `include "fw_value.svh"

    `include "fw_any_base.svh"

    `include "fw_any.svh"

    `include "fw_rule.svh"

    `include "fw_rule_node.svh"

    `include "fw_rule_set.svh"

    `include "fw_rv_hold.svh"

endpackage
