class xbar_sys extends fw_rtl_structural;
    axi4_sub_sp #(PS) s0, s1;
    axi4_mgr_sp #(PM) m0, m1;
    xbar_rtl          xbar;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual function string module_name(); return "xbar_sys"; endfunction

    function void build();
        s0   = new("s0", this);
        s1   = new("s1", this);
        m0   = new("m0", this);
        m1   = new("m1", this);
        xbar = new("xbar", this);
    endfunction

    function void connect();
        s0.bind_inner(xbar.s0);
        s1.bind_inner(xbar.s1);
        m0.bind_inner(xbar.m0);
        m1.bind_inner(xbar.m1);
    endfunction
endclass
