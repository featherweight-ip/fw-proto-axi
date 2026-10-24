// Bridges between the class layer and the signal-level transactors. Each
// bridge IS the opposite class of the endpoint it serves: to a manager's
// socket, the pins look like a subordinate, so its bridge is a mirror; to a
// subordinate's mirror, the pins look like a manager, so its bridge is a
// socket.
//
// Outbound: each API call packs the beat to stream format and hands it to
// the transactor (vif.send), blocking until the core takes it. Inbound:
// run() forks ONE process per receive channel (vif.recv -> unpack ->
// t.<ch>()), so a stalled channel never holds up another.
//
// Every bridge's constructor is new(name, parent, vif), as `fw_root_bind_*
// requires. The configuration comes from the wrapper's parameter (vif.p),
// so the class side and the pins cannot disagree about it.

// Manager socket <-> axi4_mgr_xtor pins. A mirror: provides axi4_req_if.
class axi4_mgr_xtor_bridge extends axi4_sub_mirror_t
        implements axi4_req_if, fw_runnable;
    virtual axi4_xtor_if vif;
    axi4_cfg             cfg;

    function new(string name, fw_component parent, virtual axi4_xtor_if vif);
        super.new(name, parent, this);
        this.vif = vif;
        cfg = axi4_cfg::from_param(vif.p);
        parent.add_runnable(this);
    endfunction

    virtual task aw(input axi4_aw_beat_t f); vif.send(AXI4_CH_AW, axi4_wire::pack_aw(cfg, f)); endtask
    virtual task w(input axi4_w_beat_t f);   vif.send(AXI4_CH_W,  axi4_wire::pack_w(cfg, f));  endtask
    virtual task ar(input axi4_ar_beat_t f); vif.send(AXI4_CH_AR, axi4_wire::pack_ar(cfg, f)); endtask

    virtual task run();
        fork
            forever begin axi4_wire::stream_t s; vif.recv(AXI4_CH_B, s); t.b(axi4_wire::unpack_b(cfg, s)); end
            forever begin axi4_wire::stream_t s; vif.recv(AXI4_CH_R, s); t.r(axi4_wire::unpack_r(cfg, s)); end
        join
    endtask
endclass

// Subordinate mirror <-> axi4_sub_xtor pins. A socket: provides axi4_rsp_if.
class axi4_sub_xtor_bridge extends axi4_mgr_socket_t
        implements axi4_rsp_if, fw_runnable;
    virtual axi4_xtor_if vif;
    axi4_cfg             cfg;

    function new(string name, fw_component parent, virtual axi4_xtor_if vif);
        super.new(name, parent, this);
        this.vif = vif;
        cfg = axi4_cfg::from_param(vif.p);
        parent.add_runnable(this);
    endfunction

    virtual task b(input axi4_b_beat_t f); vif.send(AXI4_CH_B, axi4_wire::pack_b(cfg, f)); endtask
    virtual task r(input axi4_r_beat_t f); vif.send(AXI4_CH_R, axi4_wire::pack_r(cfg, f)); endtask

    virtual task run();
        fork
            forever begin axi4_wire::stream_t s; vif.recv(AXI4_CH_AW, s); t.aw(axi4_wire::unpack_aw(cfg, s)); end
            forever begin axi4_wire::stream_t s; vif.recv(AXI4_CH_W,  s); t.w(axi4_wire::unpack_w(cfg, s));   end
            forever begin axi4_wire::stream_t s; vif.recv(AXI4_CH_AR, s); t.ar(axi4_wire::unpack_ar(cfg, s)); end
        join
    endtask
endclass
