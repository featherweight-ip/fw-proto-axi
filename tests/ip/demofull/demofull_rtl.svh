class demofull_rtl extends fw_extern_component;
    axi4_sub_sp #(P) s;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual function string extern_module(); return "demofull"; endfunction

    function void build();
        s = new("s", this);
    endfunction

    virtual function void extern_map(fw_extern_map x);
        x.param("C_S_AXI_ID_WIDTH", P.ID_W);
        x.param("C_S_AXI_DATA_WIDTH", P.DATA_W);
        x.param("C_S_AXI_ADDR_WIDTH", P.ADDR_W);
        x.clock("S_AXI_ACLK");
        x.reset("S_AXI_ARESETN", .active_low(1));
        x.prefix(s, "S_AXI_").upper();
        // Not AXI: the memory port.
        x.tie("i_rdata", RDATA);
        x.open("o_we");
        x.open("o_waddr");
        x.open("o_wdata");
        x.open("o_wstrb");
        x.open("o_rd");
        x.open("o_raddr");
    endfunction
endclass
