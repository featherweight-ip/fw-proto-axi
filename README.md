# fw-proto-axi

An AMBA AXI4 manager/subordinate kit for
[fw-hdl](https://github.com/featherweight-hdl/fw-hdl). The protocol is a short
hand-written core specification; the base classes, listeners, proxies, channel
APIs, field tables, transactors and bridges are derived from it at build time
by sv-weave and the `fw_proto` weavers. It contains:
- `fw_proto_axi4_defs_pkg` (synthesizable): `axi4_param_t`, encodings, and the
  burst arithmetic (beat addresses, byte lanes, wrap boundaries, 4 KB and
  legality checks);
- `fw_proto_axi4_core_pkg`: the channel payloads, the port bundle and the
  transaction-level APIs, and the generated `fw_proto_axi4_core_pkg_woven`;
- generated signal-level transactors (manager, subordinate, monitor) with
  bridges to the class APIs;
- behaviour: manager and subordinate adapters, a memory model (strobes,
  narrow/unaligned bursts, exclusive access, error ranges), blocking shims and
  `fw_mem_if`;
- protocol rules that watch any link in simulation, and `axi4_checker`, a
  synthesizable pin checker used in simulation and in formal;
- SVUnit suites that run unchanged against a direct class link and against
  real pins, reference IPs wrapped behind the class API, lint and formal.

How it fits together: [docs/overview.md](docs/overview.md). The design is in
[docs/design-new-style.md](docs/design-new-style.md), the plan and status in
[docs/plan-new-style.md](docs/plan-new-style.md).

## Scope

AXI4 as in IHI0022H chapters A1-A9: all five channels, every burst type,
narrow and unaligned transfers, write strobes, IDs with out-of-order
completion, exclusive access (EXOKAY), all four responses, and
ID/USER/QOS/REGION. Widths are parameters, and a width of 0 means the signal
is absent. Not covered: AXI3 (write interleaving, WID, locked transfers),
AXI5 and ACE.

## Running

The first time, and after any dependency change:

```
ivpm update -a                       # fetch dependencies into packages/ (installs fw-hdl's dfm plugin too)
direnv allow .                       # .envrc puts packages/ tools on PATH
```

Then (`direnv exec .` may be dropped in a shell that direnv has loaded):

```
direnv exec . dfm run tests          # every suite x view (tlm, xtor)
direnv exec . dfm run tests --tests l2_mem   # one suite
direnv exec . dfm run smoke          # types, l1, rules_pins
direnv exec . dfm run ip             # reference IPs (tests/ip)
direnv exec . dfm run lint-rtl       # Verilator lint (checker, slice, generated xtors), zero findings
direnv exec . dfm run woven          # just the derivation; output in rundir/fw.proto.axi.woven/
direnv exec . dfm run fv-cover       # reachability under the checker's rules, and back to back
direnv exec . dfm run fv-prove       # unbounded proof of the register slice
direnv exec . dfm run fv-teeth       # planted bugs must each fail formal
direnv exec . dfm run fv             # BMC of the generated cores back to back
ci/run.sh                            # what CI runs (CI_SKIP_BOOTSTRAP=1 reuses
                                     #   packages/; CI_FV_BMC=1 adds fv)
```

`dfm` can hang rather than exit on a task-graph cycle, so wrap scripted runs
in `timeout`. The weaver goldens run with `pytest fw_proto/python/tests`.

## Layout

| Path | Contents |
|---|---|
| `src/core/` | the core specification: `fw_proto_axi4_defs_pkg` (parameters, enums, burst helpers; class-free) and `fw_proto_axi4_core_pkg` (payloads, `axi4_bundle`, `axi4_xact_if`, `axi4_burst_{req,rsp}_if`) |
| `src/weave/` | sv-weave configurations: `sv-weave.yaml` (`woven`), `sv-weave-xtor.yaml` (`woven-xtor`: plus transactors and bridges) |
| `src/behav/` | `fw_proto_axi4_behav_pkg`: adapters, memory model, blocking shims, sockets, `axi4_to_mem` |
| `src/rules/` | `fw_proto_axi4_rules_pkg`: the AXI4 rules ([docs/rules.md](docs/rules.md)) |
| `src/checker/` | `axi4_checker`: the pin checker, reference until formal is generated (plan A4) |
| `src/cores/` | `axi4_slice`: a 2-entry skid buffer |
| `src/flow.yaml` | filesets `defs`, `core`, `woven`, `woven-xtor`, `behav(-xtor)`, `rules(-xtor)`, `checker`, `slice` |
| `fw_proto/` | protocol-agnostic runtime (`src/`) and weavers (`python/fw_proto_weave`); moves to fw-hdl ([fw_proto/README.md](fw_proto/README.md)) |
| `tests/unit/` | SVUnit suites `types`, `weave`, `bundle`, `xtor`, `l1`, `l2`, `l2_mem`, `rules_teeth`, `rules_pins` |
| `tests/env/` | test parameters, per-suite cells, and the L1 link per view (`tlm/`, `xtor/`) |
| `tests/weave/`, `tests/rv_pilot/` | weave inputs for the `weave` suite; the `rv_pilot` suite on fw-hdl's ready/valid kit |
| `tests/ip/` | reference IPs (`axi_ram`, `demofull`, `axi_crossbar`) and presets ([docs/reference-ips.md](docs/reference-ips.md)) |
| `tests/lint/` | lint tops: `axi4_lint_rtl` (checker, slice), `axi4_lint_xtor` (generated transactors, behaviour, rules) |
| `tests/formal/` | checker cover, slice proof, back-to-back of the generated cores, `run_sby.sh`, `fv_b2b.sh`, `teeth.sh` |
| `tests/teeth/` | `behav_teeth.py`: mutants of `src/behav`, each must fail a suite |
| `ci/run.sh` | the CI checks |

## Trademarks and the specification

AMBA and AXI are trademarks of Arm Limited. This project is independent and
is not endorsed by Arm. It implements the AMBA AXI Protocol Specification
(IHI0022, Issue H), which is available from Arm.

The specification text is not part of this repository and must not be
committed (`IHI*` is in `.gitignore`). Source files cite sections, for
example `IHI0022H A3.4.1`.
