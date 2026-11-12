// A memory component: the subordinate adapter over ip_axi_id_mem, behind an
// axi4_sub_socket. max_delay (time units) delays its responses at random,
// so responses for different IDs come back out of order.
class ip_axi_mem #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_component
        implements fw_runnable;
    axi4_sub_socket #(P)  s;
    axi4_sub_adapter #(P) sub;
    ip_axi_id_mem #(P)    mem;

    function new(string name, fw_component parent);
        super.new(name, parent);
        parent.add_runnable(this);
    endfunction

    function void build();
        mem = new();
        sub = new(null, mem);
        mem.rsp = sub;
        s   = new("s", this, sub);
    endfunction

    virtual task run();
        sub.rsp = s.t;
    endtask
endclass
