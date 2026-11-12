// Transactor suite (plan P4.2): the generated axi4_{mgr,sub,mon}_xtor and their
// bridges back to back, one link per P (axi4_xtor_b2b), with axi4_checker in
// COUNT_ONLY mode on each.
`include "svunit_defines.svh"

module xtor_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_test_params_pkg::*;

    string name = "xtor_ut";
    svunit_testcase svunit_ut;

    axi4_xtor_b2b #(P_MIN)  u_min ();
    axi4_xtor_b2b #(P_DEF)  u_def ();
    axi4_xtor_b2b #(P_WIDE) u_wide ();

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    `SVUNIT_TESTS_BEGIN

    `SVTEST(b2b_p_min)
        string err;
        u_min.run(err);
        `FAIL_UNLESS_STR_EQUAL(err, "")
    `SVTEST_END

    `SVTEST(b2b_p_def)
        string err;
        u_def.run(err);
        `FAIL_UNLESS_STR_EQUAL(err, "")
    `SVTEST_END

    `SVTEST(b2b_p_wide)
        string err;
        u_wide.run(err);
        `FAIL_UNLESS_STR_EQUAL(err, "")
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
