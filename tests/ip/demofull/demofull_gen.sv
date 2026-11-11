// Pass 1: build and connect the description (nothing is bound to pins), then
// emit demo_sys.sv (the netlist) and demo_top_sim.sv into the run directory.
`include "fw_hdl_macros.svh"

module demofull_gen;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import demofull_ip_pkg::*;

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;

    `fw_root_begin(demo_top, u_root, clock, reset)
    `fw_root_end

    initial begin
        automatic fw_emitter e = new;
        automatic string imports[$] = '{"fw_proto_axi4_defs_pkg", "fw_proto_axi4_core_pkg",
                                        "fw_proto_axi4_core_pkg_woven", "demofull_ip_pkg"};
        repeat (2) @(posedge clock);
        reset = 1'b0;
        while (u_root.root == null || !u_root.root.elaborated) @(posedge clock);
        if (e.emit(u_root.root, "demo_top", imports) != 0)
            $fatal(1, "[demofull_gen] emit failed");
        $display("[demofull_gen] PASS");
        $finish;
    end
endmodule
