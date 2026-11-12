class axi4_burst_sub_socket #(axi4_param_t P = AXI4_PARAM_DEFAULT)
        extends fw_mirror #(axi4_burst_req_if #(P), axi4_burst_rsp_if #(P));
    function new(string name, fw_component parent, axi4_burst_req_if #(P) imp = null);
        super.new(name, parent, imp);
    endfunction
endclass
