class ram_top extends fw_component;
    ram_api dut;
    ram_tb  tb;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    function void build();
        // dut before tb: tb.m resolves through dut.s, whose imp dut's
        // connect() sets (fw-hdl resolves child by child).
        dut = ram_api_reg::create("dut", this);
        tb  = new("tb", this);
    endfunction

    function void connect();
        tb.m.connect(dut.s);
    endfunction
endclass
