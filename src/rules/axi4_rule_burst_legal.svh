// Burst legality (brief §5), immediate on AW and AR: A3.4.1 (burst type, transfer
// size against the bus, FIXED/WRAP length, WRAP length and alignment, no 4KB
// crossing) and, for an exclusive access, A7.2.4 (at most 16 beats, 1 to 128
// bytes in all, a power of two, the address aligned to it). Binds the manager.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_burst_legal #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    function new();
        super.new("burst_legal");
    endfunction

    virtual function fw_rule create();
        axi4_rule_burst_legal #(P) r = new;
        return r;
    endfunction

    function void check(string ch, logic [w1(P.ID_W)-1:0] id, axi4_addr64_t addr,
                        axi4_size_e size, logic [7:0] len, axi4_burst_e burst, logic lock);
        string why = burst_why(addr, size, len, burst);
        if (why == "" && lock && !axi4_excl_legal(addr, size, len))
            why = "exclusive access not 1-128 bytes, a power of two, aligned, at most 16 beats";
        if (why != "")
            void'(chk(0, $sformatf("%s id=%0h addr=%0h len=%0d size=%0d burst=%0d lock=%0d: %s",
                                   ch, id, addr, len, size, burst, lock, why)));
    endfunction

    virtual function void on_aw(aw_t t);
        check("aw", t.id, axi4_addr64_t'(t.addr), t.size, t.len, t.burst, t.lock);
    endfunction

    virtual function void on_ar(ar_t t);
        check("ar", t.id, axi4_addr64_t'(t.addr), t.size, t.len, t.burst, t.lock);
    endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
