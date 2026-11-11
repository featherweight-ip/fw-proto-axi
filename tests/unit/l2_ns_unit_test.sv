// L2 suite, new style (l2_ns; plan P5, the port of l2_basic): whole transactions
// through the adapters and the link to a trivial target (axi4_l2_ns_cell).
// One cell per P; the same file runs in every view (the image picks the view's
// axi4_l1_ns_link).
`include "svunit_defines.svh"

module l2_ns_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_test_params_pkg::*;

    string name = "l2_ns_ut";
    svunit_testcase svunit_ut;

    axi4_l2_ns_cell #(P_MIN)  u_min ();
    axi4_l2_ns_cell #(P_DEF)  u_def ();
    axi4_l2_ns_cell #(P_WIDE) u_wide ();

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
    `define NS_TEST(T) \
        `SVTEST(T``_p_min) string err; u_min.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END \
        `SVTEST(T``_p_def) string err; u_def.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END \
        `SVTEST(T``_p_wide) string err; u_wide.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END

    `SVUNIT_TESTS_BEGIN
    `NS_TEST(single_write_read)
    `NS_TEST(random_bursts)
    `NS_TEST(backpressure)
    `NS_TEST(concurrent_ids)
    `NS_TEST(error_responses)
    `NS_TEST(link_beats)
    `NS_TEST(xact_listener)
    `NS_TEST(burst_fidelity)
    `SVUNIT_TESTS_END
    `undef NS_TEST
endmodule
