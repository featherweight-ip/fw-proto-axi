// The AXI4 rules (plan P7) on inserted abstractors, attached by path through
// axi4_observers: at(path) before the run, one rule set per path (events at the
// abstractor's proxies). check() reports what failed, and any path no
// abstractor took; it returns the number of problems.
class ip_axi_rules #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    axi4_rules #(P) sets[$];

    // max_wr / max_rd: the port's declared capacity (0: none declared).
    function void at(string path, int unsigned max_wr = 0, int unsigned max_rd = 0);
        axi4_rules #(P) r = new(path, 0, max_wr, max_rd);
        sets.push_back(r);
        axi4_observers #(P)::add(path, r.req, r.rsp);
    endfunction

    function int unsigned check(string tag);
        int unsigned n = 0;
        string u = axi4_observers #(P)::unused();
        if (u != "") begin
            $display("[%s] FAIL: rules registered for %s, but no abstractor took them", tag, u);
            n++;
        end
        foreach (sets[i]) begin
            if (sets[i].n_fail() != 0) begin
                $display("[%s] FAIL: rules on %s: %s", tag, sets[i].where, sets[i].failed());
                n++;
            end
            $display("[%s] rules on %s: %0d failures, %0d rule instances", tag, sets[i].where,
                     sets[i].n_fail(), sets[i].n_inst());
        end
        return n;
    endfunction
endclass
