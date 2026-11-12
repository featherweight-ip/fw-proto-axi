// ------------------------------------------------------------------
// The burst API pair on a component: the manager's socket calls requests
// and provides responses; the subordinate's mirror the reverse.
// ------------------------------------------------------------------
class axi4_burst_mgr_socket #(axi4_param_t P = AXI4_PARAM_DEFAULT)
        extends fw_socket #(axi4_burst_req_if #(P), axi4_burst_rsp_if #(P));
    function new(string name, fw_component parent, axi4_burst_rsp_if #(P) imp = null);
        super.new(name, parent, imp);
    endfunction
endclass
