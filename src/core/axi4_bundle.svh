// ------------------------------------------------------------------
// The port bundle: channels, their direction relative to the manager,
// and their handshake family. Clock ACLK, reset ARESETn (active low).
// ------------------------------------------------------------------
(* fw_proto_bundle = "axi4", fw_roles = "mgr,sub", fw_clock = "aclk", fw_reset_n = "aresetn",
   fw_defs_pkg = "fw_proto_axi4_defs_pkg" *)
class axi4_bundle #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    typedef axi4_types #(P) t;
    (* fw_fwd *) fw_rv_ch #(t::aw_t) aw;
    (* fw_fwd *) fw_rv_ch #(t::w_t)  w;
    (* fw_rev *) fw_rv_ch #(t::b_t)  b;
    (* fw_fwd *) fw_rv_ch #(t::ar_t) ar;
    (* fw_rev *) fw_rv_ch #(t::r_t)  r;
endclass
