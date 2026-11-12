// ------------------------------------------------------------------
// Scripted endpoints
// ------------------------------------------------------------------
// One inbound channel of a scripted endpoint: a queue the endpoint's
// channel method fills and a test drains. `stall` makes the method block
// (at pin level, the receiver holding READY low), which is how a test
// holds one channel while checking that the others still flow.
class fw_inbox #(type T = int);
    T            q[$];
    bit          stall;
    int unsigned n_recv;

    task put(input T f);
        wait (!stall);
        q.push_back(f);
        n_recv++;
    endtask

    // Blocking receive, for a test.
    task get(output T f);
        wait (q.size() > 0);
        f = q.pop_front();
    endtask

    function int size();
        return q.size();
    endfunction

    function void clear();
        q.delete();
        stall  = 0;
        n_recv = 0;
    endfunction
endclass
