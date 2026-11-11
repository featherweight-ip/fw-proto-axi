# fw_proto

Protocol-agnostic support for protocol packages written in the new style
(`docs/design-new-style.md`): a protocol is a short hand-written core, and
everything else is derived from it by sv-weave at build time. Nothing here
names a protocol. It is meant to move to fw-hdl (plan D2).

## Layout

| Path | What |
|---|---|
| `src/fw_proto_pkg.sv` | SV runtime the derived code builds on: `fw_dir_e`, `fw_field_t`, `fw_sp_base` (struct port: field table, link, bind), `fw_rv_ch` (ready/valid channel family), `fw_inbox` |
| `flow.yaml` | exports `fw-proto-sv` (the runtime) |
| `python/fw_proto_weave/` | the sv-weave binding and the `fw-proto` weaver |
| `python/tests/` | goldens and a Verilator `-Wall` lint of the woven output |

## What the core declares

| Attribute | On | Meaning |
|---|---|---|
| `(* fw_api *)` | interface class | an API: derive its listener, bases, proxy, fan-out, imp |
| `(* fw_default = "empty" \| "error" *)` | API or method | what an unimplemented method does in `<api>_base` (APIs default to `error`, listeners to `empty`) |
| `(* fw_proto_bundle = "<proto>", fw_roles = "<a>,<b>" *)` | class | the port bundle; role `a` drives the fwd channels |
| `(* fw_fwd *)`, `(* fw_rev *)` | bundle property `<family> #(<payload>) <ch>` | a channel and its direction |
| `(* fw_opt = "<P member>" *)` | payload struct member | the field has pins only when `P.<member> != 0` |
| `(* fw_clock = "<pin>", fw_reset_n = "<pin>" *)` (or `fw_reset`, active high) | bundle class | clock and reset pins of the generated transactors (default `clock`, `reset`) |
| `(* fw_defs_pkg = "<pkg>" *)` | bundle class | the bundle's synthesizable (class-free) package, holding its parameter type; needed for the RTL layer and by `xtor` |

## What is derived (into `<pkg>_woven`)

For every API, the `<api>_` classes:
- `listener` (`<m>_pre`/`<m>_post`), `listener_base` and `listener_fanout`;
- `base`, `proxy` (target + listeners) and `imp #(..., type IMP)`.

Each derived class has the API's parameter header, as written.

For every bundle:
- the channel APIs `<proto>_req_if`/`<proto>_rsp_if`, with all of the above;
- `<api>_inbox` per channel API;
- `<proto>_sp` (the field table) and `<proto>_<role>_sp` (typed `link`/`bind_inner`);
- `<proto>_payloads` (`<ch>_sprint`, `<ch>_compare`).

For every bundle with `fw_defs_pkg`, into `<fw_defs_pkg>_woven` (class-free, synthesizable):
- `<proto>_<payload>_bits(P)`, each payload struct's width.

With the weaver option `xtor: true`, for every bundle with two roles and `fw_rv_ch`
channels, the pin-level transactors (`python/fw_proto_weave/xtors.py`). They need
fw-hdl's ready/valid kit (`fw-hdl.hdl.rv-src`) in the image:
- files beside the woven package, compiled after it, per role and one for the monitor
  (`mon`): `<proto>_<role>_xtor_core.sv`, the synthesizable core (one fw-hdl rv core per
  channel, the flat payloads spliced onto the pins, named as in the field table; imports
  only the `fw_defs_pkg` packages); `<proto>_<role>_xtor.sv`, the core plus one fw-hdl rv
  interface per channel; and `<proto>_<role>_xtor_if.sv`, its class side (`u_if`);
- in the woven package: `<proto>_<role>_xtor_chans` (the channels' vifs) and the bridges
  `<proto>_<role>_xtor_bridge` (implements the role's outbound channel API; `run()`
  passes inbound beats to the other API's handle) and `<proto>_mon_xtor_bridge`
  (`<ch>_pre` on the first valid cycle, `<ch>_post` on the handshake, on `req`/`rsp`
  listener fan-outs).

`src/weave/sv-weave-xtor.yaml` (task `woven-xtor`) is the AXI4 example. Weave under an
empty top (`sources.top`), see the note there.

## Using it

Weave with `svweave.Weave` and a config like `src/weave/sv-weave.yaml`:

```yaml
sv-weave:
  binding: fw_proto_weave:FwProtoBinding      # no root classes: package-level output only
  plugin-path: [<path to>/fw_proto/python]
  packages:
    include: [<your core package>]
  weavers:
  - name: fw_proto_weave:FwProtoWeaver
    options:
      include: []      # interface classes to treat as APIs without the attribute
      derive: [listener, base, proxy, imp, bundle]   # default: all
      xtor: false      # also the pin-level transactors (needs fw-hdl's rv kit)
```

The woven package imports the core and, for bundle derivatives,
`fw_proto_pkg`. `tests/weave/rv/sv-weave.yaml` weaves fw-hdl's ready/valid
APIs, which have no attributes, through `include`.

## Notes

- Derived code reports errors with `$error`, and uses no fw-hdl.
- Interface-class typedefs are not inherited by implementing classes. Derived classes re-declare them: `typedef <api> #(P)::<t> <t>;`.
- A change to this Python is not seen by the weave's up-to-date check. After editing it, delete the `*woven*` run directories before `dfm run`.
- Tests: `pytest fw_proto/python/tests`; refresh the goldens with `FW_PROTO_REGEN=1` and review the diff.
