// ------------------------------------------------------------------
// The description
// ------------------------------------------------------------------
class axi_ram_rtl extends fw_extern_component;
    axi4_sub_sp #(P) s;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual function string extern_module(); return "axi_ram"; endfunction

    function void build();
        s = new("s", this);
    endfunction

    virtual function void extern_map(fw_extern_map x);
        x.param("DATA_WIDTH", P.DATA_W);
        x.param("ADDR_WIDTH", P.ADDR_W);
        x.param("ID_WIDTH", P.ID_W);
        x.clock("clk");
        x.reset("rst");
        x.prefix(s, "s_axi_");
    endfunction
endclass
