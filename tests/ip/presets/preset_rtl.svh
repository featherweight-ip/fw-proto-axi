// The stub module preset_<TAG>, one preset line per port.
class preset_rtl #(axi4_param_t P = AXI4_PARAM_DEFAULT, bit UC = 0, string TAG = "")
        extends fw_extern_component;
    axi4_sub_sp #(P) s;
    axi4_mgr_sp #(P) m;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual function string extern_module(); return {"preset_", TAG}; endfunction

    function void build();
        s = new("s", this);
        m = new("m", this);
    endfunction

    virtual function void extern_map(fw_extern_map x);
        if (UC) begin
            x.clock("ACLK");
            x.reset("ARESETN", .active_low(1));
            x.prefix(s, "S_AXI_").upper();
            x.prefix(m, "M_AXI_").upper();
        end else begin
            x.clock("clk");
            x.reset("rst");
            x.prefix(s, "s_axi_");
            x.prefix(m, "m_axi_");
        end
    endfunction
endclass
