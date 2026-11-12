# Writing a protocol package

How to build the next protocol package in the new style, for example AXI4-Lite or APB.
AXI4 is the worked example: each step names the AXI4 files to copy from.

Background:
- [design-new-style.md](design-new-style.md): the design and its reasons.
- [core-spec.md](core-spec.md): a reading guide to the AXI4 core.
- [derived-classes.md](derived-classes.md): every generated class and when to extend it.
- [rules.md](rules.md): the rule vocabulary and the AXI4 rules.
- [reference-ips.md](reference-ips.md), [p6-abstractors.md](p6-abstractors.md): extern
  wrapping, pin maps, abstractors.
- `fw_proto/README.md`: the attributes and the weaver options.

## The idea in one paragraph

You write a short core by hand: the parameters, the channel payloads, the port bundle
and the transaction-level API. sv-weave, with the `fw_proto` weavers, derives the rest:
bases, listeners, proxies, fan-outs, channel APIs, field tables, struct ports, the
pin-level transactors and the abstractor glue. You then write the code that cannot be
derived: the adapters between the transaction API and the channels, a reference model,
and the rules. The test of the split: adding a field to a payload is a one-line change
to the core.

## 0. Check the protocol fits

| Question | AXI4 | AXI4-Lite | APB |
|---|---|---|---|
| Channels, each one handshake | 5, ready/valid | 5, ready/valid | 1 request/response phase pair (PSEL, PENABLE, PREADY) |
| Handshake family in `fw_proto` | `fw_rv_ch` | `fw_rv_ch` | none yet |
| Two roles | `mgr,sub` | `mgr,sub` | `mgr,sub` (requester, completer) |
| Pin-level transactors generated | yes | yes | no: `xtors.py` supports `fw_rv_ch` only |

If every channel is ready/valid, everything below applies as is. If not (APB), you need
a new channel family in `fw_proto/src` (like `fw_rv_ch`: its control fields and
signal-level rule) and a transactor generator for it, beside
`fw_proto/python/fw_proto_weave/xtors.py`, built on transactors in fw-hdl. That is work
on `fw_proto`, not on the package. The class layer (steps 1-5, 7, 8) works without it.

## 1. Lay out the repo

Copy the AXI4 tree. One class per `.svh`, named after the class, `include`d by its
package; `<pkg>.sv` keeps imports, typedefs and free functions.

```
src/core/<p>_*.svh, fw_proto_<p>_defs_pkg.sv, fw_proto_<p>_core_pkg.sv
src/weave/sv-weave.yaml, sv-weave-xtor.yaml, xtor_weave_top.sv
src/behav/      adapters, model, sockets, shims
src/rules/      rule base, rule node, rules, the set
src/flow.yaml
tests/{unit,env,weave,lint,formal,ip}/
```

`fw_proto/` is protocol-agnostic and stays where it is until it moves to fw-hdl (plan
D2). Do not copy it; depend on it (`fw-proto-sv` in `fw_proto/flow.yaml`).

## 2. The class-free package: `fw_proto_<p>_defs_pkg`

Example: `src/core/fw_proto_axi4_defs_pkg.sv`.

It holds what RTL needs, with no classes, so sv2v and Yosys read it:
- **One parameter struct**, `<p>_param_t`, and its default. Every class and module takes
  one value of it, `#(<p>_param_t P = <P>_PARAM_DEFAULT)`. The weavers re-emit this
  header verbatim and the emitter prints it as one literal; don't add a second
  parameter.
- A width of 0 means the signal is absent. A presence flag is `int unsigned` 0/1
  (`HAS_QOS`), so every optional field follows one rule.
- `w1(w)`: the width of a field that may be absent (one bit, held at 0).
- The encodings (enums) and pure functions of them (AXI4: burst arithmetic). Rules and
  formal use these functions, so they must stay synthesizable.

## 3. The class package: `fw_proto_<p>_core_pkg`

Examples: `src/core/fw_proto_axi4_core_pkg.sv` and the files it includes.

### 3.1 Payloads

One parameterized class holding a packed struct per channel
(`src/core/axi4_types.svh`):
- Member names are the protocol's names **without the channel prefix** (`addr`, not
  `awaddr`). The bundle's channel name supplies the prefix, so pin names come out right
  (`aw` + `addr`).
- Optional members carry `(* fw_opt = "<P member>" *)` and are sized `w1(P.<member>)`.
  The field has pins only when `P.<member> != 0`.
- Two channels that differ in one width need two structs (`aw_t`/`ar_t`: separate USER
  widths).
- Struct packing is the order the transactors put on the wire, and the formal
  harness's stream layout. Pick it once.

### 3.2 The bundle

`src/core/axi4_bundle.svh`:

```systemverilog
(* fw_proto_bundle = "axi4", fw_roles = "mgr,sub", fw_clock = "aclk", fw_reset_n = "aresetn",
   fw_defs_pkg = "fw_proto_axi4_defs_pkg" *)
class axi4_bundle #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    typedef axi4_types #(P) t;
    (* fw_fwd *) fw_rv_ch #(t::aw_t) aw;
    (* fw_fwd *) fw_rv_ch #(t::w_t)  w;
    (* fw_rev *) fw_rv_ch #(t::b_t)  b;
    (* fw_fwd *) fw_rv_ch #(t::ar_t) ar;
    (* fw_rev *) fw_rv_ch #(t::r_t)  r;
endclass
```

| Attribute | Meaning |
|---|---|
| `fw_proto_bundle = "<p>"` | the bundle; `<p>` prefixes every derived name |
| `fw_roles = "<a>,<b>"` | the two roles; `<a>` drives the `fw_fwd` channels. Not `mon` (the generated monitor's name) |
| `fw_fwd` / `fw_rev` | a channel and its direction relative to role `<a>` |
| `fw_clock`, `fw_reset_n` (or `fw_reset`) | the transactors' clock and reset pins |
| `fw_defs_pkg` | the class-free package holding `<p>_param_t`; needed for the RTL cores and `xtor` |

Cross-channel facts (AXI4: `len`+1 W beats per AW, B after the last W) do not go in
the bundle. They are rules (step 7).

For AXI4-Lite: five channels, payloads `addr`+`prot`, `data`+`strb`, `resp`; no ID, no
`len`, no `last`. Give it its own bundle. Don't model it as AXI4 with absent fields:
`len`, `size`, `burst` and `last` are not optional in AXI4.

### 3.3 The transaction-level API

The only APIs written by hand; the channel APIs (`<p>_req_if`, `<p>_rsp_if`) come from
the bundle. Examples: `src/core/axi4_burst_req_if.svh`, `axi4_burst_rsp_if.svh`,
`axi4_xact_if.svh`.

- Mark each with `(* fw_api *)`.
- **Split by direction** (D11): a request interface the manager calls and a response
  interface the subordinate calls back. A request returns once accepted; responses
  arrive as calls. No thread waits per outstanding transaction. A blocking form is a
  shim on top (`src/behav/axi4_burst_blocking.svh`).
- **Use the channel payload types** in the protocol's own API, so a new payload field
  reaches it with no other edit. A plain-argument convenience API (`axi4_xact_if`) is
  optional, and implemented by a shim.
- Signatures use only **class-local typedef names** (`typedef axi4_types #(P)::aw_t aw_t;`
  inside the interface class). sv-weave prints a specialized type resolved to one
  width, and derived classes re-declare the same local typedefs.
- Conventions (pyhdl-if-friendly): a task if it may block, else a function; `input` and
  `output` only; no `ref`, events or class handles; packed types and queues of them.
- `(* fw_default = "empty" *)` on a method that a stub may ignore. API methods default to
  an error in `<api>_base`.
- Wrap the interface classes in `verilator lint_off UNUSEDSIGNAL` / `UNDRIVEN` (their
  arguments are prototypes), as `fw_proto_axi4_core_pkg.sv` does.

For APB the API is one request with a response (`read(addr, data, err)`,
`write(addr, data, strb, err)`): there is only one transfer in flight, so a split API
buys nothing. For AXI4-Lite keep the split: AXI4-Lite allows several outstanding.

## 4. The weave

### 4.1 Config

Two configs, one per weave. Copy `src/weave/sv-weave.yaml` and
`src/weave/sv-weave-xtor.yaml`; change only `packages.include`:

```yaml
sv-weave:
  binding: fw_proto_weave:FwProtoBinding
  plugin-path: [../../fw_proto/python]
  packages:
    include: [fw_proto_<p>_core_pkg]
  sources:
    files: [xtor_weave_top.sv]
    top: [xtor_weave_top]
  weavers:
  - name: fw_proto_weave:FwProtoWeaver
    options:
      xtor: true            # sv-weave-xtor.yaml only
```

The empty top (`src/weave/xtor_weave_top.sv`) is required. fw-hdl's `fw_root.sv` only
elaborates under a top, and slang must not elaborate the generated wrappers (see Known
limits).

Weaver options (`fw_proto/README.md`): `include` (interface classes to treat as APIs
without the attribute; `tests/weave/rv/sv-weave.yaml` weaves fw-hdl's rv APIs this way),
`derive` (a subset of `listener, base, proxy, imp, bundle`), `xtor`.

### 4.2 Flow tasks

Copy `src/flow.yaml`:

| Task | Uses | Needs | Gives |
|---|---|---|---|
| `defs` | `std.FileSet` | | the class-free package |
| `core` | `std.FileSet` | `fw-proto-sv`, `defs` | the class package |
| `woven` | `svweave.Weave` | `core` | `fw_proto_<p>_core_pkg_woven` and `fw_proto_<p>_defs_pkg_woven` |
| `woven-xtor` | `svweave.Weave` | `core`, `fw-hdl.hdl.sv-src`, `fw-hdl.hdl.rv-src` | the above plus the transactors and abstractor glue |
| `behav`, `behav-xtor` | `std.FileSet` | `woven` / `woven-xtor` | the behaviour package |
| `rules`, `rules-xtor` | `std.FileSet` | `woven` / `woven-xtor` | the rules package |

An image uses `woven` or `woven-xtor`, never both: two weaves in one image both define
`sv_weave_init_pkg` (unless each sets `init: false` and an `svweave.Init` follows them,
sv-weave 0.2). That is why everything built on the woven package comes in two
forms.

### 4.3 What you get

`dfm run woven`, then read `weave-report.md` and the woven package in the task's rundir.
[derived-classes.md](derived-classes.md) lists every class. In short:

| From | Derived |
|---|---|
| each `fw_api`, and the two channel APIs | `<api>_base`, `_listener` (`<m>_pre`/`<m>_post`), `_listener_base`, `_listener_fanout`, `_proxy`, `_imp` |
| the bundle | `<api>_inbox` per channel API; `<p>_sp` (field table); `<p>_<role>_sp` (typed `link`/`bind_inner`); `<p>_payloads` (`<ch>_sprint`, `_compare`, `_mask`) |
| `fw_defs_pkg` | `<p>_<payload>_bits(P)` in `<defs>_woven` |
| `xtor: true` | `<p>_<role>_xtor_core.sv`, `<p>_<role>_xtor.sv`, `<p>_<role>_xtor_if.sv` per role and for `mon`; `<p>_<role>_xtor_chans`, `<p>_<role>_xtor_bridge`, `<p>_mon_xtor_bridge`; `<p>_<role>_socket`, `<p>_<role>_abs`, `<p>_<role>_abs_h`, `<p>_observers`, and `connect()` on the role ports |

Edited a weaver? Delete `rundir/*woven*` first: the weave's up-to-date check does not
see weaver source changes.

## 5. Behaviour

Hand-written, on the generated `_base` classes; no macros. Examples in `src/behav/`
(package `fw_proto_axi4_behav_pkg.sv`):

| Class | Extends | Does |
|---|---|---|
| `axi4_mgr_adapter` | `axi4_rsp_if_base` | transaction requests in, channel beats out; responses back up, matched per ID |
| `axi4_sub_adapter` | `axi4_req_if_base` | channel beats in, transaction requests out; responses back as beats |
| `axi4_mem_model` | the burst API's base | the reference model |
| `axi4_burst_mgr_socket`, `axi4_burst_sub_socket` | `fw_socket`, `fw_mirror` | the request/response pair on a component |
| `axi4_burst_blocking`, `axi4_xact_on_burst` | | blocking shims for test writers |

Rules for this layer:
- Pass payloads through unchanged. Zero the fields `P` leaves off the pins with
  `<p>_payloads::<ch>_mask`, so a link with pins and one without deliver the same
  beats.
- Only the shims convert between the protocol's API and the convenience API.
- A response may come inside its request's call. Be ready for it before calling.
- Response calls may block. Queue them and send from one loop per response channel, so a
  stalled response never holds up the loop that receives requests.

For APB the adapters shrink to one each way, and the model is a register file or memory.

## 6. Pin-level transactors and abstractors

With `xtor: true` these are generated; there is nothing to write for a ready/valid
protocol. What you write is per IP (step 9). Configure by path:
`"<role>.<ch>.depth"`, `"<role>.<ch>.max_gap"` (`set_knob`), and through `fw_proto_cfg`
on an abstractor path (`dut.s_abs`).

## 7. Rules

The contract as listeners. Read [rules.md](rules.md) first. Examples in `src/rules/`
(package `fw_proto_axi4_rules_pkg.sv`).

1. **The rule base**, `<p>_rule` (`src/rules/axi4_rule.svh`): extends `fw_rule`,
   implements both channel listeners, and maps pre/post to accepted events. Requests
   count at `_pre` from a proxy and at `_post` from pins (`m_pins`); responses at
   `_post`. Hand-written for now; it is mechanical from the bundle (fwd = request).
2. **The rule node**, `<p>_rule_node` (`src/rules/axi4_rule_node.svh`): the fan-outs of
   both channel listeners. Also mechanical.
3. **One class per rule**, on the base. Use only `chk`, `fw_count`, `fw_flag`,
   `fw_value`, `fw_any` and pure functions from the defs package. Write `create()`. Call
   `retire()` when an instance's key is discharged. Anything else sets `m_free_form`
   (simulation only, opaque to formal). `src/rules/axi4_rule_resp_match.svh` is the
   shortest example.
4. **Signal-level rules** per channel from the family: `fw_rv_hold #(T)` inside one rule
   (`src/rules/axi4_rule_rv_hold.svh`), added only for pin sources.
5. **The set**, `<p>_rules` (`src/rules/axi4_rules.svh`): `new(where, pins, ...)`, `req`
   and `rsp` fan-outs, `n_fail()`, `first()`.

Attach to a link or proxy with `add_listener`, and to an abstractor by path through the
generated `<p>_observers` (`tests/ip/common/ip_axi_rules.svh`).

What to expect: AXI4-Lite needs `resp_match` (by count, no ID), and order is total, so
no `fw_any`. APB needs only signal-level rules (PSEL/PENABLE sequencing, stable
payload) and these need its new family's rule.

## 8. Tests

The layers (plan §6.1), each with its AXI4 example. Every class and RTL test runs over
three parameter sets: minimum (absent fields everywhere), default, and wide with
distinct widths per optional field so mix-ups show (`tests/env/axi4_test_params_pkg.sv`).

| Layer | Write | AXI4 example |
|---|---|---|
| Weaver goldens | only if you change `fw_proto` | `fw_proto/python/tests/test_weave.py` |
| Core | encodings and the defs functions | `tests/unit/types_unit_test.sv` |
| Derived classes | widths per P, proxy/listener order, fan-out, imp | `tests/unit/weave_unit_test.sv`, `tests/weave/sv-weave.yaml` |
| Bundle | field table against the protocol's pin list typed by hand (not from the bundle); role-port link; sprint/compare | `tests/unit/bundle_unit_test.sv` |
| Transactors | back to back, every beat checked at the far end and at the monitor | `tests/unit/xtor_unit_test.sv`, `tests/env/axi4_xtor_b2b.sv` |
| L1 (channels) | one link in two views, `tlm` and `xtor`; stalls by path | `tests/unit/l1_unit_test.sv`, `tests/env/{tlm,xtor}/axi4_l1_link.sv` |
| L2 (transactions) | adapters and model over the link: bursts, IDs, errors, fidelity of every field | `tests/unit/l2_unit_test.sv`, `l2_mem_unit_test.sv`, `tests/env/axi4_l2_env.sv` |
| Rules teeth | one planted bug per rule; exactly that rule fires; the report names the event | `tests/unit/rules_teeth_unit_test.sv` |
| Rules on pins | scripted pin sequences watched by the rules and by a reference checker; verdicts agree | `tests/unit/rules_pins_unit_test.sv` |
| Behaviour teeth | bugs planted in the adapters; the suites must catch them | `tests/teeth/behav_teeth.py` |
| Lint | Verilator `-Wall` at zero findings: RTL, and the generated wrappers with the class side | `tests/lint/`, `lint-waivers*.yaml` |
| Formal | the generated cores back to back (BMC, covers, planted bugs) | `tests/formal/axi4_fv.sv`, `fv_b2b.sh` |
| Reference IPs | extern + one preset line; data against the model; netlist against a hand-written one; Yosys synth | `tests/ip/`, [reference-ips.md](reference-ips.md) |

Every suite needs teeth. Run each with a planted bug once and check it fails. Most of
the misses found here (plan P6 D11 teeth) were test gaps, not code bugs.

Wire the suites into `tests/flow.yaml` and the roots in `flow.yaml` (`tests`, `smoke`,
`lint-rtl`, `ip`, `fv*`), and `ci/run.sh` runs them.

## 9. Wrapping a reference IP

[reference-ips.md](reference-ips.md) has the steps. In short: an `fw_extern_component`
naming the module, its parameters, clock and reset, and one pin rule per port
(`x.prefix(s, "s_axi_")`, `.upper()`, `.slot(k)`, `.rename()`; `tie`/`open` for pins
outside the bundle). An `<ip>_sys` (`fw_rtl_structural`) emitted as the netlist, and an
`<ip>_api` that connects each struct port to a socket, which inserts the abstractor.

Pick IPs that stress something: two naming styles and both reset polarities, a
packed-vector port (slots), something that reorders responses.

## Known limits

Found while building AXI4 (plan §8). Each has a workaround in place.

| Where | Limit | Workaround |
|---|---|---|
| Verilator | `/tools` 5.041 fails sv-weave's tests | put `packages/verilator/bin` (5.055) first on `PATH` |
| Verilator 5.055 | internal fault on a vif whose type parameter is a class-scoped type of a parameter (`virtual x_if #(ty #(P)::b_t)`) | a local `typedef ty #(P)::b_t b_t;` first (the weaver does this) |
| Verilator 5.055 | endless recursion or OOM on a class `localparam` from `$bits(type param)` in nested loop bounds and part-selects | a run-time member (`axi4_to_mem`); repro in `repro/verilator-class-localparam/` |
| Verilator 5.055 | a typedef whose width calls a package function (`w1()`), used as a class's type parameter, fails to link | a `localparam` width (`ID_BITS` in `axi4_rule`) |
| Verilator | a `$cast` between a class and an interface class can fold to 0 (brief §8) | never `$cast` to an interface class; hold listeners as interface-class handles |
| Verilator | `wire`, `release`, `join` are keywords | don't use them as method names |
| slang (pyslang 12.1.0) | two packed structs with the same members are taken for one type in an interface's type parameter, so legal vif assignments fail | weave under an empty top (`xtor_weave_top.sv`); Verilator lints the wrappers |
| sv-weave < 0.2 | two `svweave.Weave` tasks in one image both define `sv_weave_init_pkg` | one weave per image (`woven` or `woven-xtor`); weave test sources in the same run. 0.2: `init: false` on each plus `svweave.Init` |
| sv-weave | members of an unspecialized class are not modelled; specialized types print resolved | one `#(<p>_param_t P = ...)` header everywhere; class-local typedefs in signatures |
| fw-hdl | `fw_port` resolves during connect, child by child | build a wrapper before its users |
| Yosys 0.70 | truncates unsized parameter values over 32 bits; `$error` in an initial `for` | the emitter writes sized values; `tests/ip/ip_checks.py` patches `$error` |
| xezim 0.11.3 | wrong widths for a struct-valued class parameter | out of scope: Verilator only |
| Classes in RTL | sv2v and Yosys cannot read a package with classes | the two-package core (step 2-3) |
