// Lint elaboration top for the kit's hand-written RTL: the pin checker (and,
// through it, the defs package's burst helpers) and the register slice, under
// each test parameter set (axi4_test_params_pkg). The generated transactors
// have their own top (axi4_lint_xtor).
module axi4_lint_rtl (
    input  logic       aclk,
    input  logic       aresetn,
    input  logic       din,
    output logic [2:0] dout
);
    import axi4_test_params_pkg::*;
    axi4_lint_rtl_p #(P_MIN)  u_min  (.aclk, .aresetn, .din, .dout(dout[0]));
    axi4_lint_rtl_p #(P_DEF)  u_def  (.aclk, .aresetn, .din, .dout(dout[1]));
    axi4_lint_rtl_p #(P_WIDE) u_wide (.aclk, .aresetn, .din, .dout(dout[2]));
endmodule
