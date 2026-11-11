    // --------------------------------------------------------------
    // Sink: PROVIDES the fw_rv_target_if implementation. P1 pilot: the
    // export's implementation is the generated fw_rv_target_if_imp, which
    // forwards put() to this class, instead of `FW_RV_TARGET_IMP's nested
    // class forwarding to in_put(). Otherwise identical to fw-hdl's sink.svh.
    // --------------------------------------------------------------
    class sink extends fw_component;
        data_t received[$];

        fw_export #(fw_rv_target_if #(data_t)) in;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            fw_rv_target_if_imp #(data_t, sink) imp = new(this);
            in = new("in", this, imp);
        endfunction

        // Much slower than the pins (100ns a beat; one transfer takes about
        // 30ns), so the target's FIFO fills and ready drops on the pins.
        virtual task put(input data_t t);
            #100ns;
            received.push_back(t);
            $display("[sink]    put  0x%0h @ %0t", t, $time);
        endtask
    endclass
