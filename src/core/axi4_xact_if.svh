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
