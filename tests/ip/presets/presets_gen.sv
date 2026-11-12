// Pass 1 only: build and connect the description, then emit the netlists
// (preset_<tag>_sys.sv) into the run directory. presets.py lints them.
`include "fw_hdl_macros.svh"

module presets_gen;
    import fw_hdl_pkg::*;
    import fw_proto_pkg::*;
    import presets_ip_pkg::*;

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;

    `fw_root_begin(presets_top, u_root, clock, reset)
    `fw_root_end

    initial begin
        automatic fw_emitter e = new;
        automatic string imports[$] = '{"fw_proto_axi4_defs_pkg", "fw_proto_axi4_core_pkg",
                                        "fw_proto_axi4_core_pkg_woven", "presets_ip_pkg"};
        repeat (2) @(posedge clock);
        reset = 1'b0;
        while (u_root.root == null || !u_root.root.elaborated) @(posedge clock);
        if (e.emit(u_root.root, "presets_top", imports) != 0)
            $fatal(1, "[presets_gen] emit failed");
        $display("[presets_gen] PASS");
        $finish;
    end
endmodule
