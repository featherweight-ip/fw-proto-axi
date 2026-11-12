// Pass 2: runs the emitted demo_top_sim (demofull, the transactor, the
// run-time class tree) and checks it.
module demofull_tb;
    import fw_proto_pkg::*;
    import demofull_ip_pkg::*;
    import ip_axi_tb_pkg::*;
    import demo_top_shells_pkg::*;

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;

    demo_top_sim u_sim (.clock(clock), .reset(reset));

    // The emitted reset is active high; demofull's is active low. Counted on
    // the IP's own pin: reset must reach it inverted.
    int unsigned rst_low = 0;
    always @(posedge clock) if (reset && !u_sim.u_dut_core.slv.S_AXI_ARESETN) rst_low++;

    // The AXI4 rules on the abstractor, by its path (no capacity declared).
    ip_axi_rules #(P) rules = new;
    initial rules.at("dut.s_abs");

    initial begin
        automatic int errors = 0;
        automatic demo_api_shell s;

        repeat (4) @(posedge clock);
        reset = 1'b0;
        while (u_sim.u_root.root == null || !u_sim.u_root.root.elaborated) @(posedge clock);
        if (!$cast(s, u_sim.u_root.root.dut)) begin
            $display("FAIL: dut is not demo_api_shell");
            errors++;
        end else if (s.core != null) begin
            $display("FAIL: the shell built the RTL's description");
            errors++;
        end
        if (rst_low == 0) begin
            $display("FAIL: S_AXI_ARESETN was never low during reset");
            errors++;
        end

        // Polled: Verilator evaluates a wait() expression eagerly.
        while (!u_sim.u_root.root.tb.done) @(posedge clock);
        errors += u_sim.u_root.root.tb.n_errors;
        errors += rules.check("demofull");
        $display("[demofull] checks=%0d errors=%0d", u_sim.u_root.root.tb.n_checks, errors);
        if (errors == 0) $display("[demofull] PASS");
        else             $fatal(1, "[demofull] FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #5ms;
        $fatal(1, "[demofull] TIMEOUT");
    end
endmodule
