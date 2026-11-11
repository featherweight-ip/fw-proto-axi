# P6: abstractors and extern wrapping, design of the port

Status 2026-11-11: P6.1-P6.3 done; `axi_ram`, `demofull` and `axi_crossbar` pass
(`dfm run ip`, tests/ip). Progress is tracked in [plan-new-style.md](plan-new-style.md)
§1 and §5 (P6).

Source of the port: `featherweight-hdl/fw-hdl-sv-weave` working copy at fw-hdl
`6f45fe0` plus uncommitted changes (`src/fw_extern.svh`,
`tests/abstractor_proto/`). Reconcile here when that packet lands.

## 1. What the prototype is

Two passes over one class-tree description:
1. **Generate.** The tree is built and connected (nothing runs). The emitter
   walks it and writes one module per RTL structural class (the netlist), and
   `<top>_sim.sv`: a package of shells plus a module with the RTL, one
   transactor per abstractor, and the run-time root.
2. **Run.** The emitted files are compiled with the test. Each class that wraps
   RTL is replaced, through the factory, by its *API shell*: a subclass that
   builds only its API endpoints and binds them to transactor handles.

Kinds of component (all `fw_realized`, holding struct ports):
- `fw_extern_component`: an existing module; `extern_map()` names its pins.
- `fw_rtl_structural`: RTL assembled from children; emitted as a module.
- `fw_boundary`: an abstractor (API on one side, a struct port on the other).
  Inserted by `<struct port>.connect(<API endpoint>)`.

## 2. Mapping onto the new style

| Prototype | New style | Where |
|---|---|---|
| `fw_sp_base` (owner, `m_is_in`, string field lists) | the P3 `fw_sp_base`, given an owner and made an `fw_endpoint` (so `fw_extern_map.pin/prefix` take it). Role index, `fw_field_t` table unchanged | `fw_proto_pkg` (now imports `fw_hdl_pkg`) |
| `fw_rv_sp_in/out`, `FW_RV_FIELDS` | the generated `axi4_mgr_sp`/`axi4_sub_sp` (field table from the bundle, typed `link`/`bind_inner`) | woven, unchanged but for the owner argument |
| `fw_realized`, `fw_extern_component`, `fw_rtl_structural`, `fw_boundary`, `fw_emitter`, `fw_proto_factory`/`_reg`, `fw_proto_cfg` | ported, protocol-free | `fw_proto_pkg` |
| `fw_rv_initiator_abs`, `fw_rv_target_abs` (hand-written per protocol) | generated per role: `axi4_<role>_abs` (P6.3) | woven-xtor |
| `connect(fw_export/fw_port)` on the struct port | generated per role: `connect(<role link>)`, inserting `<link>_abs` | woven-xtor |
| one-way rv API (port or export) | the two-way role link: `fw_socket #(req, rsp)` for a manager, `fw_mirror #(req, rsp)` for a subordinate (fw-hdl's pair) | woven-xtor typedefs `axi4_mgr_socket`, `axi4_sub_socket` |
| `tname()` = `logic [w-1:0]` | `#(.P(<n>'h<hex>))`: the struct port prints its own specialization (`param_lit()`, generated) | emitter + woven |
| transactor `clock`/`reset` | the bundle's `fw_clock`/`fw_reset_n`: `.aclk(clock), .aresetn(!reset)` (string table) | woven |
| `fw_rv_target_handle` (stall knob from config) | generated `axi4_<role>_abs_h`: an `fw_component` holding the xtor bridge and a proxy per direction; knobs from `fw_proto_cfg` at its path go to `chans.set_knob` | woven-xtor |

### The two-way link

The abstractor sits on the class side of a wrapper. Which transactor it uses is
the *opposite* role of the RTL port it drives:

| RTL struct port | wrapper's API endpoint | abstractor's pin side | transactor, bridge |
|---|---|---|---|
| `axi4_sub_sp` (e.g. `axi_ram`'s `s_axi`) | `axi4_sub_socket` (mirror: provides `req`, calls `rsp`) | `axi4_mgr_sp` | `axi4_mgr_xtor`, `axi4_mgr_xtor_bridge` |
| `axi4_mgr_sp` (e.g. a crossbar `m_axi`) | `axi4_mgr_socket` (socket: calls `req`, provides `rsp`) | `axi4_sub_sp` | `axi4_sub_xtor`, `axi4_sub_xtor_bridge` |

Run time, `axi4_mgr_abs_h` for the first row: the mirror's export imp is a
`req` proxy whose target is the bridge; the bridge's `m_rsp` is a `rsp` proxy
whose target is the mirror's resolved port (set when the handle starts to
run, after connect). Tests and rules attach listeners to the two proxies by
path (`dut.s_abs`).

### Transactor pins

The generated transactors have every AXI pin (absent fields one bit wide). The
emitter connects the fields the struct port has; the rest are left off.

## 3. Changes from the prototype

- **Resolution order (brief §8).** The prototype needs `dut` built before
  `prod` because an `fw_port` resolves during connect, child by child. Kept as
  a documented rule for now (it is fw-hdl's resolution, not this code's).
- **No `$cast` to an interface class.** The emitter casts only between class
  types (`fw_component` to `fw_realized`/`fw_boundary`), as the prototype does.
- **Monitors.** `fw_rv_monitor` has no AXI counterpart in the P6 tests. The
  generic `fw_boundary` keeps `tap()`, so a generated monitor can be added later
  (A5); none is generated now.
- **Emitted text.** The emitter writes SV with `$fdisplay`, at run time, so
  Jinja does not apply to it. The Jinja decision is about the *weaver's* text
  (`xtors.py`, and the new `abs.py`); see the plan.

## 4. Pin maps, as built

- `x.prefix(sp, "s_axi_")`: one line per port for an IP whose pins are named after the
  fields. `.upper()` for upper-case names (`S_AXI_AWADDR`), `.rename(field, name)` for the
  odd one, `.slot(k)` when the port is slot k of packed-vector pins (a crossbar's
  `s_axi_awid` holds every slave port's ID).
- `x.pin(pin, sp, field, msb, lsb, slot)` for single pins and field slices.
- `x.tie(pin, value)`, `x.open(pin)` for pins outside the bundle (USER pins of an IP
  built without USER, a memory port).
- The emitter checks that every bit of every field is mapped once, that a pin is mapped
  once (per slot), and that a pin's slots are 0..n-1. Parameter values that do not fit
  32 bits are written sized.

## 5. The test of each IP (tests/ip)

Two passes per IP (`<ip>-gen`, `<ip>-run`), plus `<ip>-netlist` (emitted netlist against
a hand-written one) and `<ip>-synth` (Yosys). The class side uses the shared bench
`common/ip_axi_tb_pkg.sv`: a manager on an `axi4_mgr_socket` (manager adapter, blocking
shim, reference memory) and, for manager ports leaving the module tree, a memory component
on an `axi4_sub_socket`.

| IP | What it adds |
|---|---|
| `axi_ram` | one extern, one prefix line; stalls set by path reach the pins |
| `demofull` | upper-case pins, active-low reset, a tied/open non-AXI port |
| `axi_crossbar` | slots of packed pins, ID widening, both abstractor roles, responses out of order across IDs |

