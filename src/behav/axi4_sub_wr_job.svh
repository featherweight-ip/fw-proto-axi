// A write of the subordinate adapter waiting for its W beats.
class axi4_sub_wr_job #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    axi4_types #(P)::aw_t  aw;
    axi4_types #(P)::w_t   w[$];
endclass
