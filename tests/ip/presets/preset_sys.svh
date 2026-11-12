class preset_sys #(axi4_param_t P = AXI4_PARAM_DEFAULT, bit UC = 0, string TAG = "")
        extends fw_rtl_structural;
    axi4_sub_sp #(P)            s;
    axi4_mgr_sp #(P)            m;
    preset_rtl #(P, UC, TAG)    rtl;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual function string module_name(); return {"preset_", TAG, "_sys"}; endfunction

    function void build();
        s   = new("s", this);
        m   = new("m", this);
        rtl = new("rtl", this);
    endfunction

    function void connect();
        s.bind_inner(rtl.s);
        m.bind_inner(rtl.m);
    endfunction
endclass
