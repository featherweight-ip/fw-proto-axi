// L2 suite (plan P5): whole transactions
// through the adapters and the link to a trivial target (axi4_l2_cell).
// One cell per P; the same file runs in every view (the image picks the view's
// axi4_l1_link).
`include "svunit_defines.svh"

module l2_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_test_params_pkg::*;

    string name = "l2_ut";
    svunit_testcase svunit_ut;

    axi4_l2_cell #(P_MIN)  u_min ();
    axi4_l2_cell #(P_DEF)  u_def ();
    axi4_l2_cell #(P_WIDE) u_wide ();

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
    `define L2_TEST(T) \
        `SVTEST(T``_p_min) string err; u_min.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END \
        `SVTEST(T``_p_def) string err; u_def.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END \
        `SVTEST(T``_p_wide) string err; u_wide.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END

    `SVUNIT_TESTS_BEGIN
    `L2_TEST(single_write_read)
    `L2_TEST(random_bursts)
    `L2_TEST(backpressure)
    `L2_TEST(concurrent_ids)
    `L2_TEST(error_responses)
    `L2_TEST(link_beats)
    `L2_TEST(xact_listener)
    `L2_TEST(burst_fidelity)
    `L2_TEST(inline_responses)
    `L2_TEST(concurrent_writers)
    `SVUNIT_TESTS_END
    `undef L2_TEST
endmodule
