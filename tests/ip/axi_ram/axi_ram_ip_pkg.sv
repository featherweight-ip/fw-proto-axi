// verilog-axi axi_ram behind the AXI4 class API (plan P6.4).
//
// The description, written once:
//
//   ram_top                        (class: the testbench root)
//   +-- dut : ram_api              (class: the RAM behind an axi4_sub_socket)
//   |   +-- core : ram_sys         (RTL structural: emitted as module ram_sys)
//   |   |   +-- ram : axi_ram_rtl  (extern: axi_ram, one pin-map line)
//   |   +-- s_abs                  abstractor, inserted by core.s.connect(s)
//   +-- tb : ram_tb                (class: an axi4_mgr_socket; the tests)
//
// Pass 1 (ip_gen) builds this and emits ram_sys.sv and ram_top_sim.sv. Pass 2
// (axi_ram_tb) runs the emitted files: dut is then ram_api_shell, whose s is
// bound to the s_abs handle and the axi4_mgr_xtor in the module tree.
`include "fw_hdl_macros.svh"

package axi_ram_ip_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import fw_proto_axi4_defs_pkg::*;
    import fw_proto_axi4_core_pkg::*;
    import fw_proto_axi4_core_pkg_woven::*;
    import fw_proto_axi4_behav_pkg::*;
    import ip_axi_tb_pkg::*;

    // axi_ram's pins: no QOS, REGION or USER.
    localparam axi4_param_t P = '{ADDR_W: 16, DATA_W: 32, ID_W: 8,
                                  AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
                                  HAS_QOS: 0, HAS_REGION: 0};

    // ------------------------------------------------------------------
    // The description
    // ------------------------------------------------------------------
    class axi_ram_rtl extends fw_extern_component;
        axi4_sub_sp #(P) s;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        virtual function string extern_module(); return "axi_ram"; endfunction

        function void build();
            s = new("s", this);
        endfunction

        virtual function void extern_map(fw_extern_map x);
            x.param("DATA_WIDTH", P.DATA_W);
            x.param("ADDR_WIDTH", P.ADDR_W);
            x.param("ID_WIDTH", P.ID_W);
            x.clock("clk");
            x.reset("rst");
            x.prefix(s, "s_axi_");
        endfunction
    endclass

    class ram_sys extends fw_rtl_structural;
        axi4_sub_sp #(P) s;
        axi_ram_rtl      ram;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        virtual function string module_name(); return "ram_sys"; endfunction

        function void build();
            s   = new("s", this);
            ram = new("ram", this);
        endfunction

        function void connect();
            s.bind_inner(ram.s);
        endfunction
    endclass

    class ram_api extends fw_component;
        axi4_sub_socket #(P) s;
        ram_sys              core;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            s    = new("s", this);
            core = new("core", this);
        endfunction

        function void connect();
            // Method endpoint to struct port: the bundle inserts the abstractor.
            void'(core.s.connect(s));
        endfunction
    endclass
    typedef fw_proto_reg #(ram_api, "ram_api") ram_api_reg;

    // The tests: the l2_mem_ns scenarios that apply to a plain RAM (no error
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

    class ram_top extends fw_component;
        ram_api dut;
        ram_tb  tb;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            // dut before tb: tb.m resolves through dut.s, whose imp dut's
            // connect() sets (fw-hdl resolves child by child).
            dut = ram_api_reg::create("dut", this);
            tb  = new("tb", this);
        endfunction

        function void connect();
            tb.m.connect(dut.s);
        endfunction
    endclass
endpackage
