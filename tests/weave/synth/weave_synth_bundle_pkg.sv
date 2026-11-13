// A synthetic bundle covering what the AXI4 bundle does not: no struct parameter
// (two int parameters, so fw_opt guards are expressions and param_lit() is
// empty), an active-high reset (fw_reset), non-default roles and an fw_opt
// member. Woven with the AXI4 core for the weave suite (no xtor option: the
// transactors need one struct parameter).
package weave_synth_bundle_pkg;
    import fw_proto_pkg::*;

    class synb_types #(int AW = 8, int DW = 16);
        typedef struct packed {
            logic [AW-1:0] addr;
            (* fw_opt = "DW > 8" *) logic [3:0] tag;
            logic          wr;
        } cmd_t;
        typedef struct packed {
            logic [DW-1:0] data;
            logic          err;
        } rsp_t;
    endclass

    (* fw_proto_bundle = "synb", fw_roles = "host,dev", fw_clock = "clk", fw_reset = "rst" *)
    class synb_bundle #(int AW = 8, int DW = 16);
        typedef synb_types #(AW, DW) t;
        (* fw_fwd *) fw_rv_ch #(t::cmd_t) cmd;
        (* fw_rev *) fw_rv_ch #(t::rsp_t) rsp;
    endclass
endpackage
