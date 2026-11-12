// ------------------------------------------------------------------
// Channel payloads, sized by P. Member names are the AMBA names without
// the channel prefix; the bundle's channel name supplies the prefix.
// ------------------------------------------------------------------
class axi4_types #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    typedef struct packed {
        (* fw_opt = "ID_W" *)       logic [w1(P.ID_W)-1:0] id;
        logic [P.ADDR_W-1:0]       addr;
        logic [7:0]                len;
        axi4_size_e                size;
        axi4_burst_e               burst;
        logic                      lock;
        logic [3:0]                cache;
        logic [2:0]                prot;
        (* fw_opt = "HAS_QOS" *)    logic [3:0] qos;
        (* fw_opt = "HAS_REGION" *) logic [3:0] region;
        (* fw_opt = "AWUSER_W" *)   logic [w1(P.AWUSER_W)-1:0] user;
    } aw_t;
    typedef struct packed {
        (* fw_opt = "ID_W" *)       logic [w1(P.ID_W)-1:0] id;
        logic [P.ADDR_W-1:0]       addr;
        logic [7:0]                len;
        axi4_size_e                size;
        axi4_burst_e               burst;
        logic                      lock;
        logic [3:0]                cache;
        logic [2:0]                prot;
        (* fw_opt = "HAS_QOS" *)    logic [3:0] qos;
        (* fw_opt = "HAS_REGION" *) logic [3:0] region;
        (* fw_opt = "ARUSER_W" *)   logic [w1(P.ARUSER_W)-1:0] user;
    } ar_t;
    typedef struct packed {
        logic [P.DATA_W-1:0]       data;
        logic [P.DATA_W/8-1:0]     strb;
        logic                      last;
        (* fw_opt = "WUSER_W" *)    logic [w1(P.WUSER_W)-1:0] user;
    } w_t;
    typedef struct packed {
        (* fw_opt = "ID_W" *)       logic [w1(P.ID_W)-1:0] id;
        axi4_resp_e                resp;
        (* fw_opt = "BUSER_W" *)    logic [w1(P.BUSER_W)-1:0] user;
    } b_t;
    typedef struct packed {
        (* fw_opt = "ID_W" *)       logic [w1(P.ID_W)-1:0] id;
        logic [P.DATA_W-1:0]       data;
        axi4_resp_e                resp;
        logic                      last;
        (* fw_opt = "RUSER_W" *)    logic [w1(P.RUSER_W)-1:0] user;
    } r_t;
    // Address-channel attributes of the convenience API (axi4_xact_if).
    typedef struct packed {
        logic [w1(P.ID_W)-1:0]     id;
        axi4_burst_e               burst;
        axi4_size_e                size;
        logic                      lock;
        logic [3:0]                cache;
        logic [2:0]                prot;
        logic [3:0]                qos;
        logic [3:0]                region;
        logic [w1(max2(P.AWUSER_W, P.ARUSER_W))-1:0] user;
    } attr_t;
    typedef logic [P.ADDR_W-1:0]   addr_t;
    typedef logic [P.DATA_W-1:0]   data_t;
    typedef logic [P.DATA_W/8-1:0] strb_t;
endclass
