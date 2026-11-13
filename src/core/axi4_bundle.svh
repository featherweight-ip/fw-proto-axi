// ------------------------------------------------------------------
// The port bundle: channels, their direction relative to the manager,
// and their handshake family. Clock and reset are not here: they are the
// domain of the component that holds a transactor (docs/design-domains.md),
// and a device's ACLK / ARESETn (active low) go in its pin map.
// ------------------------------------------------------------------
(* fw_proto_bundle = "axi4", fw_roles = "mgr,sub", fw_defs_pkg = "fw_proto_axi4_defs_pkg" *)
class axi4_bundle #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    typedef axi4_types #(P) t;
    (* fw_fwd *) fw_rv_ch #(t::aw_t) aw;
    (* fw_fwd *) fw_rv_ch #(t::w_t)  w;
    (* fw_rev *) fw_rv_ch #(t::b_t)  b;
    (* fw_fwd *) fw_rv_ch #(t::ar_t) ar;
    (* fw_rev *) fw_rv_ch #(t::r_t)  r;
endclass
