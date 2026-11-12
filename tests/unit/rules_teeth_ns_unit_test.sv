// Rule teeth (rules_teeth_ns; plan P7, the port of chk_teeth): one planted bug
// per case, each of which must fire exactly its rule, reported as the API event
// it broke, and (with pins) agree with axi4_checker. See axi4_rules_teeth_cell.
// The same file runs in every view (the image picks the view's axi4_l1_ns_link).
`include "svunit_defines.svh"

module rules_teeth_ns_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_test_params_pkg::*;

    string name = "rules_teeth_ns_ut";
    svunit_testcase svunit_ut;

    axi4_rules_teeth_cell #(P_DEF) u_def ();

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // case, the rule it must fire, text its report must contain, the checker
    // side ("m", "s"; "" none), whether the checker may also count the other side.
    `define RT(N, R, M, S, E) \
        `SVTEST(N) string err; u_def.t_case(`"N`", R, M, S, E, err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END
    `define RV(N) \
        `SVTEST(N) string err; u_def.t_rv(`"N`", err); `FAIL_UNLESS_STR_EQUAL(err, "") `SVTEST_END

    `SVUNIT_TESTS_BEGIN
    `RT(legal,        "",            "",                         "",  0)
    `RT(b_twice,      "resp_match",  "b id=3: no write",         "s", 0)
    `RT(r_spurious,   "resp_match",  "r id=5: no read",          "s", 0)
    `RT(rlast_early,  "r_burst",     "beat 2 of 4: rlast=1",     "s", 0)
    `RT(r_order,      "r_burst",     "r id=4, read 0",           "s", 0)
    `RT(b_early,      "b_order",     "b id=6 (write 0",          "s", 0)
    `RT(exokay,       "exclusive",   "b id=1: EXOKAY",           "s", 0)
    `RT(wlast_early,  "w_burst",     "beat 2 of 4: wlast=1",     "m", 0)
    `RT(w_ahead_long, "w_burst",     "sent ahead, had 3 beats",  "m", 0)
    `RT(burst_4k,     "burst_legal", "crosses a 4KB boundary",   "m", 0)
    `RT(wrap_len,     "burst_legal", "WRAP length",              "m", 0)
    `RT(excl_illegal, "burst_legal", "exclusive access",         "m", 0)
    `RT(wstrb_lane,   "w_lanes",     "beat 0: wstrb",            "m", 0)
    `RT(capacity,     "capacity",    "32 reads outstanding",     "m", 1)
    `RV(rv_legal)
    `RV(rv_drop)
    `RV(rv_payload)
    `SVUNIT_TESTS_END
    `undef RT
    `undef RV
endmodule
