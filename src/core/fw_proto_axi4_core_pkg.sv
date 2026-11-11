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

    // ------------------------------------------------------------------
    // Channel payloads, sized by P. Member names are the AMBA names without
    // the channel prefix; the bundle's channel name supplies the prefix.
    // ------------------------------------------------------------------
    class axi4_types #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef struct packed {
            (* fw_opt = "ID_W" *)       logic [w1(P.ID_W)-1:0] id;
            logic [P.ADDR_W-1:0]       addr;
            logic [7:0]                len;
            axi4_size_e                size;
            axi4_burst_e               burst;
            logic                      lock;
            logic [3:0]                cache;
            logic [2:0]                prot;
            (* fw_opt = "HAS_QOS" *)    logic [3:0] qos;
            (* fw_opt = "HAS_REGION" *) logic [3:0] region;
            (* fw_opt = "AWUSER_W" *)   logic [w1(P.AWUSER_W)-1:0] user;
        } aw_t;
        typedef struct packed {
            (* fw_opt = "ID_W" *)       logic [w1(P.ID_W)-1:0] id;
            logic [P.ADDR_W-1:0]       addr;
            logic [7:0]                len;
            axi4_size_e                size;
            axi4_burst_e               burst;
            logic                      lock;
            logic [3:0]                cache;
            logic [2:0]                prot;
            (* fw_opt = "HAS_QOS" *)    logic [3:0] qos;
            (* fw_opt = "HAS_REGION" *) logic [3:0] region;
            (* fw_opt = "ARUSER_W" *)   logic [w1(P.ARUSER_W)-1:0] user;
        } ar_t;
        typedef struct packed {
            logic [P.DATA_W-1:0]       data;
            logic [P.DATA_W/8-1:0]     strb;
            logic                      last;
            (* fw_opt = "WUSER_W" *)    logic [w1(P.WUSER_W)-1:0] user;
        } w_t;
        typedef struct packed {
            (* fw_opt = "ID_W" *)       logic [w1(P.ID_W)-1:0] id;
            axi4_resp_e                resp;
            (* fw_opt = "BUSER_W" *)    logic [w1(P.BUSER_W)-1:0] user;
        } b_t;
        typedef struct packed {
            (* fw_opt = "ID_W" *)       logic [w1(P.ID_W)-1:0] id;
            logic [P.DATA_W-1:0]       data;
            axi4_resp_e                resp;
            logic                      last;
            (* fw_opt = "RUSER_W" *)    logic [w1(P.RUSER_W)-1:0] user;
        } r_t;
        // Address-channel attributes of the convenience API (axi4_xact_if).
        typedef struct packed {
            logic [w1(P.ID_W)-1:0]     id;
            axi4_burst_e               burst;
            axi4_size_e                size;
            logic                      lock;
            logic [3:0]                cache;
            logic [2:0]                prot;
            logic [3:0]                qos;
            logic [3:0]                region;
            logic [w1(max2(P.AWUSER_W, P.ARUSER_W))-1:0] user;
        } attr_t;
        typedef logic [P.ADDR_W-1:0]   addr_t;
        typedef logic [P.DATA_W-1:0]   data_t;
        typedef logic [P.DATA_W/8-1:0] strb_t;
    endclass

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
    (* fw_api *)
    interface class axi4_burst_req_if #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_types #(P)::aw_t aw_t;
        typedef axi4_types #(P)::w_t  w_t;
        typedef axi4_types #(P)::ar_t ar_t;
        // aw.len + 1 beats in w. Returns when the beats are accepted; the B
        // beat comes back through write_resp (possibly before this returns).
        pure virtual task write_burst(input aw_t aw, input w_t w[$]);
        // Returns when AR is accepted; the R beats come back through read_resp.
        pure virtual task read_burst(input ar_t ar);
    endclass

    // The responses to axi4_burst_req_if, in request order per ID; R beats of
    // different IDs may interleave. A call may block until the beat is accepted.
    (* fw_api *)
    interface class axi4_burst_rsp_if #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_types #(P)::b_t b_t;
        typedef axi4_types #(P)::r_t r_t;
        // One per write_burst.
        pure virtual task write_resp(input b_t b);
        // One per R beat; r.last ends the burst.
        pure virtual task read_resp(input r_t r);
    endclass

    // A convenience on top of the burst API (axi4_xact_on_burst implements it):
    // plain arguments, no channel structs, blocking. write moves data.size() beats (strobes
    // missing from strb default to the active lanes); read moves `beats` beats.
    // attr holds the address-channel fields; resp is B, or the worst R beat's.
    // W/B/R USER and per-beat R responses are only on the burst API.
    (* fw_api *)
    interface class axi4_xact_if #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_types #(P)::addr_t addr_t;
        typedef axi4_types #(P)::data_t data_t;
        typedef axi4_types #(P)::strb_t strb_t;
        typedef axi4_types #(P)::attr_t attr_t;
        pure virtual task write(input addr_t addr, input data_t data[$], input strb_t strb[$],
                                input attr_t attr, output axi4_resp_e resp);
        pure virtual task read(input addr_t addr, input int unsigned beats, input attr_t attr,
                               output data_t data[$], output axi4_resp_e resp);
    endclass
    /* verilator lint_on UNDRIVEN */
    /* verilator lint_on UNUSEDSIGNAL */

    /* verilator lint_on UNUSEDPARAM */
endpackage
