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

    // What every env has: the interface configuration and the ready
    // handshake with the tests.
    class axi4_env_base extends fw_component implements fw_runnable;
        static axi4_env_base inst;

        axi4_cfg cfg;
        bit      ready;

        function new(string name, fw_component parent);
            super.new(name, parent);
            cfg  = axi4_cfg::from_param(AXI4_TEST_PARAM);
            inst = this;
            add_runnable(this);
        endfunction

        // A view whose link needs bring-up (pins, reset) overrides this.
        virtual task link_up();
        endtask

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
        endfunction
    endclass

    // L1: scripted beat endpoints on both sides of the link.
    //   mgr (socket) <-- AXI4 link --> sub (mirror)
    class axi4_l1_env extends axi4_env_base;
        axi4_l1_mgr_ep mgr;
        axi4_l1_sub_ep sub;

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            mgr = new("mgr", this);
            sub = new("sub", this);
        endfunction

        virtual function bit idle();
            return mgr.idle() && sub.idle();
        endfunction

        virtual function void clear();
            mgr.clear(); sub.clear();
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
endpackage
