// TLM view harness body, shared by every level. The including file defines:
//   AXI4_HARNESS   module name (what the suite's TestRunner instantiates)
//   AXI4_ENV_T     the env class (an axi4_test_pkg::axi4_env_base)
//   AXI4_EP_MGR    the manager side's socket   AXI4_EP_SUB  its peer mirror
// The link is bound directly, socket to mirror: no masking, zero time.
`include "fw_hdl_macros.svh"

module `AXI4_HARNESS;
    import fw_hdl_pkg::*;
    import fw_proto_axi4_pkg::*;
    import axi4_test_pkg::*;

    class axi4_env_tlm extends `AXI4_ENV_T;
        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void connect();
            super.connect();
            `AXI4_EP_MGR.connect(`AXI4_EP_SUB);
        endfunction
    endclass

    reg clock = 0, reset = 1;
    always #5 clock = ~clock;
    initial begin
        repeat (2) @(posedge clock);
        reset = 0;
    end

    `fw_root_begin(axi4_env_tlm, u_root, clock, reset)
    `fw_root_end
endmodule
