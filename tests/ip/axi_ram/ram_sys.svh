class ram_sys extends fw_rtl_structural;
    axi4_sub_sp #(P) s;
    axi_ram_rtl      ram;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual function string module_name(); return "ram_sys"; endfunction

    function void build();
        s   = new("s", this);
        ram = new("ram", this);
    endfunction

    function void connect();
        s.bind_inner(ram.s);
    endfunction
endclass
