# Derived classes

Every class, interface and module the fw_proto weavers generate from the core
specification ([core-spec.md](core-spec.md)): its name, what its default bodies do, and
when to use or extend it. The examples are excerpts of the woven output for AXI4
(`rundir/fw.proto.axi.woven-xtor/woven/`), cut with `...`. Design background:
[design-new-style.md](design-new-style.md) §4.

## Where they come from

The weaver is `fw_proto_weave:FwProtoWeaver` (`fw_proto/python/fw_proto_weave`), run by
sv-weave as a dv-flow task:

| Task | Config | Output (`rundir/…/woven/`) |
|---|---|---|
| `dfm run woven` | `src/weave/sv-weave.yaml` | `fw_proto_axi4_core_pkg_woven.sv`, `fw_proto_axi4_defs_pkg_woven.sv` |
| `dfm run woven-xtor` | `src/weave/sv-weave-xtor.yaml` (`xtor: true`) | the same two packages, larger, plus nine module/interface files (`axi4_{mgr,sub,mon}_xtor{,_core,_if}.sv`) |

An image uses `woven` or `woven-xtor`, never both (they define the same package). The
`behav`/`rules` file sets come in both forms (`behav-xtor`, `rules-xtor`).

Weaver options (in the config's `weavers[].options`):

| Option | Effect | Default |
|---|---|---|
| `include: [names]` | treat these interface classes as APIs without `(* fw_api *)` | none |
| `derive: [kinds]` | subset of `listener`, `base`, `proxy`, `imp`, `bundle` | all |
| `xtor: bool` | also the transactors and the abstractor glue | off |

Each source file's module docstring (`bases.py`, `listeners.py`, `proxies.py`, `imps.py`,
`endpoints.py`, `ports.py`, `xtors.py`, `abs.py`) lists what it emits.

## Naming

`<api>` is any API: a `(* fw_api *)` interface class or a channel API. `<proto>` is the
bundle's `fw_proto_bundle` (`axi4`), `<role>` one of its `fw_roles` (`mgr`, `sub`) or
`mon`, `<ch>` a channel (`aw`, `w`, `b`, `ar`, `r`), `<m>` an API method.

| Name | Kind | From | Weave |
|---|---|---|---|
| `<proto>_req_if`, `<proto>_rsp_if` | interface class (API) | bundle | `woven` |
| `<api>_listener` | interface class | each API | `woven` |
| `<api>_listener_base` | virtual class | each API | `woven` |
| `<api>_listener_fanout` | class | each API | `woven` |
| `<api>_base` | virtual class | each API | `woven` |
| `<api>_proxy` | class | each API | `woven` |
| `<api>_imp #(P, type IMP)` | class | each API | `woven` |
| `<proto>_req_if_inbox`, `<proto>_rsp_if_inbox` | class | bundle | `woven` |
| `<proto>_sp` | virtual class | bundle | `woven` |
| `<proto>_<role>_sp` | class | bundle, per role | `woven` (`connect()` only with `xtor`) |
| `<proto>_payloads` | class (static functions) | bundle | `woven` |
| `<proto>_<payload>_bits(P)` | function in `<fw_defs_pkg>_woven` | bundle | `woven` |
| `<proto>_<role>_xtor_core` | module (synthesizable) | bundle, per role and `mon` | `woven-xtor` |
| `<proto>_<role>_xtor` | module | bundle, per role and `mon` | `woven-xtor` |
| `<proto>_<role>_xtor_if` | interface | bundle, per role and `mon` | `woven-xtor` |
| `<proto>_<role>_xtor_chans` | class | bundle, per role and `mon` | `woven-xtor` |
| `<proto>_<role>_xtor_bridge` | class | bundle, per role and `mon` | `woven-xtor` |
| `<proto>_<role>_socket` | class | bundle, per role | `woven-xtor` |
| `<proto>_observers` | class (static) | bundle | `woven-xtor` |
| `<proto>_<role>_abs` | class | bundle, per role | `woven-xtor` |
| `<proto>_<role>_abs_h` | class | bundle, per role | `woven-xtor` |

Every derived class has the API's or bundle's own parameter header, here
`#(axi4_param_t P = AXI4_PARAM_DEFAULT)`. Within a method name, a suffix (`aw_pre`, not
`pre_aw`) keeps each operation's names together when sorted.

For AXI4 the per-API set is generated five times: for `axi4_req_if`, `axi4_rsp_if`,
`axi4_burst_req_if`, `axi4_burst_rsp_if` and `axi4_xact_if`.

Every derived class that implements an API re-declares the API's typedefs
(`typedef axi4_req_if #(P)::aw_t aw_t;`), since interface-class typedefs are not
inherited. A subclass can use `aw_t` etc. directly.

## Per-API derivatives

### Channel APIs: `<proto>_req_if`, `<proto>_rsp_if`

Synthesized from the bundle, then treated like a hand-written API. One task per channel,
named after the channel, taking the payload; it returns when the beat is accepted.
`_req_if` has the `fw_fwd` channels (called by the first role), `_rsp_if` the `fw_rev`
ones (called by the second).

```systemverilog
// Forward channels of axi4_bundle, called by the mgr: one task per channel, returning
// when the beat is accepted.
(* fw_api *)
interface class axi4_req_if #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    typedef axi4_types #(P)::aw_t aw_t;
    typedef axi4_types #(P)::w_t w_t;
    typedef axi4_types #(P)::ar_t ar_t;
    pure virtual task aw(input aw_t t);
    pure virtual task w(input w_t t);
    pure virtual task ar(input ar_t t);
endclass
```

The method name equals the channel name. That is the only link a bridge needs between a
method and its pins.

### `<api>_listener`

An interface class with two `void` functions per API method: `<m>_pre` when the call is
made, `<m>_post` when it completes. `_pre` gets the inputs; `_post` gets the inputs and
the outputs (as inputs). Callbacks are functions, so a listener cannot block or alter the
call. Marked `(* fw_listener *)`.

```systemverilog
(* fw_listener *)
interface class axi4_xact_if_listener #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    ...
    pure virtual function void write_pre(input addr_t addr, input data_t data [$], input strb_t strb [$], input attr_t attr);
    pure virtual function void write_post(input addr_t addr, input data_t data [$], input strb_t strb [$], input attr_t attr, input axi4_resp_e resp);
    pure virtual function void read_pre(input addr_t addr, input int unsigned beats, input attr_t attr);
    pure virtual function void read_post(input addr_t addr, input int unsigned beats, input attr_t attr, input data_t data [$], input axi4_resp_e resp);
endclass
```

What pre and post mean depends on the source:

| Source | `<m>_pre` | `<m>_post` |
|---|---|---|
| `<api>_proxy` | before forwarding the call | after the call returns |
| `<proto>_mon_xtor_bridge` (pins) | first cycle with `valid` | the handshake |

There is no separate monitor API. A monitor is a producer of listener calls.

### `<api>_listener_base`

The listener with empty bodies. Extend it and override only the events you need.

```systemverilog
// axi4_req_if_listener with default bodies: override only the methods you need.
virtual class axi4_req_if_listener_base #(axi4_param_t P = AXI4_PARAM_DEFAULT) implements axi4_req_if_listener #(P);
    ...
    virtual function void aw_pre(input aw_t t);
    endfunction
    virtual function void aw_post(input aw_t t);
    endfunction
    ...
endclass
```

Use (`tests/env/axi4_l1_cell.sv`):

```systemverilog
class rsp_rec extends axi4_rsp_if_listener_base #(P);
    int unsigned n_pre[5], n_post[5];
    virtual function void b_post(input b_t t); n_post[B_I]++; endfunction
    ...
endclass
```

### `<api>_listener_fanout`

A listener that forwards every call to a list, so one source feeds several consumers.
`add_listener(l)`, `remove_listener(l)`; held as interface-class handles, never cast.

```systemverilog
class axi4_req_if_listener_fanout #(axi4_param_t P = AXI4_PARAM_DEFAULT) implements axi4_req_if_listener #(P);
    ...
    axi4_req_if_listener #(P) m_listeners[$];
    function void add_listener(axi4_req_if_listener #(P) l);
        m_listeners.push_back(l);
    endfunction
    ...
    virtual function void aw_pre(input aw_t t);
        foreach (m_listeners[i]) m_listeners[i].aw_pre(t);
    endfunction
    ...
endclass
```

`axi4_rules` (`src/rules/axi4_rules.svh`) exposes its rule set as one `req` and one `rsp`
fan-out; `axi4_mon_xtor_bridge` publishes through two.

### `<api>_base`

The API with default bodies, for stubs and partial models.

| Interface kind | Default body |
|---|---|
| API (`fw_api`, channel API, `include`d) | `$error("<api>_base::<m>: not implemented")`, outputs set to zero, a function returns zero |
| Listener (`fw_listener`) | empty |

`(* fw_default = "empty" | "error" *)` on the API class or a method overrides the default.

```systemverilog
virtual class axi4_xact_if_base #(axi4_param_t P = AXI4_PARAM_DEFAULT) implements axi4_xact_if #(P);
    ...
    virtual task read(input addr_t addr, input int unsigned beats, input attr_t attr, output data_t data [$], output axi4_resp_e resp);
        $error("axi4_xact_if_base::read: not implemented");
        data = {};
        resp = axi4_resp_e'(0);
    endtask
endclass
```

With `fw_default = "empty"` on a method (`tests/weave/synth/weave_synth_pkg.sv`, woven in
`rundir/fw.proto.axi.suites.weave-woven`):

```systemverilog
virtual class syn_if_base #(type T = int, int N = 4) implements syn_if #(T, N);
    ...
    virtual function void hint(input T t);
    endfunction
    virtual function bit [3:0] peek();
        $error("syn_if_base::peek: not implemented");
        return '0;
    endfunction
endclass
```

Use: `axi4_mgr_adapter extends axi4_rsp_if_base #(P) implements axi4_burst_req_if #(P)`
(`src/behav/axi4_mgr_adapter.svh`). SV has single class inheritance, so a class that needs
two APIs extends one base and implements the other directly.

### `<api>_proxy`

Implements the API by forwarding to `m_target`, calling every listener's `_pre` before
and `_post` after. `new(target = null)`; `add_listener`, `remove_listener`. The proxy is
where the class layer is observed: abstractor handles expose one per direction.

```systemverilog
class axi4_req_if_proxy #(axi4_param_t P = AXI4_PARAM_DEFAULT) implements axi4_req_if #(P);
    ...
    axi4_req_if #(P) m_target;
    axi4_req_if_listener #(P) m_listeners[$];
    ...
    function new(axi4_req_if #(P) target = null);
        m_target = target;
    endfunction
    virtual task aw(input aw_t t);
        foreach (m_listeners[i]) m_listeners[i].aw_pre(t);
        m_target.aw(t);
        foreach (m_listeners[i]) m_listeners[i].aw_post(t);
    endtask
    ...
endclass
```

Use (`tests/env/axi4_l2_env.sv`): `axi4_req_if_proxy #(P) isub_px = new(isub);`.

### `<api>_imp #(P, type IMP)`

Implements the API by forwarding each method to `m_imp`, an object of any class with
methods of the same names and signatures. It replaces the `_IMP` macros for a component
with one export per API type (a per-field form is planned, design §4.4).

```systemverilog
class axi4_req_if_imp #(axi4_param_t P = AXI4_PARAM_DEFAULT, type IMP = int) implements axi4_req_if #(P);
    ...
    IMP m_imp;
    function new(IMP imp);
        m_imp = imp;
    endfunction
    virtual task aw(input aw_t t);
        m_imp.aw(t);
    endtask
    ...
endclass
```

Use (`tests/unit/weave_unit_test.sv`): `axi4_xact_if_imp #(P, plain_mem #(P)) ip = new(m);`,
where `plain_mem` implements nothing. The rv pilot uses fw-hdl's
`fw_rv_target_if_imp #(data_t, sink)` the same way (`tests/rv_pilot/sink.svh`).

## Per-bundle derivatives

### `<proto>_req_if_inbox`, `<proto>_rsp_if_inbox`

The channel API as a set of queues, one `fw_inbox` per channel (`<ch>_in`). Each method
`put`s the beat; a test `get`s it. Setting `<ch>_in.stall` makes the method block, so
behind a transactor bridge that channel's READY stays low. `clear()` empties all queues;
`idle()` is 1 when all are empty. Extends `<api>_base`.

```systemverilog
class axi4_rsp_if_inbox #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rsp_if_base #(P);
    fw_inbox #(b_t) b_in = new;
    fw_inbox #(r_t) r_in = new;

    virtual task b(input b_t t);
        b_in.put(t);
    endtask
    ...
    function bit idle();
        return b_in.size() == 0 && r_in.size() == 0;
    endfunction
endclass
```

Use: the far ends of the back-to-back test (`tests/env/axi4_xtor_b2b.sv`:
`mb = new(u_mgr.u_if, m_in);`).

### `<proto>_sp`

The field table: name, width and direction of every pin, built at construction with
optional (`fw_opt`) fields dropped. Extends `fw_sp_base` (`fw_proto/src/fw_sp_base.svh`:
`add_field`, `n_fields`, `field_index`, `bits(dir)`, …). Virtual; one subclass per role.
`proto()` is `"axi4"`; `param_lit()` is `P` as a literal, for the emitter.

```systemverilog
virtual class axi4_sp #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_sp_base;
    ...
    protected function void build_fields();
        ...
        if (P.ID_W != 0) add_field("awid", $bits(aw.id), FW_FWD);
        add_field("awaddr", $bits(aw.addr), FW_FWD);
        ...
        if (P.AWUSER_W != 0) add_field("awuser", $bits(aw.user), FW_FWD);
        fw_rv_ch #(axi4_types #(P)::aw_t)::add_ctl(this, "aw", FW_FWD);
        ...
    endfunction
endclass
```

`fw_rv_ch::add_ctl` adds `<ch>valid` and `<ch>ready`. Not extended by users.

### `<proto>_<role>_sp`

The struct port of one role, the type an RTL component's or extern component's port is
declared with (`axi4_sub_sp #(P) s;`). Typed connections:

| Method | Does |
|---|---|
| `link(<other role>_sp peer)` | joins two opposite ports at one level (one bundle of nets) |
| `bind_inner(<same role>_sp child)` | makes a child's port this one, one level in |
| `connect(<same role>_socket api)` (`xtor` only) | inserts `<socket name>_abs` (the opposite role's abstractor) under the owner's parent, serving `api`, and links it to this port; returns it |

```systemverilog
class axi4_mgr_sp #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_sp #(P);
    ...
    function void link(axi4_sub_sp #(P) peer);
        do_link(peer);
    endfunction
    ...
    function axi4_sub_abs #(P) connect(axi4_mgr_socket #(P) api);
        axi4_sub_abs #(P) a;
        ...
        a = new({api.get_name(), "_abs"}, m_owner.get_parent());
        a.serve(api);
        a.sp.link(this);
        return a;
    endfunction
endclass
```

Use (`tests/ip/axi_ram/ram_api.svh`): `void'(core.s.connect(s));` puts an
`axi4_mgr_abs` named `s_abs` between the API socket `s` and the RTL port `core.s`.

### `<proto>_payloads`

Static helpers per payload type, named by channel. Absent fields follow `fw_opt`.

| Function | Does |
|---|---|
| `<ch>_sprint(v)` | `"id=0x.. addr=0x.. ..."`, absent fields skipped |
| `<ch>_compare(a, b, diff)` | 1 when equal; else 0 and the differing fields in `diff`; absent fields skipped |
| `<ch>_mask(v)` | `v` with absent fields zeroed: what a link with pins delivers |

```systemverilog
static function axi4_types #(P)::aw_t aw_mask(axi4_types #(P)::aw_t v);
    axi4_types #(P)::aw_t m = v;
    if (!(P.ID_W != 0)) m.id = '0;
    if (!(P.HAS_QOS != 0)) m.qos = '0;
    ...
    return m;
endfunction
```

Use: `typedef axi4_payloads #(P) pl;` in the adapters (`src/behav`), then `pl::aw_mask(a)`.

### `<proto>_<payload>_bits(P)` (in `<fw_defs_pkg>_woven`)

One function per payload struct: its width, as packed. Class-free, so RTL can use it.
Emitted whenever the bundle sets `fw_defs_pkg`.

```systemverilog
package fw_proto_axi4_defs_pkg_woven;
  ...
  function automatic int unsigned axi4_b_t_bits(axi4_param_t P);
      return (w1(P.ID_W)) + $bits(axi4_resp_e) + (w1(P.BUSER_W));
  endfunction
```

## Transactors (`xtor: true`)

One set per role and one for the monitor (`mon`). Only the `fw_rv_ch` family is
supported, with exactly two roles. The modules are files beside the woven package.

| Name | What it is |
|---|---|
| `<proto>_<role>_xtor_core` | synthesizable module, class-free: one fw-hdl rv core per channel (initiator for the channels the role sends, target for the ones it receives, monitor for all in `mon`), the flat payload spliced onto the pins; `<ch>_up_*` links to the class side |
| `<proto>_<role>_xtor` | the core plus one fw-hdl rv interface per channel; same pins; instance `u_if` is the class side |
| `<proto>_<role>_xtor_if` | interface holding `chans` and `bound`; the bridge's vif |
| `<proto>_<role>_xtor_chans` | class holding the channel transactors' vifs (an interface may not hold vifs); `set_knob("<ch>.depth" \| "<ch>.max_gap", v)` (`mon`: `depth` only) |
| `<proto>_<role>_xtor_bridge` | class: the pins as the role's channel API (below) |

Pin names are the field table's, and the protocol checker's, so `.*` connects.
Optional fields keep their pins, `w1` wide, tied to 0. Clock and reset pins come from
`fw_clock` and `fw_reset_n` (here `aclk`, `aresetn`).

```systemverilog
module axi4_mgr_xtor_core
    import fw_proto_axi4_defs_pkg::*, fw_proto_axi4_defs_pkg_woven::*;
#(axi4_param_t P = AXI4_PARAM_DEFAULT) (
    input  logic aclk,
    input  logic aresetn,
    output logic awvalid,
    input  logic awready,
    output logic [w1(P.ID_W)-1:0] awid,
    ...
    input  logic [axi4_aw_t_bits(P)-1:0] aw_up_data,
    ...
);
    ...
    fw_rv_initiator_xtor_core #(.W(AW_BITS)) u_aw (.clock(aclk), .reset(!aresetn), ...);
    assign awid = (P.ID_W != 0) ? aw_d[AW_ID_LSB +: (w1(P.ID_W))] : '0;
    assign awaddr = aw_d[AW_ADDR_LSB +: (P.ADDR_W)];
    ...
```

The wrapper fills `u_if` at time 0:

```systemverilog
    initial begin
        u_if.chans = new(u_aw_if, u_w_if, u_b_if, u_ar_if, u_r_if);
        u_if.bound = 1;
    end
endmodule : axi4_mgr_xtor
```

### `<proto>_<role>_xtor_bridge`

For a role: implements the API that role sends; an outbound call is
`vif.chans.<ch>.send(t)`. `run()` forks one `recv → m_<api>.<ch>(t)` loop per received
channel, so a stalled channel holds up no other. `new(vif, <received API> = null)`.

```systemverilog
class axi4_mgr_xtor_bridge #(axi4_param_t P = AXI4_PARAM_DEFAULT) implements axi4_req_if #(P);
    ...
    virtual axi4_mgr_xtor_if #(P) vif;
    axi4_rsp_if #(P) m_rsp;
    ...
    virtual task aw(input aw_t t);
        wait (vif.bound);
        vif.chans.aw.send(t);
    endtask
    ...
    virtual task run();
        wait (vif.bound);
        fork
            forever begin b_t t; vif.chans.b.recv(t); m_rsp.b(t); end
            forever begin r_t t; vif.chans.r.recv(t); m_rsp.r(t); end
        join
    endtask
endclass
```

For `mon`: implements no API. It has a `req` and a `rsp` listener fan-out; `run()` calls
`<ch>_pre` on a beat's first valid cycle and `<ch>_post` on its handshake.

```systemverilog
class axi4_mon_xtor_bridge #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    ...
    axi4_req_if_listener_fanout #(P) req = new();
    axi4_rsp_if_listener_fanout #(P) rsp = new();
    ...
            forever begin
                aw_t t;
                bit first, xfer;
                vif.chans.aw.get_ev(t, first, xfer);
                if (first) req.aw_pre(t);
                if (xfer) req.aw_post(t);
            end
```

Use (`tests/env/axi4_xtor_b2b.sv`): `monb = new(u_mon.u_if); monb.req.add_listener(rq);`,
then `fork mb.run(); sb.run(); monb.run(); join_none`.

## Abstractor glue (`xtor: true`)

What lets a class description put RTL behind the bundle's APIs
([p6-abstractors.md](p6-abstractors.md)). The abstractor's role is the opposite of the
RTL port's: an RTL subordinate port is driven by a manager abstractor.

### `<proto>_<role>_socket`

The role's API endpoint on an fw-hdl component. The first role's is an `fw_socket` (calls
the fwd API, provides the rev one); the second's an `fw_mirror` of the same pair. Peers
connect with fw-hdl's `connect()`.

```systemverilog
class axi4_sub_socket #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_mirror #(axi4_req_if #(P), axi4_rsp_if #(P));
    function new(string name, fw_component parent, axi4_req_if #(P) imp = null);
        super.new(name, parent, imp);
    endfunction
endclass
```

Use (`tests/ip/axi_ram/ram_api.svh`, `ram_top.svh`): `axi4_sub_socket #(P) s;` …
`tb.m.connect(dut.s);`.

### `<proto>_<role>_abs`

The description-time abstractor, an `fw_boundary` implementing the API its role sends.
`serve(socket)` makes it the endpoint's imp. Nothing runs through it: its methods wait on
an event that never fires. Its string tables tell the emitter what to instantiate
(`xtor_module()`, `vif_type()`, `handle_type()`, `xtor_clk_rst()`; `pin_sp()` is its
`sp`, the struct port it links to the RTL). Inserted by `<role>_sp::connect()`; not used
directly.

```systemverilog
class axi4_mgr_abs #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_boundary implements axi4_req_if #(P);
    ...
    axi4_mgr_sp #(P) sp;
    ...
    virtual task aw(input aw_t t);
        @m_never;
    endtask
    ...
    virtual function string xtor_module(); return "axi4_mgr_xtor"; endfunction
    virtual function string handle_type();
        return {"axi4_mgr_abs_h #(", sp.param_lit(), ")"};
    endfunction
endclass
```

### `<proto>_<role>_abs_h`

The run-time abstractor, an `fw_component` and `fw_runnable` that replaces `_abs` in the
emitted design. It holds the bridge and a proxy per direction (`req`, `rsp`): calls on
the endpoint go through one proxy to the pins, beats from the pins through the other to
the endpoint's peer. At construction it registers its proxies with `<proto>_observers`
under its path. At `run()` it applies the knobs set for its path in `fw_proto_cfg`
(`"<ch>.depth"`, `"<ch>.max_gap"`) to the channel transactors, then runs the bridge.

```systemverilog
class axi4_mgr_abs_h #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends fw_component implements fw_runnable;
    axi4_mgr_xtor_bridge #(P) bridge;
    axi4_req_if_proxy #(P) req;
    axi4_rsp_if_proxy #(P) rsp;
    ...
    function new(string name, fw_component parent, virtual axi4_mgr_xtor_if #(P) vif);
        super.new(name, parent);
        rsp = new();
        bridge = new(vif, rsp);
        req = new(bridge);
        axi4_observers #(P)::attach(fw_rel_path(this), req, rsp);
        parent.add_runnable(this);
    endfunction
```

Use (`tests/ip/axi_ram/axi_ram_tb.sv`):
`fw_proto_cfg::set_int("dut.s_abs", "r.max_gap", max_gap);`.

### `<proto>_observers`

Static registry joining listeners to abstractor handles by path. A test calls
`add(path, req_listener, rsp_listener)` (either may be null); each handle calls
`attach(path, req_proxy, rsp_proxy)` when built. Whichever comes second joins them, so the
order does not matter as long as both come before traffic. `unused()` names the paths no
handle took (a misspelled path, or another `P`).

```systemverilog
class axi4_observers #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    ...
    static function void add(string path, axi4_req_if_listener #(P) req, axi4_rsp_if_listener #(P) rsp);
    ...
    static function void attach(string path, axi4_req_if_proxy #(P) req, axi4_rsp_if_proxy #(P) rsp);
    ...
    static function string unused();
```

Use (`tests/ip/common/ip_axi_rules.svh`): `axi4_observers #(P)::add(path, r.req, r.rsp);`.

## When to use which

| You want | Use |
|---|---|
| To observe an API's calls (rule, monitor, scoreboard, recorder) | extend `<api>_listener_base`; or implement `<api>_listener` when you must cover every event, or need two listeners (`axi4_rule` implements both channel listeners) |
| To feed one event source to several consumers | `<api>_listener_fanout` |
| To see the calls on an existing connection | put an `<api>_proxy` in it and `add_listener` |
| A stub or partial model of an API | extend `<api>_base`, override what you use; the rest report an error |
| To expose a class with the right methods as the API, without `implements` | `<api>_imp #(P, YourClass)` |
| A scripted channel endpoint in a test (queue, stall) | `<proto>_req_if_inbox` / `<proto>_rsp_if_inbox` |
| A forwarding object that must cover every method | implement the API directly (as `_proxy` and the bridges do) |
| To print, compare or mask a beat | `<proto>_payloads::<ch>_sprint/_compare/_mask` |
| A struct port on an RTL or extern component | `<proto>_<role>_sp`; `link`/`bind_inner` between ports; `connect(socket)` to a class endpoint |
| A class-level API endpoint on a component | `<proto>_<role>_socket` |
| Pins driven from class code in a hand-built bench | `<proto>_<role>_xtor` + `<proto>_<role>_xtor_bridge`; `<proto>_mon_xtor` + bridge to observe |
| Listeners on an abstractor inserted by `connect()` | `<proto>_observers::add(path, …)` |
| Back-pressure on an inserted abstractor | `fw_proto_cfg::set_int(path, "<ch>.max_gap", n)` |

Not generated, written by hand on top of these (`src/behav`): the burst API sockets
(`axi4_burst_mgr_socket`, `axi4_burst_sub_socket`), the adapters between the burst and
channel APIs (`axi4_mgr_adapter`, `axi4_sub_adapter`), `axi4_burst_blocking`, the
`axi4_xact_if` shims and the memory model.

## Regenerating

`dfm run woven` and `dfm run woven-xtor` from the repo root. The weave's up-to-date check
covers the core sources but not the weaver's Python source: after editing
`fw_proto/python/fw_proto_weave`, delete `rundir/fw.proto.axi.*woven*` first. The
generated output is also checked in as goldens under `fw_proto/python/tests/golden/`
(`pytest fw_proto/python/tests`): the `woven` form of both packages, the nine transactor
files and `weave_synth_pkg_woven.sv`.
