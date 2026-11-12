// The tests: the l2_mem scenarios that apply to a plain RAM (no error
// ranges, no exclusive access; axi_ram treats WRAP as INCR), checked
// against axi4_mem_model as the reference (ip_axi_tb).
class ram_tb extends ip_axi_tb #(P);
    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    virtual task tests();
        single_write_read(16'h0100);
        random_bursts(16'h1000, 40);
        concurrent_ids(16'h4000, 4, 10);
    endtask
endclass
