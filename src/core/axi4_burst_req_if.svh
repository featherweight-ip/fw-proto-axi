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
