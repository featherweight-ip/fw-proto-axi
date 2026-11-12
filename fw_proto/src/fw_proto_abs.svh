    // ==================================================================
    // Describing a design as a class tree and realizing it (design §4.5;
    // ported from fw-hdl-sv-weave tests/abstractor_proto/abs_lib.svh, see
    // docs/p6-abstractors.md). Included in fw_proto_pkg. Names no protocol:
    // the abstractors of a protocol are generated from its bundle.
    //
    // The class tree a designer assembles is a description. Each component's
    // implementation ends up in exactly one place:
    //   - module tree: extern components (existing modules) and RTL structural
    //     components (assemblies of RTL linked by struct ports);
    //   - class tree:  ordinary class components.
    // Abstractors are boundary objects: an API in the class tree, a
    // transactor in the module tree.
    //
    // fw_emitter reads the description and writes:
    //   <module>.sv   one module per RTL structural class; its struct ports are
    //                 its pins. This is the netlist.
    //   <top>_sim.sv  a package of API shells, and a module holding the RTL,
    //                 one transactor per abstractor, and the run-time root.
    // At run time a class that wraps RTL is replaced, through the factory, by
    // its API shell: a subclass that builds only its API endpoints and binds
    // them to transactor handles.
    // ==================================================================

    `include "fw_proto_cfg.svh"

    // ------------------------------------------------------------------
    // A stand-in factory (fw-hdl's fw_factory.svh is not in fw_hdl_pkg yet).
    // ------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */      // a prototype's arguments
    `include "fw_proto_ctor.svh"
    /* verilator lint_on UNUSEDSIGNAL */

    `include "fw_proto_factory.svh"

    `include "fw_proto_reg.svh"

    `include "fw_realized.svh"

    function automatic bit fw_is_rtl(fw_component c);
        fw_realized r;
        if (c == null || !$cast(r, c)) return 0;
        return r.is_rtl();
    endfunction

    // An integer as a Verilog literal: unsized decimal when it fits 32 signed
    // bits (all a tool must give an unsized constant), else sized 64-bit hex
    // (e.g. a packed parameter vector such as {32'd15, 32'd15}).
    function automatic string fw_int_lit(longint v);
        if (v >= 0 && v < 64'sh8000_0000) return $sformatf("%0d", v);
        return $sformatf("64'h%0h", v);
    endfunction

    // Bits [msb:lsb] of a field that a pin-map entry covers.
    function automatic void fw_pin_bits(fw_extern_pin p, int unsigned width,
                                        output int msb, output int lsb);
        msb = (p.msb < 0) ? int'(width) - 1 : p.msb;
        lsb = (p.msb < 0) ? 0 : ((p.lsb < 0) ? p.msb : p.lsb);
    endfunction

    `include "fw_extern_component.svh"

    `include "fw_rtl_structural.svh"

    `include "fw_boundary.svh"

    `include "fw_emitter.svh"
