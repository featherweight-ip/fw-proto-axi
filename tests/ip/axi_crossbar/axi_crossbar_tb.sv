// Pass 2: runs the emitted xbar_top_sim (axi_crossbar, four transactors, the
// run-time class tree) and checks it.
module axi_crossbar_tb;
    import fw_proto_pkg::*;
    import axi_crossbar_ip_pkg::*;
    import xbar_top_shells_pkg::*;

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;

    xbar_top_sim u_sim (.clock(clock), .reset(reset));

    // Out of order on slave port 0's pins: a read's last beat whose ID is not
    // the oldest outstanding read's.
    logic [3:0]  rd_open[$];
    int unsigned n_ooo = 0;
    always @(posedge clock) if (!reset) begin
        if (u_sim.dut_core_s0_arvalid && u_sim.dut_core_s0_arready)
            rd_open.push_back(u_sim.dut_core_s0_arid);
        if (u_sim.dut_core_s0_rvalid && u_sim.dut_core_s0_rready && u_sim.dut_core_s0_rlast) begin
            int k[$];
            // Assigned, not initialized: an initializer here would run once.
            k = rd_open.find_first_index(x) with (x == u_sim.dut_core_s0_rid);
            if (k.size() != 0) begin
                if (k[0] != 0) n_ooo++;
                rd_open.delete(k[0]);
            end
        end
    end

    initial begin
        automatic int errors = 0;
        automatic xbar_api_shell s;

        repeat (4) @(posedge clock);
        reset = 1'b0;
        while (u_sim.u_root.root == null || !u_sim.u_root.root.elaborated) @(posedge clock);
        if (!$cast(s, u_sim.u_root.root.dut)) begin
            $display("FAIL: dut is not xbar_api_shell");
            errors++;
        end else if (s.core != null) begin
            $display("FAIL: the shell built the RTL's description");
            errors++;
        end

        // Polled: Verilator evaluates a wait() expression eagerly.
        while (!u_sim.u_root.root.tb0.done || !u_sim.u_root.root.tb1.done) @(posedge clock);
        errors += u_sim.u_root.root.tb0.n_errors + u_sim.u_root.root.tb1.n_errors;
        errors += u_sim.u_root.root.mem0.sub.n_errors + u_sim.u_root.root.mem1.sub.n_errors;
        // ID widening: each memory saw bursts from both slave ports.
        foreach (u_sim.u_root.root.mem0.mem.n_by_top[t])
            if (u_sim.u_root.root.mem0.mem.n_by_top[t] == 0
                    || u_sim.u_root.root.mem1.mem.n_by_top[t] == 0) begin
                $display("FAIL: a memory saw no burst with ID top bit %0d (mem0 %0d/%0d, mem1 %0d/%0d)", t,
                         u_sim.u_root.root.mem0.mem.n_by_top[0], u_sim.u_root.root.mem0.mem.n_by_top[1],
                         u_sim.u_root.root.mem1.mem.n_by_top[0], u_sim.u_root.root.mem1.mem.n_by_top[1]);
                errors++;
                break;
            end
        if (n_ooo == 0) begin
            $display("FAIL: no read completed out of order on s0");
            errors++;
        end
        $display("[axi_crossbar] checks=%0d errors=%0d out_of_order=%0d mem0=%0d/%0d mem1=%0d/%0d",
                 u_sim.u_root.root.tb0.n_checks + u_sim.u_root.root.tb1.n_checks, errors, n_ooo,
                 u_sim.u_root.root.mem0.mem.n_by_top[0], u_sim.u_root.root.mem0.mem.n_by_top[1],
                 u_sim.u_root.root.mem1.mem.n_by_top[0], u_sim.u_root.root.mem1.mem.n_by_top[1]);
        if (errors == 0) $display("[axi_crossbar] PASS");
        else             $fatal(1, "[axi_crossbar] FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #10ms;
        $display("[axi_crossbar] stuck: tb0 mgr idle %0b waiting %0d; tb1 mgr idle %0b waiting %0d",
                 u_sim.u_root.root.tb0.mgr.idle(), u_sim.u_root.root.tb0.blk.n_waiting,
                 u_sim.u_root.root.tb1.mgr.idle(), u_sim.u_root.root.tb1.blk.n_waiting);
        $display("[axi_crossbar] stuck: mem0 %s", u_sim.u_root.root.mem0.sub.state());
        $display("[axi_crossbar] stuck: mem1 %s", u_sim.u_root.root.mem1.sub.state());
        $display("[axi_crossbar] stuck: s0 aw %b%b w %b%b b %b%b ar %b%b r %b%b; s1 aw %b%b w %b%b b %b%b ar %b%b r %b%b",
                 u_sim.dut_core_s0_awvalid, u_sim.dut_core_s0_awready, u_sim.dut_core_s0_wvalid,
                 u_sim.dut_core_s0_wready, u_sim.dut_core_s0_bvalid, u_sim.dut_core_s0_bready,
                 u_sim.dut_core_s0_arvalid, u_sim.dut_core_s0_arready, u_sim.dut_core_s0_rvalid,
                 u_sim.dut_core_s0_rready,
                 u_sim.dut_core_s1_awvalid, u_sim.dut_core_s1_awready, u_sim.dut_core_s1_wvalid,
                 u_sim.dut_core_s1_wready, u_sim.dut_core_s1_bvalid, u_sim.dut_core_s1_bready,
                 u_sim.dut_core_s1_arvalid, u_sim.dut_core_s1_arready, u_sim.dut_core_s1_rvalid,
                 u_sim.dut_core_s1_rready);
        $display("[axi_crossbar] stuck: m0 aw %b%b w %b%b b %b%b ar %b%b r %b%b; m1 aw %b%b w %b%b b %b%b ar %b%b r %b%b",
                 u_sim.dut_core_m0_awvalid, u_sim.dut_core_m0_awready, u_sim.dut_core_m0_wvalid,
                 u_sim.dut_core_m0_wready, u_sim.dut_core_m0_bvalid, u_sim.dut_core_m0_bready,
                 u_sim.dut_core_m0_arvalid, u_sim.dut_core_m0_arready, u_sim.dut_core_m0_rvalid,
                 u_sim.dut_core_m0_rready,
                 u_sim.dut_core_m1_awvalid, u_sim.dut_core_m1_awready, u_sim.dut_core_m1_wvalid,
                 u_sim.dut_core_m1_wready, u_sim.dut_core_m1_bvalid, u_sim.dut_core_m1_bready,
                 u_sim.dut_core_m1_arvalid, u_sim.dut_core_m1_arready, u_sim.dut_core_m1_rvalid,
                 u_sim.dut_core_m1_rready);
        $fatal(1, "[axi_crossbar] TIMEOUT");
    end
endmodule
