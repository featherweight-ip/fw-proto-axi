// verilog-axi axi_crossbar (2x2) behind the AXI4 class API (plan P6.4): ports
// in slots of packed-vector pins, ID widening, out-of-order responses.
//
//   xbar_top
//   +-- dut : xbar_api                (class: two axi4_sub_sockets, two axi4_mgr_sockets)
//   |   +-- core : xbar_sys           (RTL structural: emitted as module xbar_sys)
//   |   |   +-- xbar : xbar_rtl       (extern: axi_crossbar, S_COUNT = M_COUNT = 2)
//   |   +-- s0_abs, s1_abs            manager abstractors (core.s<i>.connect(s<i>))
//   |   +-- m0_abs, m1_abs            subordinate abstractors (core.m<i>.connect(m<i>))
//   +-- tb0, tb1 : xbar_tb            (managers, on dut.s0 and dut.s1, at once)
//   +-- mem0, mem1 : ip_axi_mem       (memories, on dut.m0 and dut.m1)
//
// The address map: m0 is 0x0000-0x7fff, m1 0x8000-0xffff (M_ADDR_WIDTH 15 each).
// The master ports' IDs are one bit wider: the crossbar adds the slave port.
`include "fw_hdl_macros.svh"

package axi_crossbar_ip_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;
    import ip_axi_tb_pkg::*;

    // Slave ports: QOS, no REGION. Master ports: QOS and REGION, one more ID bit.
    localparam axi4_param_t PS = '{ADDR_W: 16, DATA_W: 32, ID_W: 4,
                                   AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
                                   HAS_QOS: 1, HAS_REGION: 0};
    localparam axi4_param_t PM = '{ADDR_W: 16, DATA_W: 32, ID_W: 5,
                                   AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
                                   HAS_QOS: 1, HAS_REGION: 1};

    class xbar_rtl extends fw_extern_component;
        axi4_sub_sp #(PS) s0, s1;
        axi4_mgr_sp #(PM) m0, m1;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        virtual function string extern_module(); return "axi_crossbar"; endfunction

        function void build();
            s0 = new("s0", this);
            s1 = new("s1", this);
            m0 = new("m0", this);
            m1 = new("m1", this);
        endfunction

        virtual function void extern_map(fw_extern_map x);
            x.param("S_COUNT", 2);
            x.param("M_COUNT", 2);
            x.param("DATA_WIDTH", PS.DATA_W);
            x.param("ADDR_WIDTH", PS.ADDR_W);
            x.param("S_ID_WIDTH", PS.ID_W);
            x.param("M_ADDR_WIDTH", 64'h0000_000f_0000_000f);   // {32'd15, 32'd15}
            x.clock("clk");
            x.reset("rst");
            // Each port is one slot of the packed pins.
            x.prefix(s0, "s_axi_").slot(0);
            x.prefix(s1, "s_axi_").slot(1);
            x.prefix(m0, "m_axi_").slot(0);
            x.prefix(m1, "m_axi_").slot(1);
            // USER is off (*USER_ENABLE = 0); its pins are still there.
            x.tie("s_axi_awuser", 0);
            x.tie("s_axi_wuser", 0);
            x.tie("s_axi_aruser", 0);
            x.tie("m_axi_buser", 0);
            x.tie("m_axi_ruser", 0);
            x.open("s_axi_buser");
            x.open("s_axi_ruser");
            x.open("m_axi_awuser");
            x.open("m_axi_wuser");
            x.open("m_axi_aruser");
        endfunction
    endclass

    class xbar_sys extends fw_rtl_structural;
        axi4_sub_sp #(PS) s0, s1;
        axi4_mgr_sp #(PM) m0, m1;
        xbar_rtl          xbar;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        virtual function string module_name(); return "xbar_sys"; endfunction

        function void build();
            s0   = new("s0", this);
            s1   = new("s1", this);
            m0   = new("m0", this);
            m1   = new("m1", this);
            xbar = new("xbar", this);
        endfunction

        function void connect();
            s0.bind_inner(xbar.s0);
            s1.bind_inner(xbar.s1);
            m0.bind_inner(xbar.m0);
            m1.bind_inner(xbar.m1);
        endfunction
    endclass

    class xbar_api extends fw_component;
        axi4_sub_socket #(PS) s0, s1;
        axi4_mgr_socket #(PM) m0, m1;
        xbar_sys              core;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            s0   = new("s0", this);
            s1   = new("s1", this);
            m0   = new("m0", this);
            m1   = new("m1", this);
            core = new("core", this);
        endfunction

        function void connect();
            void'(core.s0.connect(s0));
            void'(core.s1.connect(s1));
            void'(core.m0.connect(m0));
            void'(core.m1.connect(m1));
        endfunction
    endclass
    typedef fw_proto_reg #(xbar_api, "xbar_api") xbar_api_reg;

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

    class xbar_top extends fw_component;
        xbar_api          dut;
        xbar_tb           tb0, tb1;
        ip_axi_mem #(PM)  mem0, mem1;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            dut  = xbar_api_reg::create("dut", this);
            tb0  = new("tb0", this);
            tb1  = new("tb1", this);
            mem0 = new("mem0", this);
            mem1 = new("mem1", this);
            tb0.single = 16'h0100; tb0.page_m0 = 16'h1000; tb0.page_m1 = 16'he000; tb0.conc = 16'h6000;
            tb1.single = 16'h0200; tb1.page_m0 = 16'h2000; tb1.page_m1 = 16'hf000; tb1.conc = 16'ha000;
        endfunction

        function void connect();
            tb0.m.connect(dut.s0);
            tb1.m.connect(dut.s1);
            dut.m0.connect(mem0.s);
            dut.m1.connect(mem1.s);
            // Up to 300 time units (ns) before each response: mem1 answers
            // late, so reads behind mem0 overtake reads behind mem1.
            // verilog-axi's crossbar does not accept interleaved R, so
            // r_interleave stays off.
            mem1.sub.max_delay = 300;
        endfunction
    endclass
endpackage
