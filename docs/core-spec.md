# AXI4 core specification: a reading guide

The core is the only hand-written protocol description in the package. Everything else
(listeners, proxies, the field table, transactors, abstractor glue, …) is derived from it
by the fw_proto weavers (`fw_proto/python/fw_proto_weave`). This note walks through each
declaration in `src/core/`, says what it means, and names what the weavers derive from it.
The derived classes themselves are described in [derived-classes.md](derived-classes.md).
The reasons for the split are in [design-new-style.md](design-new-style.md) §1-§3.

## Files

| File | Package | Content |
|---|---|---|
| `fw_proto_axi4_defs_pkg.sv` | `fw_proto_axi4_defs_pkg` | Parameters, encodings, burst arithmetic. No classes |
| `fw_proto_axi4_core_pkg.sv` | `fw_proto_axi4_core_pkg` | The class part. Includes the `.svh` files below, one class each |
| `axi4_types.svh` | (core) | `axi4_types #(P)`: the channel payload structs |
| `axi4_bundle.svh` | (core) | `axi4_bundle #(P)`: the port bundle |
| `axi4_burst_req_if.svh` | (core) | `axi4_burst_req_if #(P)`: burst API, requests |
| `axi4_burst_rsp_if.svh` | (core) | `axi4_burst_rsp_if #(P)`: burst API, responses |
| `axi4_xact_if.svh` | (core) | `axi4_xact_if #(P)`: the blocking convenience API |

Two packages because RTL flows (sv2v, Yosys) cannot read a package that holds classes.
The defs package is synthesizable; the generated transactor cores import it and nothing
else from the core.

Each spec package has a generated counterpart, written by `dfm run woven` (or
`woven-xtor`) to `rundir/fw.proto.axi.woven[-xtor]/woven/`:

| Spec (hand-written) | Woven (generated) |
|---|---|
| `fw_proto_axi4_defs_pkg` | `fw_proto_axi4_defs_pkg_woven`: payload widths `axi4_<payload>_bits(P)` |
| `fw_proto_axi4_core_pkg` | `fw_proto_axi4_core_pkg_woven`: all the classes in [derived-classes.md](derived-classes.md) |

A user of the classes imports four packages:

```systemverilog
import fw_proto_axi4_defs_pkg::*;
import fw_proto_axi4_core_pkg::*;
import fw_proto_axi4_core_pkg_woven::*;
// plus fw_proto_pkg::* (the runtime) for rules and struct ports
```

## The defs package (`fw_proto_axi4_defs_pkg`)

### The parameter struct `axi4_param_t`

All sizing goes through one struct parameter, `P`. Every class, interface and module in
the package has the header `#(axi4_param_t P = AXI4_PARAM_DEFAULT)`.

| Member | Meaning | 0 means |
|---|---|---|
| `ADDR_W` | AxADDR width | (not allowed) |
| `DATA_W` | xDATA width: 8, 16, … 1024 | (not allowed) |
| `ID_W` | AxID/xID width | no ID pins |
| `AWUSER_W`, `WUSER_W`, `BUSER_W`, `ARUSER_W`, `RUSER_W` | USER widths, per channel | no USER pins on that channel |
| `HAS_QOS` | AxQOS present (0/1) | no QOS pins |
| `HAS_REGION` | AxREGION present (0/1) | no REGION pins |

`AXI4_PARAM_DEFAULT` is 32-bit address, 64-bit data, 4-bit ID, no USER, QOS and REGION
present.

Why one struct: it carries every optional width in one parameter, so classes, interfaces
and modules pass `P` and nothing else. The weavers rely on it: `fw_opt` (below) names a
member of the bundle's one struct parameter, and the transactors need exactly one.

`w1(w)` gives the width a possibly absent field is held at (`w`, or 1 when `w` is 0).
`max2(a, b)` is used for `attr_t.user`.

### Encodings

`axi4_burst_e` (AxBURST), `axi4_size_e` (AxSIZE), `axi4_resp_e` (xRESP), with the AMBA
encodings (IHI0022 Issue H, cited per item). The payload structs use these enums directly,
so the pins carry `$bits` of each.

### Burst arithmetic

Pure functions on 64-bit addresses (`axi4_addr64_t`), independent of `P`, so RTL, rules
and models share one copy:

| Function | Gives |
|---|---|
| `axi4_size_bytes(size)`, `axi4_burst_beats(len)` | bytes per beat, beats per burst |
| `axi4_aligned_addr`, `axi4_wrap_boundary`, `axi4_beat_addr` | addresses (A3.4.1, A3.4.2) |
| `axi4_beat_lower_lane`, `axi4_beat_upper_lane` | active byte lanes of beat `n` (A3.4.3) |
| `axi4_crosses_4k`, `axi4_burst_legal` | burst legality (A3.4.1) |
| `axi4_excl_legal` | exclusive-access legality (A7.2.4) |

The rules (`src/rules`), the memory model, `axi4_checker` and the tests use these. The
weavers derive nothing from them.

### Packed channel widths

`axi4_ax_bits(p, rd)`, `axi4_wd_bits(p)`, `axi4_b_bits(p)`, `axi4_r_bits(p)`: the width of
one beat of each channel. They are hand-written and duplicate the generated
`axi4_<payload>_bits(P)` in `fw_proto_axi4_defs_pkg_woven` (which `tests/formal/axi4_fv.sv`
and the transactor cores use). `tests/env/xtor/axi4_l1_link.sv` and `tests/lint` still use
the hand-written ones.

## The core package (`fw_proto_axi4_core_pkg`)

It imports `fw_proto_pkg` (the runtime: `fw_rv_ch`, `fw_sp_base`, …) and the defs package.
The header comment lists the attributes the weavers read; this section repeats them by
declaration.

### Channel payloads: `axi4_types #(P)`

One packed struct per channel payload, inside a parameterized class so that widths can
depend on `P`:

| Typedef | Channel(s) | Members (MSB first) |
|---|---|---|
| `aw_t` | AW | `id addr len size burst lock cache prot qos region user` |
| `ar_t` | AR | as `aw_t`, with `ARUSER_W` for `user` |
| `w_t` | W | `data strb last user` |
| `b_t` | B | `id resp user` |
| `r_t` | R | `id data resp last user` |

Rules for a payload struct:
- **Member names are the AMBA names without the channel prefix.** The bundle's channel
  name supplies the prefix: member `addr` of channel `aw` is pin `awaddr`.
- **Member order is pin and packing order.** The struct is packed MSB first in
  declaration order; the transactor cores splice pins in that order.
- **An optional field is marked `(* fw_opt = "<P member>" *)`.** The field exists on the
  pins only when `P.<member> != 0`. In the struct it is always there, `w1(...)` bits wide
  (one bit when absent), so the struct type never changes shape.

What `fw_opt` does in each derivative:

| Derivative | Absent field (`P.<member> == 0`) |
|---|---|
| Field table (`axi4_sp::build_fields`) | not added: no pin |
| `axi4_payloads::<ch>_sprint`, `<ch>_compare` | skipped |
| `axi4_payloads::<ch>_mask` | zeroed |
| Transactor cores and wrappers | pin kept, `w1` wide, driven or read as 0 |

`attr_t`, `addr_t`, `data_t` and `strb_t` are helper types for `axi4_xact_if`. They are
not channel payloads and nothing is derived from them.

### The port bundle: `axi4_bundle #(P)`

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

The bundle is never instantiated. It is a declaration the weavers read: which channels
the protocol has, which way each goes, and what each carries.

Class attributes:

| Attribute | Meaning | Default |
|---|---|---|
| `fw_proto_bundle = "<proto>"` | marks the bundle; `<proto>` prefixes every derived name | class name less `_bundle` |
| `fw_roles = "<a>,<b>"` | the two roles; `<a>` sends the `fw_fwd` channels, `<b>` the `fw_rev` ones. `mon` is reserved | `init,targ` |
| `fw_clock = "<pin>"` | clock pin of the transactor modules | `clock` |
| `fw_reset_n = "<pin>"` | active-low reset pin; wins over `fw_reset` | none |
| `fw_reset = "<pin>"` | active-high reset pin | `reset` |
| `fw_defs_pkg = "<pkg>"` | the class-free package of the parameters; gets `<pkg>_woven`; needed for transactors | none |

Channel members:
- **Type `<family> #(<payload>)`.** The family is the handshake. Only `fw_rv_ch`
  (ready/valid, `fw_proto/src/fw_rv_ch.svh`) exists; it adds the pins `<ch>valid` (with
  the payload) and `<ch>ready` (the other way) to the field table. The payload must be a
  packed struct the weave has read (here `axi4_types #(P)::<x>_t`, through the local
  typedef `t`).
- **Exactly one of `(* fw_fwd *)` or `(* fw_rev *)`.** Forward is from the first role to
  the second (manager to subordinate).
- **The member name is the channel name.** It is the pin prefix and the method name in the
  channel API.
- **Member order is channel order** in every derivative (field table, method order,
  transactor ports).

Cross-channel facts (`len+1` W beats per AW, B after the last W, ID ordering) are not in
the bundle. They are rules ([rules.md](rules.md)).

### Hand-written APIs: `(* fw_api *)` interface classes

```systemverilog
(* fw_api *)
interface class axi4_burst_req_if #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    typedef axi4_types #(P)::aw_t aw_t;
    typedef axi4_types #(P)::w_t  w_t;
    typedef axi4_types #(P)::ar_t ar_t;
    pure virtual task write_burst(input aw_t aw, input w_t w[$]);
    pure virtual task read_burst(input ar_t ar);
endclass
```

| API | Called by | Methods |
|---|---|---|
| `axi4_burst_req_if` | manager | `write_burst(aw, w[$])`, `read_burst(ar)`: return when the beats are accepted |
| `axi4_burst_rsp_if` | subordinate | `write_resp(b)`, `read_resp(r)`: one per B; one per R beat |
| `axi4_xact_if` | test writer | `write(addr, data[$], strb[$], attr, resp)`, `read(addr, beats, attr, data[$], resp)`: blocking |

The burst pair is the protocol's own transaction API, in the payload types, so no channel
field is lost (design §3.4, D11). `axi4_xact_if` is a convenience on top of it
(`src/behav/axi4_xact_on_burst.svh`).

Conventions for an API class (the weavers depend on them):
- **`(* fw_api *)` on the class** marks it. An interface class without it can be named in
  the weaver's `include` option instead (the rv pilot does this for fw-hdl's rv APIs).
- **Local typedefs for every type in a signature.** Interface-class typedefs are not
  inherited, so each derived class re-declares them as `typedef <api> #(P)::<t> <t>;`.
- **A task when the call may block, a function otherwise.** Only `input` and `output`
  arguments; packed types and queues of packed types. No `ref`, events or class handles.
- **`(* fw_default = "empty" | "error" *)`** on the class or a method overrides the default
  body in `<api>_base` (not used in AXI4; `tests/weave/synth/weave_synth_pkg.sv` has one).
- **`(* fw_listener *)`** marks a hand-written listener interface: its `_base` gets empty
  bodies. The weavers put it on every generated `<api>_listener`.

The lint pragmas around the API includes (`UNUSEDSIGNAL`, `UNDRIVEN`) are there because
prototype arguments are never read or written.

## What is derived from each declaration

| Declaration | Derived (names for AXI4) | Weave |
|---|---|---|
| `axi4_param_t`, encodings, arithmetic | nothing | |
| `axi4_types` payload struct | `axi4_<x>_t_bits(P)` (defs woven); a field-table section, `axi4_payloads::<ch>_sprint/_compare/_mask`, transactor pin splices (through the bundle) | `woven` |
| `axi4_bundle` | channel APIs `axi4_req_if`, `axi4_rsp_if`, each with the per-API set below; `axi4_req_if_inbox`, `axi4_rsp_if_inbox`; `axi4_sp`, `axi4_mgr_sp`, `axi4_sub_sp`; `axi4_payloads` | `woven` |
| `axi4_bundle` with `xtor: true` | `axi4_{mgr,sub,mon}_xtor_core`, `_xtor`, `_xtor_if` (files); `axi4_{mgr,sub,mon}_xtor_chans`, `_xtor_bridge`; `axi4_mgr_socket`, `axi4_sub_socket`; `axi4_observers`; `axi4_{mgr,sub}_abs`, `_abs_h`; `connect()` on the role ports | `woven-xtor` |
| each `(* fw_api *)` class (and each channel API) | `<api>_listener`, `<api>_listener_base`, `<api>_listener_fanout`, `<api>_base`, `<api>_proxy`, `<api>_imp` | `woven` |

So `axi4_burst_req_if` yields `axi4_burst_req_if_listener`, `…_listener_base`,
`…_listener_fanout`, `axi4_burst_req_if_base`, `…_proxy`, `…_imp`; likewise
`axi4_burst_rsp_if`, `axi4_xact_if`, `axi4_req_if` and `axi4_rsp_if`.

Not derived: sockets for the hand-written APIs. The burst pair's sockets
(`axi4_burst_mgr_socket`, `axi4_burst_sub_socket`) are written by hand in `src/behav/`.

## Changing the core

- **A new field in a payload** (e.g. a new optional signal): add the member, with
  `fw_opt` if it may be absent, and if needed a member in `axi4_param_t`. Every derivative
  (field table, sprint/compare, transactors, burst API) picks it up with no other edit.
  The hand-written `axi4_*_bits` in the defs package do not (see above).
- **A new channel**: add a bundle member. It becomes a method of `axi4_req_if` or
  `axi4_rsp_if`.
- **A new API**: a new `(* fw_api *)` interface class, `include`d by the core package.

After editing the weavers themselves (not the core), delete
`rundir/fw.proto.axi.*woven*` before `dfm run`: the weave's up-to-date check does not
cover the weaver's Python source (plan §1).
