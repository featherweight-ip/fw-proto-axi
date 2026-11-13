// The class-free package of the synthetic transactor bundle (weave_synx_pkg.sv):
// its parameter struct, for the generated synthesizable cores.
package weave_synx_defs_pkg;
    /* verilator lint_off UNUSEDPARAM */
    typedef struct packed {
        int unsigned DATA_W;
        int unsigned HAS_PRI;     // cmd pri present (0/1)
    } synx_param_t;

    localparam synx_param_t SYNX_PARAM_DEFAULT = '{DATA_W: 16, HAS_PRI: 1};
    /* verilator lint_on UNUSEDPARAM */
endpackage
