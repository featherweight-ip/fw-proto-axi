// fw-hdl's protocol-independent fw_mem_if over an axi4_xact_if (port
// `xact`, e.g. an axi4_mgr_adapter). Each access is one INCR transaction:
// one beat of the access's own size when DATA is no wider than the bus,
// else full-width beats covering DATA. Data and strobes go on the byte
// lanes the address selects (A3.4.4). err = 1 when the response is SLVERR
// or DECERR. An access should be aligned to its size.
class axi4_to_mem #(type ADDR = logic [31:0], type DATA = logic [63:0],
                    type STRB = logic [7:0]) extends fw_component;
    `FW_MEM_IMP(ADDR, DATA, STRB, axi4_to_mem #(ADDR, DATA, STRB), mem);
    fw_port #(axi4_xact_if) xact;

    axi4_cfg          cfg;
    axi4_id_t         id;
    logic [3:0]       cache = 4'b0000;   // Device Non-bufferable
    logic [2:0]       prot  = 3'b000;

    localparam int BYTES = $bits(DATA) / 8;

    function new(string name, fw_component parent, axi4_cfg cfg = null);
        super.new(name, parent);
        this.cfg = cfg;
        if (this.cfg == null) this.cfg = new();
    endfunction

    function void build();
        mem  = new(this);
        xact = new("xact", this);
    endfunction

    // Bytes per beat and the transaction for an access at addr.
    local function axi4_xact mk(bit write, ADDR addr, output int unsigned bpb);
        axi4_xact x;
        int unsigned bb = cfg.bus_bytes();
        bpb = (BYTES < bb) ? BYTES : bb;
        x = axi4_xact::new_read(axi4_addr_t'(addr), axi4_size_e'($clog2(bpb)),
                                axi4_len_t'(BYTES / bpb - 1), AXI4_BURST_INCR, id);
        x.write = write;
        x.cache = cache;
        x.prot  = prot;
        return x;
    endfunction

    local function int unsigned lane0(axi4_xact x, int unsigned n);
        return axi4_beat_lower_lane(x.addr, x.size, x.len, x.burst, n, cfg.bus_bytes());
    endfunction

    task mem_write(output bit err, input ADDR addr, input DATA data, input STRB strb);
        int unsigned bpb;
        axi4_xact    x = mk(1, addr, bpb);
        for (int unsigned n = 0; n < x.n_beats(); n++) begin
            axi4_data_t  d = '0;
            axi4_strb_t  s = '0;
            int unsigned off = lane0(x, n);
            for (int unsigned i = 0; i < bpb; i++) begin
                d[8*(off + i) +: 8] = data[8*(n*bpb + i) +: 8];
                s[off + i]          = strb[n*bpb + i];
            end
            x.data.push_back(d);
            x.strb.push_back(s);
            x.wuser.push_back('0);
        end
        xact.t.xact(x);
        err = (x.resp inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR});
    endtask

    task mem_read(output DATA data, output bit err, input ADDR addr);
        int unsigned bpb;
        axi4_xact    x = mk(0, addr, bpb);
        xact.t.xact(x);
        data = '0;
        for (int unsigned n = 0; n < x.n_beats() && n < x.data.size(); n++) begin
            int unsigned off = lane0(x, n);
            for (int unsigned i = 0; i < bpb; i++)
                data[8*(n*bpb + i) +: 8] = x.data[n][8*(off + i) +: 8];
        end
        err = (x.resp inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR});
    endtask
endclass
