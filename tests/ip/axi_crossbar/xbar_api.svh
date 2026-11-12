class xbar_api extends fw_component;
    axi4_sub_socket #(PS) s0, s1;
    axi4_mgr_socket #(PM) m0, m1;
    xbar_sys              core;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    function void build();
        s0   = new("s0", this);
        s1   = new("s1", this);
        m0   = new("m0", this);
        m1   = new("m1", this);
        core = new("core", this);
    endfunction

    function void connect();
        void'(core.s0.connect(s0));
        void'(core.s1.connect(s1));
        void'(core.m0.connect(m0));
        void'(core.m1.connect(m1));
    endfunction
endclass
