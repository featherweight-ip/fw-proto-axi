// The parameter sets every new-style test runs over (plan §3.3).
package axi4_test_params_pkg;
    import fw_proto_axi4_defs_pkg::*;

    // Absent fields everywhere: no ID, no USER, no QOS/REGION.
    localparam axi4_param_t P_MIN = '{
        ADDR_W: 32, DATA_W: 32, ID_W: 0,
        AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
        HAS_QOS: 0, HAS_REGION: 0
    };

    localparam axi4_param_t P_DEF = AXI4_PARAM_DEFAULT;

    // Wide data; distinct USER widths, so a mix-up between channels shows.
    localparam axi4_param_t P_WIDE = '{
        ADDR_W: 64, DATA_W: 512, ID_W: 8,
        AWUSER_W: 4, WUSER_W: 2, BUSER_W: 1, ARUSER_W: 3, RUSER_W: 5,
        HAS_QOS: 1, HAS_REGION: 1
    };
endpackage
