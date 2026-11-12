// AXI4 rules (plan P7; design §3.5; brief §5): the protocol's contract as
// listeners in the restricted form of fw_rule (fw_proto_pkg). Hand-written: the
// rules are specification. Built on the woven channel listeners, so like the
// behaviour it comes in two forms (`rules` over `woven`, `rules-xtor` over
// `woven-xtor`). The rules and where they attach: docs/rules.md.
package fw_proto_axi4_rules_pkg;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;

    typedef class axi4_rule_node;

    `include "axi4_rule.svh"

    `include "axi4_rule_node.svh"

    `include "axi4_rule_resp_match.svh"

    `include "axi4_rule_r_burst.svh"

    `include "axi4_rule_w_burst.svh"

    `include "axi4_rule_b_order.svh"

    `include "axi4_rule_burst_legal.svh"

    `include "axi4_rule_w_lanes.svh"

    `include "axi4_rule_capacity.svh"

    `include "axi4_rule_exclusive.svh"

    `include "axi4_rule_rv_hold.svh"

    `include "axi4_rules.svh"
endpackage
