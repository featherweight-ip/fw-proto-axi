class xbar_top extends fw_component;
    xbar_api          dut;
    xbar_tb           tb0, tb1;
    ip_axi_mem #(PM)  mem0, mem1;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    function void build();
        dut  = xbar_api_reg::create("dut", this);
        tb0  = new("tb0", this);
        tb1  = new("tb1", this);
        mem0 = new("mem0", this);
        mem1 = new("mem1", this);
        tb0.single = 16'h0100; tb0.page_m0 = 16'h1000; tb0.page_m1 = 16'he000; tb0.conc = 16'h6000;
        tb1.single = 16'h0200; tb1.page_m0 = 16'h2000; tb1.page_m1 = 16'hf000; tb1.conc = 16'ha000;
    endfunction

    function void connect();
        tb0.m.connect(dut.s0);
        tb1.m.connect(dut.s1);
        dut.m0.connect(mem0.s);
        dut.m1.connect(mem1.s);
        // Up to 300 time units (ns) before each response: mem1 answers
        // late, so reads behind mem0 overtake reads behind mem1.
        // verilog-axi's crossbar does not accept interleaved R, so
        // r_interleave stays off.
        mem1.sub.max_delay = 300;
    endfunction
endclass
