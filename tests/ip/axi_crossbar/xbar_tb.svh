// A manager. Its pages are its own (the other manager's writes would make
// its reference wrong), on both sides of the address map.
class xbar_tb extends ip_axi_tb #(PS);
    addr_t single, page_m0, page_m1, conc;

    function new(string name, fw_component parent);
        super.new(name, parent);
        use_wrap = 1;
    endfunction

    virtual task tests();
        single_write_read(single);
        random_bursts(page_m0, 20);
        random_bursts(page_m1, 20);
        // Four IDs over four pages, two behind each memory: the responses
        // of different IDs come back out of order.
        concurrent_ids(conc, 4, 10);
    endtask
endclass
