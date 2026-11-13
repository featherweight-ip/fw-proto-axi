// Pass 1: build and connect the description (nothing is bound to pins), then
// emit ram_sys.sv (the netlist) and ram_top_sim.sv into the run directory.
`include "fw_hdl_macros.svh"

module axi_ram_gen;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import axi_ram_ip_pkg::*;

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;

    `fw_root_begin(ram_top, u_root, clock, reset)
    `fw_root_end

    // +emit_neg_soft_reset: the negative case (docs/design-domains.md §9, D8).
    // The same description with `dut` in a register-bit reset domain: the sim
    // top has nets for the root domains only, so emit() must refuse it, naming
    // the abstractor and the domain. fw_root is held in reset; this tree is
    // seated by hand.
    class ram_top_soft extends ram_top;
        fw_reg_block #(32)        rf;
        fw_reg #(bit [31:0])      ctrl;
        fw_reg_reset_domain #(32) srst;
        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction
        function void build();
            super.build();
            rf   = new("rf", this);
            ctrl = new("ctrl", rf);
            srst = new("srst", this, ctrl, 0);
        endfunction
        function void connect();
            super.connect();
            srst.src.connect(this.reset);
            dut.reset.connect(srst);
            dut.waive_crossing("s", FW_DOMAIN_RESET, "negative emitter test");
            tb.waive_crossing("m", FW_DOMAIN_RESET, "negative emitter test");
        endfunction
    endclass

    fw_clock_xtor_if u_ck(.clock(clock), .reset(1'b0));
    fw_reset_xtor_if u_rs(.clock(clock), .reset(1'b0));

    task automatic neg_soft_reset(string imports[$]);
        fw_component_root #(ram_top_soft) r = new("ram_top");
        fw_clock_xtor_bridge ck = new("clock", r, u_ck);
        fw_reset_xtor_bridge rs = new("reset", r, u_rs);
        fw_emitter e = new;
        bit named = 0;
        rs.clk.connect(ck);
        r.clock.connect(ck);
        r.reset.connect(rs);
        fork r.start(); join_none
        while (!r.elaborated) @(posedge clock);
        e.m_dir = "neg";
        void'($system("mkdir -p neg"));
        if (e.emit(r, "ram_top", imports) == 0)
            $fatal(1, "[axi_ram_gen] emit accepted an abstractor in a register-bit reset domain");
        foreach (e.m_errs[i])
            if (e.m_errs[i] == {"dut.s_abs: in reset domain ram_top.srst, not the root's; the emitted",
                                " sim top has nets for the root clock and reset only"}) named = 1;
        if (!named) $fatal(1, "[axi_ram_gen] the domain error does not name dut.s_abs and ram_top.srst");
        $display("[axi_ram_gen] PASS (negative: rejected by name)");
        $finish;
    endtask

    initial begin
        automatic fw_emitter e = new;
        automatic string imports[$] = '{"fw_proto_axi4_defs_pkg", "fw_proto_axi4_core_pkg",
                                        "fw_proto_axi4_core_pkg_woven", "axi_ram_ip_pkg"};
        if ($test$plusargs("emit_neg_soft_reset")) begin
            neg_soft_reset(imports);
        end
        repeat (2) @(posedge clock);
        reset = 1'b0;
        while (u_root.root == null || !u_root.root.elaborated) @(posedge clock);
        if (e.emit(u_root.root, "ram_top", imports) != 0)
            $fatal(1, "[axi_ram_gen] emit failed");
        $display("[axi_ram_gen] PASS");
        $finish;
    end
endmodule
