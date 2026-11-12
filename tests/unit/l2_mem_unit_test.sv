// L2 memory suite (plan P5): the memory
// model and fw_mem_if through the adapters and the link (axi4_l2_mem_cell).
// One cell per P; the same file runs in every view (the image picks the view's
// axi4_l1_link).
`include "svunit_defines.svh"

module l2_mem_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_test_params_pkg::*;

    string name = "l2_mem_ut";
    svunit_testcase svunit_ut;

    axi4_l2_mem_cell #(P_MIN)  u_min ();
    axi4_l2_mem_cell #(P_DEF)  u_def ();
    axi4_l2_mem_cell #(P_WIDE) u_wide ();

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
    `define L2_MEM_TEST(T) \
        `SVTEST(T``_p_min) string err; u_min.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END \
        `SVTEST(T``_p_def) string err; u_def.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END \
        `SVTEST(T``_p_wide) string err; u_wide.t_``T(err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END

    `SVUNIT_TESTS_BEGIN
    `L2_MEM_TEST(mem_if_rw)
    `L2_MEM_TEST(strobes_and_fill)
    `L2_MEM_TEST(narrow_unaligned_incr)
    `L2_MEM_TEST(wrap_burst)
    `L2_MEM_TEST(fixed_burst)
    `L2_MEM_TEST(random_incr_readback)
    `L2_MEM_TEST(exclusive)
    `L2_MEM_TEST(error_ranges)
    `L2_MEM_TEST(concurrent_mem_if)
    `SVUNIT_TESTS_END
    `undef L2_MEM_TEST
endmodule
