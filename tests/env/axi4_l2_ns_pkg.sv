// Test-side record of one transaction in the convenience API's terms (the L2 cells
// build requests and keep results in it). Library code does not use it.
package axi4_l2_ns_pkg;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;

    class axi4_l2_xact #(axi4_param_t P = AXI4_PARAM_DEFAULT);
        typedef axi4_attr #(P)          at;
        typedef axi4_payloads #(P)      pl;
        typedef axi4_types #(P)::aw_t   aw_t;
        typedef axi4_types #(P)::ar_t   ar_t;
        typedef axi4_types #(P)::attr_t attr_t;
        typedef axi4_types #(P)::addr_t addr_t;
        typedef axi4_types #(P)::data_t data_t;
        typedef axi4_types #(P)::strb_t strb_t;
        localparam int unsigned BUS = P.DATA_W / 8;

        bit          write;
        addr_t       addr;
        logic [7:0]  len;          // beats - 1
        attr_t       attr;
        data_t       data[$];      // write: in; read: out
        strb_t       strb[$];      // write only
        axi4_resp_e  resp;
        bit          done;

        function int unsigned n_beats();
            return axi4_burst_beats(len);
        endfunction

        function axi4_addr64_t beat_addr(int unsigned n);
            return axi4_beat_addr(axi4_addr64_t'(addr), attr.size, len, attr.burst, n);
        endfunction

        function strb_t lanes(int unsigned n);
            return at::lanes(axi4_addr64_t'(addr), attr.size, len, attr.burst, n);
        endfunction

        // The address beat as a link carries it (absent fields zeroed).
        function aw_t link_aw();
            return pl::aw_mask(at::to_aw(addr, n_beats(), attr));
        endfunction

        function ar_t link_ar();
            return pl::ar_mask(at::to_ar(addr, n_beats(), attr));
        endfunction

        // attr as a link carries it.
        function attr_t link_attr();
            return write ? at::of_aw(link_aw()) : at::of_ar(link_ar());
        endfunction

        function string convert2string();
            return $sformatf("%s id=0x%0h addr=0x%0h len=%0d size=%0d %s%s resp=%s",
                write ? "WR" : "RD", attr.id, addr, len, attr.size, attr.burst.name(),
                attr.lock ? " excl" : "", resp.name());
        endfunction
    endclass
endpackage
