// A blocking caller's transaction (axi4_burst_blocking): its response, once done.
class axi4_burst_waiter #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    axi4_types #(P)::b_t   b;
    axi4_types #(P)::r_t   r[$];
    bit                    done;
endclass
