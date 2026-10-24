// The class-facing side of axi4_mon_xtor: a queue of observed beats, in the
// cores' packed stream layout (so axi4_wire::unpack_* reads them). The
// queue is a ring of fixed arrays: Verilator 5.052 cannot schedule on a
// queue reached through a virtual interface. The bridge drains the ring
// without consuming time, so it never holds more than a few cycles of
// traffic. Unparameterized, like axi4_xtor_if.
interface axi4_mon_xtor_if (
    input logic aclk,
    input logic aresetn
);
    import axi4_types_pkg::*;

    typedef logic [AXI4_STREAM_W_MAX-1:0] stream_beat_t;

    // Read by the class side, through the virtual interface, which lint
    // cannot see.
    /* verilator lint_off UNUSEDSIGNAL */
    axi4_param_t  p;
    /* verilator lint_on UNUSEDSIGNAL */
    wire          unused_clk_rst = aclk ^ aresetn;

    localparam int RING = 1024;
    localparam int RW   = $clog2(RING);
    axi4_ch_e     ch_r[RING];
    stream_beat_t beat_r[RING];
    time          t_r[RING];
    int unsigned  n_push, n_pop;

    function automatic void push(axi4_ch_e ch, stream_beat_t beat);
        logic [RW-1:0] i = RW'(n_push % RING);
        if (n_push - n_pop >= RING)
            $fatal(1, "axi4_mon_xtor_if: observation ring overflow");
        ch_r[i]   = ch;
        beat_r[i] = beat;
        t_r[i]    = $time;
        n_push++;
    endfunction

    task automatic pop(output axi4_ch_e ch, output stream_beat_t beat, output time t);
        logic [RW-1:0] i;
        wait (n_push != n_pop);
        i    = RW'(n_pop % RING);
        ch   = ch_r[i];
        beat = beat_r[i];
        t    = t_r[i];
        n_pop++;
    endtask
endinterface
