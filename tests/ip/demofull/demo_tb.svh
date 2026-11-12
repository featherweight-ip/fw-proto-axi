class demo_tb extends ip_axi_tb #(P);
    function new(string name, fw_component parent);
        super.new(name, parent);
        const_rdata = 1;
        rdata_value = RDATA;
        use_wrap    = 1;
    endfunction

    virtual task tests();
        single_write_read(16'h0100);
        random_bursts(16'h1000, 40);
        concurrent_ids(16'h4000, 4, 10);
    endtask
endclass
