class preset_api #(axi4_param_t P = AXI4_PARAM_DEFAULT, bit UC = 0, string TAG = "")
        extends fw_component;
    axi4_sub_socket #(P)       s;
    axi4_mgr_socket #(P)       m;
    preset_sys #(P, UC, TAG)   core;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    function void build();
        s    = new("s", this);
        m    = new("m", this);
        core = new("core", this);
    endfunction

    function void connect();
        void'(core.s.connect(s));
        void'(core.m.connect(m));
    endfunction
endclass
