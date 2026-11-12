// The memory behind ip_axi_mem: counts bursts by the top bit of their ID,
// which a crossbar sets to the slave port it came from.
class ip_axi_id_mem #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_mem_model #(P);
    int unsigned n_by_top[2];

    virtual task write_burst(input aw_t aw, input w_t w[$]);
        n_by_top[aw.id[$bits(aw.id) - 1]]++;
        super.write_burst(aw, w);
    endtask

    virtual task read_burst(input ar_t ar);
        n_by_top[ar.id[$bits(ar.id) - 1]]++;
        super.read_burst(ar);
    endtask
endclass
