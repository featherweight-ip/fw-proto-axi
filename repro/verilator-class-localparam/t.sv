// Internal fault in Verilator 5.055 (segfault; unbounded memory without a ulimit).
// A class `localparam` derived from $bits() of a type parameter (BPB below) used in
// a nested loop's bounds and part-select indices, where the queue indexed in the
// loop body is filled through an interface-class task call whose argument types
// are typedefs of another parameterized class.
package p;
    typedef struct packed {
        int unsigned ADDR_W;
        int unsigned DATA_W;
        int unsigned ID_W;
    } param_t;
    localparam param_t PDEF = '{ADDR_W: 32, DATA_W: 64, ID_W: 4};

    typedef enum logic [1:0] {OKAY = 2'b00, SLVERR = 2'b10} resp_e;

    function automatic int unsigned w1(int unsigned w);
        return (w > 0) ? w : 1;
    endfunction

    class types #(param_t P = PDEF);
        typedef struct packed {
            logic [w1(P.ID_W)-1:0] id;
        } attr_t;
        typedef logic [P.ADDR_W-1:0] addr_t;
        typedef logic [P.DATA_W-1:0] data_t;
    endclass

    interface class xact_if #(param_t P = PDEF);
        typedef types #(P)::addr_t addr_t;
        typedef types #(P)::data_t data_t;
        typedef types #(P)::attr_t attr_t;
        pure virtual task read(input addr_t addr, input int unsigned beats, input attr_t attr,
                               output data_t data[$], output resp_e resp);
    endclass

    class to_mem #(param_t P = PDEF, type ADDR = logic [31:0], type DATA = logic [63:0]);
        typedef types #(P)::attr_t attr_t;
        typedef types #(P)::addr_t addr_t;
        typedef types #(P)::data_t data_t;
        localparam int unsigned BUS = P.DATA_W / 8;
        localparam int unsigned BYTES = $bits(DATA) / 8;
        localparam int unsigned BPB = (BYTES < BUS) ? BYTES : BUS;   // 4 here
        xact_if #(P) xact;
        attr_t       attr;

        virtual task read(output DATA data, input ADDR addr);
            data_t d[$];
            resp_e resp;
            xact.read(addr_t'(addr), 1, attr, d, resp);
            for (int unsigned n = 0; n < BYTES / BPB && n < d.size(); n++)
                for (int unsigned i = 0; i < BPB; i++)
                    data[8*(n*BPB + i) +: 8] = d[n][8*i +: 8];
        endtask
    endclass
endpackage

module top;
    import p::*;
    // DATA (32 bits) narrower than the bus (P.DATA_W = 64): faults.
    // With DATA = logic [63:0] it builds.
    to_mem #(PDEF, logic [31:0], logic [31:0]) tm;
endmodule
