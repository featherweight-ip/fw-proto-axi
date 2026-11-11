// AXI4: the core specification, synthesizable part: the parameter set, the
// encodings and the burst arithmetic. No classes, so it reads into any RTL flow
// (sv2v, Yosys). The classes (payload structs, port bundle, transaction API) are
// in fw_proto_axi4_core_pkg; the fw_proto weavers derive the rest of both
// (fw_proto_axi4_defs_pkg_woven, fw_proto_axi4_core_pkg_woven; docs/design-new-style.md §3).
//
// Encodings are transcribed from AMBA AXI Protocol Specification IHI0022
// Issue H (sections cited per item). Identifiers and encodings only.
package fw_proto_axi4_defs_pkg;
    /* verilator lint_off UNUSEDPARAM */

    // ------------------------------------------------------------------
    // Parameters. A width of 0 means the signal is absent (A9.3).
    // ------------------------------------------------------------------
    typedef struct packed {
        int unsigned ADDR_W;     // AxADDR
        int unsigned DATA_W;     // xDATA: 8, 16, ... 1024
        int unsigned ID_W;       // AWID/BID, ARID/RID
        int unsigned AWUSER_W;
        int unsigned WUSER_W;
        int unsigned BUSER_W;
        int unsigned ARUSER_W;
        int unsigned RUSER_W;
        int unsigned HAS_QOS;    // AxQOS present (0/1)
        int unsigned HAS_REGION; // AxREGION present (0/1)
    } axi4_param_t;

    localparam axi4_param_t AXI4_PARAM_DEFAULT = '{
        ADDR_W: 32, DATA_W: 64, ID_W: 4,
        AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0,
        HAS_QOS: 1, HAS_REGION: 1
    };

    // Width of a field that may be absent: an absent field is held as one bit.
    function automatic int unsigned w1(int unsigned w);
        return (w > 0) ? w : 1;
    endfunction

    function automatic int unsigned max2(int unsigned a, int unsigned b);
        return (a > b) ? a : b;
    endfunction

    // ------------------------------------------------------------------
    // Encodings
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {                  // AxBURST (A3.4.1, Table A3.3)
        AXI4_BURST_FIXED = 2'b00, AXI4_BURST_INCR = 2'b01,
        AXI4_BURST_WRAP  = 2'b10, AXI4_BURST_RSVD = 2'b11
    } axi4_burst_e;

    typedef enum logic [2:0] {                  // AxSIZE (A3.4.1, Table A3.2)
        AXI4_SIZE_1  = 3'd0, AXI4_SIZE_2  = 3'd1, AXI4_SIZE_4  = 3'd2, AXI4_SIZE_8   = 3'd3,
        AXI4_SIZE_16 = 3'd4, AXI4_SIZE_32 = 3'd5, AXI4_SIZE_64 = 3'd6, AXI4_SIZE_128 = 3'd7
    } axi4_size_e;

    typedef enum logic [1:0] {                  // xRESP (A3.4.5, Table A3.4)
        AXI4_RESP_OKAY   = 2'b00, AXI4_RESP_EXOKAY = 2'b01,
        AXI4_RESP_SLVERR = 2'b10, AXI4_RESP_DECERR = 2'b11
    } axi4_resp_e;

    // ------------------------------------------------------------------
    // Burst arithmetic (A3.4.1, A3.4.2). Independent of P: addresses are
    // carried at 64 bits. `n` is the 0-based beat index within the burst.
    // ------------------------------------------------------------------
    typedef logic [63:0] axi4_addr64_t;

    function automatic int unsigned axi4_size_bytes(axi4_size_e size);
        return 32'd1 << size;
    endfunction

    function automatic int unsigned axi4_burst_beats(logic [7:0] len);
        return int'(len) + 1;
    endfunction

    function automatic axi4_addr64_t axi4_aligned_addr(axi4_addr64_t addr, axi4_size_e size);
        return addr & ~((axi4_addr64_t'(1) << size) - 1);
    endfunction

    function automatic axi4_addr64_t axi4_wrap_boundary(
        axi4_addr64_t addr, axi4_size_e size, logic [7:0] len);
        axi4_addr64_t total = axi4_addr64_t'(axi4_burst_beats(len)) << size;
        return addr & ~(total - 1);
    endfunction

    function automatic axi4_addr64_t axi4_beat_addr(
        axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
        axi4_burst_e burst, int unsigned n);
        axi4_addr64_t total = axi4_addr64_t'(axi4_burst_beats(len)) << size;
        axi4_addr64_t a;
        if (n == 0 || burst == AXI4_BURST_FIXED)
            return addr;
        a = axi4_aligned_addr(addr, size) + (axi4_addr64_t'(n) << size);
        if (burst == AXI4_BURST_WRAP && a >= axi4_wrap_boundary(addr, size, len) + total)
            a = a - total;
        return a;
    endfunction

    // Lowest and highest active byte lane of transfer n on a bus of bus_bytes
    // bytes (A3.4.3).
    function automatic int unsigned axi4_beat_lower_lane(
        axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
        axi4_burst_e burst, int unsigned n, int unsigned bus_bytes);
        axi4_addr64_t a = axi4_beat_addr(addr, size, len, burst, n);
        return int'(a & (axi4_addr64_t'(bus_bytes) - 1));
    endfunction

    function automatic int unsigned axi4_beat_upper_lane(
        axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
        axi4_burst_e burst, int unsigned n, int unsigned bus_bytes);
        axi4_addr64_t a = axi4_aligned_addr(axi4_beat_addr(addr, size, len, burst, n), size);
        return int'((a & (axi4_addr64_t'(bus_bytes) - 1))
                   + (axi4_addr64_t'(axi4_size_bytes(size)) - 1));
    endfunction

    function automatic bit axi4_crosses_4k(
        axi4_addr64_t addr, axi4_size_e size, logic [7:0] len, axi4_burst_e burst);
        axi4_addr64_t last;
        if (burst != AXI4_BURST_INCR)
            return 1'b0;
        last = axi4_aligned_addr(addr, size)
             + (axi4_addr64_t'(axi4_burst_beats(len)) << size) - 1;
        return (addr >> 12) != (last >> 12);
    endfunction

    // A3.4.1: burst type not reserved, transfer no wider than the bus,
    // FIXED/WRAP at most 16 transfers, WRAP aligned with 2/4/8/16, no 4KB crossing.
    function automatic bit axi4_burst_legal(
        axi4_addr64_t addr, axi4_size_e size, logic [7:0] len,
        axi4_burst_e burst, int unsigned bus_bytes);
        int unsigned beats = axi4_burst_beats(len);
        if (burst == AXI4_BURST_RSVD || axi4_size_bytes(size) > bus_bytes)
            return 1'b0;
        if (burst != AXI4_BURST_INCR && beats > 16)
            return 1'b0;
        if (burst == AXI4_BURST_WRAP &&
            (!(beats inside {2, 4, 8, 16}) || axi4_aligned_addr(addr, size) != addr))
            return 1'b0;
        return !axi4_crosses_4k(addr, size, len, burst);
    endfunction

    // A7.2.4 exclusive access: at most 16 transfers, a total of 1, 2, 4, ...
    // 128 bytes, the start address aligned to that total.
    function automatic bit axi4_excl_legal(axi4_addr64_t addr, axi4_size_e size, logic [7:0] len);
        int unsigned  beats = axi4_burst_beats(len);
        axi4_addr64_t total = axi4_addr64_t'(beats) << size;
        if (beats > 16 || total > 128 || (total & (total - 1)) != 0)
            return 1'b0;
        return (addr & (total - 1)) == 0;
    endfunction
    /* verilator lint_on UNUSEDPARAM */
endpackage
