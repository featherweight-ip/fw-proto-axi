// L1 suite (plan P4.3): the channel
// contract through API handles only, one cell per P (axi4_l1_cell). The same
// file runs in every view; the image picks the view's axi4_l1_link.
`include "svunit_defines.svh"

module l1_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_test_params_pkg::*;

    string name = "l1_ut";
    svunit_testcase svunit_ut;

    axi4_l1_cell #(P_MIN)  u_min ();
    axi4_l1_cell #(P_DEF)  u_def ();
    axi4_l1_cell #(P_WIDE) u_wide ();

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // One SVTEST per (test, P).
    `define L1_TEST(T) \
        `SVTEST(T``_p_min) string err; u_min.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END \
        `SVTEST(T``_p_def) string err; u_def.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END \
        `SVTEST(T``_p_wide) string err; u_wide.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END

    `SVUNIT_TESTS_BEGIN
    `L1_TEST(channels)
    `L1_TEST(concurrent)
    `L1_TEST(aw_stalled)
    `L1_TEST(encodings)
    `L1_TEST(backpressure)
    `SVUNIT_TESTS_END
endmodule
