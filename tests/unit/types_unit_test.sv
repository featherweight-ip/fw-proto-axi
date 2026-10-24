// Types suite: the burst address helpers of axi4_types_pkg against worked
// examples of the IHI0022H A3.4.1 / A3.4.2 rules. No harness.
`include "svunit_defines.svh"

module types_unit_test;
    import svunit_pkg::svunit_testcase;
    import axi4_types_pkg::*;

    string name = "types_ut";
    svunit_testcase svunit_ut;

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

    `SVTEST(incr_aligned)
        for (int n = 0; n < 4; n++)
            `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h1000, AXI4_SIZE_4, 8'd3,
                                              AXI4_BURST_INCR, n), 64'h1000 + 4*n)
    `SVTEST_END

    `SVTEST(incr_unaligned_first)
        // First transfer at the start address; later ones size-aligned.
        `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 0), 64'h1003)
        `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 1), 64'h1004)
        `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 2), 64'h1008)
        // 8-byte bus: lanes 3..3 then 4..7 then 0..3.
        `FAIL_UNLESS_EQUAL(axi4_beat_lower_lane(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 0, 8), 3)
        `FAIL_UNLESS_EQUAL(axi4_beat_upper_lane(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 0, 8), 3)
        `FAIL_UNLESS_EQUAL(axi4_beat_lower_lane(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 1, 8), 4)
        `FAIL_UNLESS_EQUAL(axi4_beat_upper_lane(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 1, 8), 7)
        `FAIL_UNLESS_EQUAL(axi4_beat_lower_lane(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 2, 8), 0)
        `FAIL_UNLESS_EQUAL(axi4_beat_upper_lane(64'h1003, AXI4_SIZE_4, 8'd2, AXI4_BURST_INCR, 2, 8), 3)
    `SVTEST_END

    `SVTEST(wrap4x4)
        // 4 x 4-byte WRAP from 0x38: window 0x30..0x3F.
        `FAIL_UNLESS_EQUAL(axi4_wrap_boundary(64'h38, AXI4_SIZE_4, 8'd3), 64'h30)
        `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h38, AXI4_SIZE_4, 8'd3, AXI4_BURST_WRAP, 0), 64'h38)
        `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h38, AXI4_SIZE_4, 8'd3, AXI4_BURST_WRAP, 1), 64'h3C)
        `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h38, AXI4_SIZE_4, 8'd3, AXI4_BURST_WRAP, 2), 64'h30)
        `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h38, AXI4_SIZE_4, 8'd3, AXI4_BURST_WRAP, 3), 64'h34)
    `SVTEST_END

    `SVTEST(fixed)
        for (int n = 0; n < 4; n++)
            `FAIL_UNLESS_EQUAL(axi4_beat_addr(64'h2002, AXI4_SIZE_2, 8'd3,
                                              AXI4_BURST_FIXED, n), 64'h2002)
    `SVTEST_END

    `SVTEST(legality)
        `FAIL_UNLESS(axi4_burst_legal(64'h0FF0, AXI4_SIZE_4, 8'd3, AXI4_BURST_INCR, 8))
        `FAIL_IF(axi4_burst_legal(64'h0FF8, AXI4_SIZE_4, 8'd3, AXI4_BURST_INCR, 8))   // 4KB
        `FAIL_IF(axi4_burst_legal(64'h0000, AXI4_SIZE_16, 8'd0, AXI4_BURST_INCR, 8))  // > bus
        `FAIL_IF(axi4_burst_legal(64'h0000, AXI4_SIZE_4, 8'd2, AXI4_BURST_WRAP, 8))   // 3 beats
        `FAIL_IF(axi4_burst_legal(64'h0002, AXI4_SIZE_4, 8'd3, AXI4_BURST_WRAP, 8))   // unaligned
        `FAIL_IF(axi4_burst_legal(64'h0000, AXI4_SIZE_4, 8'd16, AXI4_BURST_FIXED, 8)) // > 16
        `FAIL_IF(axi4_burst_legal(64'h0000, AXI4_SIZE_4, 8'd0, AXI4_BURST_RSVD, 8))
        `FAIL_UNLESS(axi4_burst_legal(64'h0FC0, AXI4_SIZE_4, 8'd15, AXI4_BURST_WRAP, 8))
        `FAIL_UNLESS(axi4_burst_legal(64'h0000, AXI4_SIZE_1, 8'd255, AXI4_BURST_INCR, 8))
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
