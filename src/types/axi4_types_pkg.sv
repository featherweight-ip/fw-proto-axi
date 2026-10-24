// AXI4 types: field encodings, the interface parameter set, the class-level
// per-channel beat structs and the burst address helpers. Synthesizable and
// fw-hdl-free.
//
// Encodings are transcribed from AMBA AXI Protocol Specification IHI0022
// Issue H (sections cited per item). Identifiers and encodings only; no
// specification text is reproduced.
//
// The beat structs are the CLASS-LEVEL form: every field at its widest
// (Addr 64, Data 1024, ID 32, USER 64), so one beat type serves every
// interface configuration. The wire layout per configuration is the
// transactors' job.
// The enums and scalar typedefs are 4-state for RTL and simulation, and
// 2-state when read by fw-hdl's formal lifter (FW_FORMAL), whose static
// subset is 2-state. Nothing here relies on X.
`ifndef AXI4_LOGIC
`ifdef FW_FORMAL
`define AXI4_LOGIC bit
`else
`define AXI4_LOGIC logic
`endif
`endif

package axi4_types_pkg;
    // A package of encodings is an API: most constants are unused by any one
    // consumer.
    /* verilator lint_off UNUSEDPARAM */

    // ------------------------------------------------------------------
    // Widths (maxima the class-level structs carry)
    // ------------------------------------------------------------------
    localparam int AXI4_ADDR_W_MAX = 64;    // A2.2: implementation-defined
    localparam int AXI4_DATA_W_MAX = 1024;  // A2.3: 8..1024, power of 2
    localparam int AXI4_STRB_W_MAX = AXI4_DATA_W_MAX / 8;
    localparam int AXI4_ID_W_MAX   = 32;    // A5.2: implementation-defined
    localparam int AXI4_USER_W_MAX = 64;    // A8.4: implementation-defined
    localparam int AXI4_LEN_W      = 8;     // A3.4.1: AxLEN
    localparam int AXI4_SIZE_W     = 3;     // A3.4.1: AxSIZE
    localparam int AXI4_MAX_BEATS  = 256;   // A3.4.1: INCR, AxLEN+1
    localparam int AXI4_MAX_BEATS_FIXED_WRAP = 16;  // A3.4.1
    localparam int AXI4_BOUNDARY_BYTES = 4096;      // A3.4.1: 4KB rule

    typedef `AXI4_LOGIC [AXI4_ADDR_W_MAX-1:0] axi4_addr_t;
    typedef `AXI4_LOGIC [AXI4_DATA_W_MAX-1:0] axi4_data_t;
    typedef `AXI4_LOGIC [AXI4_STRB_W_MAX-1:0] axi4_strb_t;
    typedef `AXI4_LOGIC [AXI4_ID_W_MAX-1:0]   axi4_id_t;
    typedef `AXI4_LOGIC [AXI4_USER_W_MAX-1:0] axi4_user_t;
    typedef `AXI4_LOGIC [AXI4_LEN_W-1:0]      axi4_len_t;

    // ------------------------------------------------------------------
    // Interface parameter set. A width of 0 means the signal is absent
    // (A9.3); the beat structs still carry the field, held at 0.
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
    } axi4_param_t;

    localparam axi4_param_t AXI4_PARAM_DEFAULT = '{
        ADDR_W:   32,
        DATA_W:   64,
        ID_W:     4,
        AWUSER_W: 0,
        WUSER_W:  0,
        BUSER_W:  0,
        ARUSER_W: 0,
        RUSER_W:  0
    };

    // ------------------------------------------------------------------
    // AxBURST (A3.4.1, Table A3.3)
    // ------------------------------------------------------------------
    typedef enum `AXI4_LOGIC [1:0] {
        AXI4_BURST_FIXED = 2'b00,
        AXI4_BURST_INCR  = 2'b01,
        AXI4_BURST_WRAP  = 2'b10,
        AXI4_BURST_RSVD  = 2'b11
    } axi4_burst_e;

    // ------------------------------------------------------------------
    // AxSIZE (A3.4.1, Table A3.2): bytes per transfer = 2**AxSIZE
    // ------------------------------------------------------------------
    typedef enum `AXI4_LOGIC [2:0] {
        AXI4_SIZE_1   = 3'b000,
        AXI4_SIZE_2   = 3'b001,
        AXI4_SIZE_4   = 3'b010,
        AXI4_SIZE_8   = 3'b011,
        AXI4_SIZE_16  = 3'b100,
        AXI4_SIZE_32  = 3'b101,
        AXI4_SIZE_64  = 3'b110,
        AXI4_SIZE_128 = 3'b111
    } axi4_size_e;

    // ------------------------------------------------------------------
    // xRESP (A3.4.5, Table A3.4)
    // ------------------------------------------------------------------
    typedef enum `AXI4_LOGIC [1:0] {
        AXI4_RESP_OKAY   = 2'b00,
        AXI4_RESP_EXOKAY = 2'b01,
        AXI4_RESP_SLVERR = 2'b10,
        AXI4_RESP_DECERR = 2'b11
    } axi4_resp_e;

    // ------------------------------------------------------------------
    // AxCACHE (A4.4) and AxPROT (A4.7) bit positions
    // ------------------------------------------------------------------
    localparam int AXI4_CACHE_BUFFERABLE = 0;
    localparam int AXI4_CACHE_MODIFIABLE = 1;
    localparam int AXI4_CACHE_RALLOC     = 2;  // AWCACHE: Other Allocate
    localparam int AXI4_CACHE_WALLOC     = 3;  // ARCACHE: Other Allocate
    localparam int AXI4_PROT_PRIVILEGED  = 0;
    localparam int AXI4_PROT_NONSECURE   = 1;
    localparam int AXI4_PROT_INSTRUCTION = 2;

    // ------------------------------------------------------------------
    // Per-channel beats (A2.2-A2.6). AW and AR share one address struct.
    // ------------------------------------------------------------------
    typedef struct packed {
        axi4_id_t    id;
        axi4_addr_t  addr;
        axi4_len_t   len;
        axi4_size_e  size;
        axi4_burst_e burst;
        `AXI4_LOGIC        lock;   // A7.4: 0 normal, 1 exclusive
        `AXI4_LOGIC [3:0]  cache;
        `AXI4_LOGIC [2:0]  prot;
        `AXI4_LOGIC [3:0]  qos;
        `AXI4_LOGIC [3:0]  region;
        axi4_user_t  user;
    } axi4_addr_beat_t;

    typedef axi4_addr_beat_t axi4_aw_beat_t;
    typedef axi4_addr_beat_t axi4_ar_beat_t;

    typedef struct packed {
        axi4_data_t data;
        axi4_strb_t strb;
        `AXI4_LOGIC last;
        axi4_user_t user;
    } axi4_w_beat_t;

    typedef struct packed {
        axi4_id_t   id;
        axi4_resp_e resp;
        axi4_user_t user;
    } axi4_b_beat_t;

    typedef struct packed {
        axi4_id_t   id;
        axi4_data_t data;
        axi4_resp_e resp;
        `AXI4_LOGIC last;
        axi4_user_t user;
    } axi4_r_beat_t;

    // ------------------------------------------------------------------
    // Burst helpers (A3.4.1 rules, A3.4.2 transfer address and byte lanes).
    // `n` is the 0-based beat index within the burst.
    // ------------------------------------------------------------------

    // Bytes per transfer: 2**size.
    function automatic int unsigned axi4_size_bytes(axi4_size_e size);
        return 32'd1 << size;
    endfunction

    // Transfers in the burst: AxLEN+1.
    function automatic int unsigned axi4_burst_beats(axi4_len_t len);
        return int'(len) + 1;
    endfunction

    // Start address rounded down to the transfer size.
    function automatic axi4_addr_t axi4_aligned_addr(axi4_addr_t addr, axi4_size_e size);
        return addr & ~((axi4_addr_t'(1) << size) - 1);
    endfunction

    // Lowest address of a WRAP burst's window. Meaningful only for legal
    // WRAP lengths (2, 4, 8, 16 transfers), whose window is a power of 2.
    function automatic axi4_addr_t axi4_wrap_boundary(
        axi4_addr_t addr, axi4_size_e size, axi4_len_t len);
        axi4_addr_t total = axi4_addr_t'(axi4_burst_beats(len)) << size;
        return addr & ~(total - 1);
    endfunction

    // Address of transfer n. The first transfer is at the (possibly
    // unaligned) start address; later ones are size-aligned.
    function automatic axi4_addr_t axi4_beat_addr(
        axi4_addr_t addr, axi4_size_e size, axi4_len_t len,
        axi4_burst_e burst, int unsigned n);
        axi4_addr_t aligned = axi4_aligned_addr(addr, size);
        axi4_addr_t total   = axi4_addr_t'(axi4_burst_beats(len)) << size;
        axi4_addr_t a;
        if (n == 0 || burst == AXI4_BURST_FIXED)
            return addr;
        a = aligned + (axi4_addr_t'(n) << size);
        if (burst == AXI4_BURST_WRAP) begin
            axi4_addr_t lo = axi4_wrap_boundary(addr, size, len);
            if (a >= lo + total)
                a = a - total;
        end
        return a;
    endfunction

    // Lowest active byte lane of transfer n on a bus of bus_bytes bytes.
    function automatic int unsigned axi4_beat_lower_lane(
        axi4_addr_t addr, axi4_size_e size, axi4_len_t len,
        axi4_burst_e burst, int unsigned n, int unsigned bus_bytes);
        axi4_addr_t a = axi4_beat_addr(addr, size, len, burst, n);
        return int'(a & (axi4_addr_t'(bus_bytes) - 1));
    endfunction

    // Highest active byte lane of transfer n on a bus of bus_bytes bytes.
    function automatic int unsigned axi4_beat_upper_lane(
        axi4_addr_t addr, axi4_size_e size, axi4_len_t len,
        axi4_burst_e burst, int unsigned n, int unsigned bus_bytes);
        axi4_addr_t a = axi4_aligned_addr(
            axi4_beat_addr(addr, size, len, burst, n), size);
        return int'((a & (axi4_addr_t'(bus_bytes) - 1))
                   + (axi4_addr_t'(axi4_size_bytes(size)) - 1));
    endfunction

    // An INCR burst that crosses a 4KB boundary (FIXED and legal WRAP
    // bursts cannot).
    function automatic bit axi4_crosses_4k(
        axi4_addr_t addr, axi4_size_e size, axi4_len_t len, axi4_burst_e burst);
        axi4_addr_t last;
        if (burst != AXI4_BURST_INCR)
            return 1'b0;
        last = axi4_aligned_addr(addr, size)
             + (axi4_addr_t'(axi4_burst_beats(len)) << size) - 1;
        return (addr >> 12) != (last >> 12);
    endfunction

    // The A3.4.1 burst rules for a bus of bus_bytes bytes: burst type not
    // reserved, transfer no wider than the bus, FIXED/WRAP at most 16
    // transfers, WRAP aligned with 2/4/8/16 transfers, no 4KB crossing.
    function automatic bit axi4_burst_legal(
        axi4_addr_t addr, axi4_size_e size, axi4_len_t len,
        axi4_burst_e burst, int unsigned bus_bytes);
        int unsigned beats = axi4_burst_beats(len);
        if (burst == AXI4_BURST_RSVD)
            return 1'b0;
        if (axi4_size_bytes(size) > bus_bytes)
            return 1'b0;
        if (burst != AXI4_BURST_INCR && beats > AXI4_MAX_BEATS_FIXED_WRAP)
            return 1'b0;
        if (burst == AXI4_BURST_WRAP) begin
            if (!(beats == 2 || beats == 4 || beats == 8 || beats == 16))
                return 1'b0;
            if (axi4_aligned_addr(addr, size) != addr)
                return 1'b0;
        end
        return !axi4_crosses_4k(addr, size, len, burst);
    endfunction

    /* verilator lint_on UNUSEDPARAM */
endpackage
