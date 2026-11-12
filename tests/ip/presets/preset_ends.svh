// The class-side peers of one preset_api, so its sockets resolve: a manager
// socket on api.s, a subordinate socket on api.m. Nothing runs (generate pass).
class preset_ends #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_component;
    axi4_mgr_socket #(P)  m;
    axi4_sub_socket #(P)  s;
    axi4_mgr_adapter #(P) mgr;
    axi4_sub_adapter #(P) sub;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    function void build();
        mgr = new();
        sub = new();
        m   = new("m", this, mgr);
        s   = new("s", this, sub);
    endfunction
endclass
