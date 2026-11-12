class xbar_rtl extends fw_extern_component;
    axi4_sub_sp #(PS) s0, s1;
    axi4_mgr_sp #(PM) m0, m1;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual function string extern_module(); return "axi_crossbar"; endfunction

    function void build();
        s0 = new("s0", this);
        s1 = new("s1", this);
        m0 = new("m0", this);
        m1 = new("m1", this);
    endfunction

    virtual function void extern_map(fw_extern_map x);
        x.param("S_COUNT", 2);
        x.param("M_COUNT", 2);
        x.param("DATA_WIDTH", PS.DATA_W);
        x.param("ADDR_WIDTH", PS.ADDR_W);
        x.param("S_ID_WIDTH", PS.ID_W);
        x.param("M_ADDR_WIDTH", 64'h0000_000f_0000_000f);   // {32'd15, 32'd15}
        x.clock("clk");
        x.reset("rst");
        // Each port is one slot of the packed pins.
        x.prefix(s0, "s_axi_").slot(0);
        x.prefix(s1, "s_axi_").slot(1);
        x.prefix(m0, "m_axi_").slot(0);
        x.prefix(m1, "m_axi_").slot(1);
        // USER is off (*USER_ENABLE = 0); its pins are still there.
        x.tie("s_axi_awuser", 0);
        x.tie("s_axi_wuser", 0);
        x.tie("s_axi_aruser", 0);
        x.tie("m_axi_buser", 0);
        x.tie("m_axi_ruser", 0);
        x.open("s_axi_buser");
        x.open("s_axi_ruser");
        x.open("m_axi_awuser");
        x.open("m_axi_wuser");
        x.open("m_axi_aruser");
    endfunction
endclass
