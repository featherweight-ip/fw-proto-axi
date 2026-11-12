class demo_sys extends fw_rtl_structural;
    axi4_sub_sp #(P) s;
    demofull_rtl     slv;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual function string module_name(); return "demo_sys"; endfunction

    function void build();
        s   = new("s", this);
        slv = new("slv", this);
    endfunction

    function void connect();
        s.bind_inner(slv.s);
    endfunction
endclass
