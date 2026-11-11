// wb2axip demofull behind the AXI4 class API (plan P6.4): upper-case pin
// names (S_AXI_AWADDR), an active-low reset, and a non-AXI memory port
// (o_we ... o_raddr out, i_rdata in) that is not part of the bundle.
//
//   demo_top
//   +-- dut : demo_api              (class: an axi4_sub_socket)
//   |   +-- core : demo_sys         (RTL structural: emitted as module demo_sys)
//   |   |   +-- slv : demofull_rtl  (extern: demofull)
//   |   +-- s_abs                   abstractor, inserted by core.s.connect(s)
//   +-- tb : demo_tb
//
// The memory port: the outputs are left open and i_rdata is tied to RDATA, so
// every read returns RDATA and writes go nowhere. The tests check the AXI side:
// responses, IDs, beat counts, and the tied value on every active lane.
`include "fw_hdl_macros.svh"

package demofull_ip_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;
    import ip_axi_tb_pkg::*;

    // demofull's pins: QOS but no REGION, no USER.
    localparam axi4_param_t P = '{ADDR_W: 16, DATA_W: 32, ID_W: 4,
                                  AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
                                  HAS_QOS: 1, HAS_REGION: 0};
    localparam logic [31:0] RDATA = 32'h5a5a_5a5a;

    class demofull_rtl extends fw_extern_component;
        axi4_sub_sp #(P) s;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        virtual function string extern_module(); return "demofull"; endfunction

        function void build();
            s = new("s", this);
        endfunction

        virtual function void extern_map(fw_extern_map x);
            x.param("C_S_AXI_ID_WIDTH", P.ID_W);
            x.param("C_S_AXI_DATA_WIDTH", P.DATA_W);
            x.param("C_S_AXI_ADDR_WIDTH", P.ADDR_W);
            x.clock("S_AXI_ACLK");
            x.reset("S_AXI_ARESETN", .active_low(1));
            x.prefix(s, "S_AXI_").upper();
            // Not AXI: the memory port.
            x.tie("i_rdata", RDATA);
            x.open("o_we");
            x.open("o_waddr");
            x.open("o_wdata");
            x.open("o_wstrb");
            x.open("o_rd");
            x.open("o_raddr");
        endfunction
    endclass

    class demo_sys extends fw_rtl_structural;
        axi4_sub_sp #(P) s;
        demofull_rtl     slv;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        virtual function string module_name(); return "demo_sys"; endfunction

        function void build();
            s   = new("s", this);
            slv = new("slv", this);
        endfunction

        function void connect();
            s.bind_inner(slv.s);
        endfunction
    endclass

    class demo_api extends fw_component;
        axi4_sub_socket #(P) s;
        demo_sys             core;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            s    = new("s", this);
            core = new("core", this);
        endfunction

        function void connect();
            void'(core.s.connect(s));
        endfunction
    endclass
    typedef fw_proto_reg #(demo_api, "demo_api") demo_api_reg;

    class demo_tb extends ip_axi_tb #(P);
        function new(string name, fw_component parent);
            super.new(name, parent);
            const_rdata = 1;
            rdata_value = RDATA;
            use_wrap    = 1;
        endfunction

        virtual task tests();
            single_write_read(16'h0100);
            random_bursts(16'h1000, 40);
            concurrent_ids(16'h4000, 4, 10);
        endtask
    endclass

    class demo_top extends fw_component;
        demo_api dut;
        demo_tb  tb;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            dut = demo_api_reg::create("dut", this);
            tb  = new("tb", this);
        endfunction

        function void connect();
            tb.m.connect(dut.s);
        endfunction
    endclass
endpackage
