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
