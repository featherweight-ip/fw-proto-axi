// Pass 2: runs the emitted ram_top_sim (axi_ram, the transactor, the run-time
// class tree) and checks what the description promised.
module axi_ram_tb;
    import fw_proto_pkg::*;
    import axi_ram_ip_pkg::*;
    import ip_axi_tb_pkg::*;
    import ram_top_shells_pkg::*;

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;

    ram_top_sim u_sim (.clock(clock), .reset(reset));

    // Stalls set by path (+max_gap=N, default 8): the abstractor's B and R
    // transactors hold READY low at random. Counted on axi_ram's own pins. Only
    // R must show them: the rv target core's one-deep buffer takes a lone B
    // beat while the knob holds its up-link, so B stalls on the pins only when
    // B beats queue up.
    int unsigned max_gap = 8;
    int unsigned r_stalls = 0, b_stalls = 0, r_beats = 0;
    // The AXI4 rules on the abstractor, by its path (no capacity declared).
    ip_axi_rules #(P) rules = new;
    initial begin
        rules.at("dut.s_abs");
        void'($value$plusargs("max_gap=%d", max_gap));
        fw_proto_cfg::set_int("dut.s_abs", "r.max_gap", max_gap);
        fw_proto_cfg::set_int("dut.s_abs", "b.max_gap", max_gap);
    end
    always @(posedge clock) if (!reset) begin
        if (u_sim.dut_core_s_rvalid && !u_sim.dut_core_s_rready) r_stalls++;
        if (u_sim.dut_core_s_rvalid && u_sim.dut_core_s_rready) r_beats++;
        if (u_sim.dut_core_s_bvalid && !u_sim.dut_core_s_bready) b_stalls++;
    end

    initial begin
        automatic int errors = 0;
        automatic ram_api_shell s;

        repeat (4) @(posedge clock);
        reset = 1'b0;
        while (u_sim.u_root.root == null || !u_sim.u_root.root.elaborated) @(posedge clock);

        // Implementation in one place: dut is the shell, and the description
        // of what the module tree implements was never built.
        if (!$cast(s, u_sim.u_root.root.dut)) begin
            $display("FAIL: dut is not ram_api_shell");
            errors++;
        end else if (s.core != null) begin
            $display("FAIL: the shell built the RTL's description");
            errors++;
        end

        // Polled: Verilator evaluates a wait() expression eagerly, before root.tb exists.
        while (!u_sim.u_root.root.tb.done) @(posedge clock);
        errors += u_sim.u_root.root.tb.n_errors;
        errors += rules.check("axi_ram");
        // Without the knob the transactor's own buffering stalls R less than
        // one cycle per beat; a random gap of 0..max_gap adds max_gap/2 a beat.
        if (max_gap >= 8 && r_stalls < 2 * r_beats) begin
            $display("FAIL: max_gap set on dut.s_abs did not reach the pins (%0d R stalls, %0d beats)",
                     r_stalls, r_beats);
            errors++;
        end
        $display("[axi_ram] checks=%0d errors=%0d r_beats=%0d r_stalls=%0d b_stalls=%0d",
                 u_sim.u_root.root.tb.n_checks, errors, r_beats, r_stalls, b_stalls);
        if (errors == 0) $display("[axi_ram] PASS");
        else             $fatal(1, "[axi_ram] FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #5ms;
        $fatal(1, "[axi_ram] TIMEOUT");
    end
endmodule
