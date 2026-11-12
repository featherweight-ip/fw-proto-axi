class demo_top extends fw_component;
    demo_api dut;
    demo_tb  tb;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    function void build();
        dut = demo_api_reg::create("dut", this);
        tb  = new("tb", this);
    endfunction

    function void connect();
        tb.m.connect(dut.s);
    endfunction
endclass
