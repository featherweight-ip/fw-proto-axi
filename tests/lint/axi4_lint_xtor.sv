// Lint elaboration of the generated transactors (plan P4.3): for each test P,
// axi4_mgr_xtor -> axi4_sub_xtor on internal pins with axi4_mon_xtor on them,
// and each wrapper's bridge. A separate top from axi4_lint_rtl (the checker and
// slice).
module axi4_lint_xtor (
    input  logic aclk, aresetn
);
    import axi4_test_params_pkg::*;
    axi4_lint_xtor_b2b #(P_MIN)  u_min (.*);
    axi4_lint_xtor_b2b #(P_DEF)  u_def (.*);
    axi4_lint_xtor_b2b #(P_WIDE) u_wide (.*);
endmodule
