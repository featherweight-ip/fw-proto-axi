// A synthetic bundle for the transactor weave (xtor option), covering what the
// AXI4 bundle does not: an active-high reset (fw_reset), non-default roles, one
// channel each way and an fw_opt member. Woven with the AXI4 core.
package weave_synx_pkg;
    import fw_proto_pkg::*;
    import weave_synx_defs_pkg::*;
    /* verilator lint_off UNUSEDPARAM */

    class synx_types #(synx_param_t P = SYNX_PARAM_DEFAULT);
        typedef struct packed {
            logic [P.DATA_W-1:0]        wdata;
            (* fw_opt = "HAS_PRI" *) logic [1:0] pri;
        } cmd_t;
        typedef struct packed {
            logic [P.DATA_W-1:0] rdata;
            logic                ok;
            logic                last;
        } rsp_t;
    endclass

    (* fw_proto_bundle = "synx", fw_roles = "ctl,per", fw_clock = "clk", fw_reset = "rst",
       fw_defs_pkg = "weave_synx_defs_pkg" *)
    class synx_bundle #(synx_param_t P = SYNX_PARAM_DEFAULT);
        typedef synx_types #(P) t;
        (* fw_fwd *) fw_rv_ch #(t::cmd_t) cmd;
        (* fw_rev *) fw_rv_ch #(t::rsp_t) rsp;
    endclass
    /* verilator lint_on UNUSEDPARAM */
endpackage
