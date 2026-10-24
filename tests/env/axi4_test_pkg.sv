// Test environments. Tests use ONLY the API handles an env holds; which
// implementation sits behind them is the VIEW, chosen by which harness file
// (tests/env/<view>/axi4_l<N>_harness.sv) is compiled in.
package axi4_test_pkg;
    import fw_hdl_pkg::*;
    import axi4_types_pkg::*;
    import fw_proto_axi4_pkg::*;

    // The interface every test link uses (both views): narrow enough to
    // exercise masking, every USER signal present.
    localparam axi4_param_t AXI4_TEST_PARAM = '{
        ADDR_W: 32, DATA_W: 64, ID_W: 4,
        AWUSER_W: 2, WUSER_W: 3, BUSER_W: 1, ARUSER_W: 2, RUSER_W: 3};

    // What every env has: the interface configuration, a recorder of every
    // beat a monitor saw on the link, and the ready handshake with the tests.
    class axi4_env_base extends fw_component implements fw_runnable;
        static axi4_env_base inst;

        axi4_cfg cfg;
        bit      ready;
        // Monitors (pin monitors, in pin views) bind to fan.in; the fanout
        // feeds the recorder and whatever else an env subscribes. A view
        // with a monitor on the link sets `monitored`.
        axi4_mon_fanout   fan;
        axi4_mon_recorder mon;
        bit               monitored;

        function new(string name, fw_component parent);
            super.new(name, parent);
            cfg  = axi4_cfg::from_param(AXI4_TEST_PARAM);
            inst = this;
            add_runnable(this);
        endfunction

        function void build();
            fan = new("fan", this);
            mon = new("mon", this);
        endfunction

        function void connect();
            fan.subscribe(mon);
        endfunction

        // A view whose link needs bring-up (pins, reset) overrides this.
        virtual task link_up();
        endtask

        // Random stalls on the link: up to n idle cycles before each beat's
        // VALID (sending side) or READY (receiving side). A view with pins
        // overrides this; elsewhere it does nothing.
        virtual function void set_backpressure(int unsigned n);
        endfunction

        task run();
            link_up();
            ready = 1;
        endtask

        // Wait for the env to be built and its link up.
        static task wait_ready();
            while (inst == null || !inst.ready) #1;
        endtask

        virtual function bit idle();
            return 1;
        endfunction

        virtual function void clear();
            mon.clear();
        endfunction
    endclass

    // L1: scripted beat endpoints on both sides of the link.
    //   mgr (socket) <-- AXI4 link --> sub (mirror)
    class axi4_l1_env extends axi4_env_base;
        axi4_l1_mgr_ep mgr;
        axi4_l1_sub_ep sub;

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            super.build();
            mgr = new("mgr", this);
            sub = new("sub", this);
        endfunction

        virtual function bit idle();
            return mgr.idle() && sub.idle();
        endfunction

        virtual function void clear();
            super.clear();
            mgr.clear(); sub.clear();
        endfunction
    endclass

    // A trivial L2 target for the adapter suites: logs every transaction it
    // serves, answers reads with data_of(addr, beat) and every transaction
    // with `resp` (or err_resp inside [err_lo, err_hi]).
    class axi4_test_target extends fw_component;
        `FW_AXI4_XACT_IMP(axi4_test_target, xact);

        axi4_xact    seen[$];
        axi4_resp_e  resp = AXI4_RESP_OKAY;
        axi4_addr_t  err_lo = '1, err_hi = '0;
        axi4_resp_e  err_resp = AXI4_RESP_SLVERR;

        function new(string name, fw_component parent); super.new(name, parent); endfunction
        function void build(); xact = new(this); endfunction

        static function axi4_data_t data_of(axi4_addr_t addr, int unsigned n);
            return {16{addr[31:0] ^ (32'h9e37_79b9 * (n + 1))}};
        endfunction

        task xact_xact(axi4_xact x);
            x.resp = (x.addr >= err_lo && x.addr <= err_hi) ? err_resp : resp;
            if (!x.write)
                for (int unsigned n = 0; n < x.n_beats(); n++)
                    x.data.push_back(data_of(x.addr, n));
            seen.push_back(x);
        endtask
    endclass

    // L2: manager adapter -> link -> subordinate adapter -> test target.
    //   mgr.axi (socket) <-- AXI4 link --> sub.axi (mirror);  sub.tgt -> tgt
    class axi4_l2_env extends axi4_env_base;
        axi4_mgr_adapter mgr;
        axi4_sub_adapter sub;
        axi4_test_target tgt;

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            super.build();
            mgr = new("mgr", this, cfg);
            sub = new("sub", this, cfg);
            tgt = new("tgt", this);
        endfunction

        function void connect();
            super.connect();
            sub.tgt.connect(tgt.xact);
        endfunction

        function int unsigned n_errors();
            return mgr.n_errors + sub.n_errors;
        endfunction

        virtual function bit idle();
            return mgr.idle() && sub.idle() && n_errors() == 0;
        endfunction

        virtual function void clear();
            super.clear();
            tgt.seen.delete();
            tgt.resp = AXI4_RESP_OKAY;
            tgt.err_lo = '1; tgt.err_hi = '0;
            sub.max_delay = 0;
        endfunction
    endclass

    // L2 over memory: manager adapter -> link -> subordinate adapter ->
    // axi4_mem_model; fw_mem_if views of the manager in two widths:
    // m32 (narrow single beats) and m128 (two-beat bursts on the 64-bit bus).
    class axi4_mem_env extends axi4_env_base;
        axi4_mgr_adapter mgr;
        axi4_sub_adapter sub;
        axi4_mem_model   mem;
        axi4_to_mem #(logic [31:0], logic [31:0], logic [3:0])   m32;
        axi4_to_mem #(logic [31:0], logic [127:0], logic [15:0]) m128;

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            super.build();
            mgr  = new("mgr", this, cfg);
            sub  = new("sub", this, cfg);
            mem  = new("mem", this, cfg);
            m32  = new("m32", this, cfg);
            m128 = new("m128", this, cfg);
        endfunction

        function void connect();
            super.connect();
            sub.tgt.connect(mem.xact);
            m32.xact.connect(mgr.xact);
            m128.xact.connect(mgr.xact);
        endfunction

        virtual function bit idle();
            return mgr.idle() && sub.idle() && mgr.n_errors + sub.n_errors == 0;
        endfunction

        virtual function void clear();
            super.clear();
            mem.clear();
            sub.max_delay = 0;
        endfunction
    endclass

    // ---- beat generators. Every beat is random and pre-masked to the
    // configuration; address beats are legal bursts (A3.4.1).
    function automatic logic [1023:0] rand_bits();
        logic [1023:0] v;
        for (int i = 0; i < 32; i++) v[i*32 +: 32] = $urandom;
        return v;
    endfunction

    function automatic axi4_addr_beat_t rand_ax(axi4_cfg cfg, bit rd);
        axi4_addr_beat_t f = axi4_addr_beat_t'(rand_bits());
        do begin
            f.addr  = axi4_addr_t'({$urandom, $urandom});
            f.size  = axi4_size_e'($urandom_range($clog2(cfg.bus_bytes())));
            f.burst = axi4_burst_e'($urandom_range(2));
            f.len   = axi4_len_t'((f.burst == AXI4_BURST_WRAP)
                          ? (2 << $urandom_range(3)) - 1 : $urandom_range(15));
            f.lock  = 1'b0;
            f       = cfg.mask_ax(f, rd);
        end while (!axi4_burst_legal(f.addr, f.size, f.len, f.burst, cfg.bus_bytes()));
        return f;
    endfunction

    function automatic axi4_aw_beat_t rand_aw(axi4_cfg cfg);
        return rand_ax(cfg, 0);
    endfunction

    function automatic axi4_ar_beat_t rand_ar(axi4_cfg cfg);
        return rand_ax(cfg, 1);
    endfunction

    function automatic axi4_w_beat_t rand_w(axi4_cfg cfg);
        return cfg.mask_w(axi4_w_beat_t'(rand_bits()));
    endfunction

    function automatic axi4_b_beat_t rand_b(axi4_cfg cfg);
        return cfg.mask_b(axi4_b_beat_t'(rand_bits()));
    endfunction

    function automatic axi4_r_beat_t rand_r(axi4_cfg cfg);
        return cfg.mask_r(axi4_r_beat_t'(rand_bits()));
    endfunction

    // The byte lanes of beat n of x on a bus of bus_bytes (A3.4.4: WSTRB
    // may be HIGH only on these).
    function automatic axi4_strb_t beat_lanes(axi4_xact x, int unsigned n,
                                             int unsigned bus_bytes);
        int unsigned lo = axi4_beat_lower_lane(x.addr, x.size, x.len, x.burst, n, bus_bytes);
        int unsigned hi = axi4_beat_upper_lane(x.addr, x.size, x.len, x.burst, n, bus_bytes);
        axi4_strb_t  m  = '0;
        for (int unsigned i = lo; i <= hi; i++) m[i] = 1'b1;
        return m;
    endfunction

    // A random legal transaction (request half), pre-masked to cfg.
    function automatic axi4_xact rand_xact(axi4_cfg cfg, bit write);
        axi4_xact x = axi4_xact::from_ax(rand_ax(cfg, !write), write);
        if (write)
            for (int unsigned n = 0; n < x.n_beats(); n++) begin
                axi4_w_beat_t w = rand_w(cfg);
                x.data.push_back(w.data);
                x.strb.push_back(w.strb & beat_lanes(x, n, cfg.bus_bytes()));
                x.wuser.push_back(w.user);
            end
        return x;
    endfunction
endpackage
