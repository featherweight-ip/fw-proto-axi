# fw-proto-axi

An AMBA AXI4 manager/subordinate kit for
[fw-hdl](https://github.com/featherweight-hdl/fw-hdl), modeled on
[fw-proto-chi](https://github.com/featherweight-ip/fw-proto-chi). It contains:
- `axi4_types_pkg`: parameters, encodings, beat structs and burst arithmetic
  (beat addresses, byte lanes, wrap boundaries, 4 KB and legality checks);
- `axi4_checker`: a passive pin checker, synthesizable, that runs the same
  rules in simulation and in formal;
- synthesizable manager and subordinate channel cores (register slices),
  formally checked back to back;
- a class layer over fw-hdl's socket/mirror binding: L1 (one beat per call),
  L2 (one burst per call, through manager and subordinate adapters), and a
  memory model with strobes, narrow/unaligned bursts, exclusive access and
  error ranges;
- signal-level transactors (manager, subordinate, passive monitor) with
  random VALID/READY backpressure;
- SVUnit suites that run unchanged against a direct TLM bind and against
  real pins.

How it fits together: [docs/overview.md](docs/overview.md).

## Scope

AXI4 as in IHI0022H chapters A1-A9: all five channels, every burst type,
narrow and unaligned transfers, write strobes, IDs with out-of-order
completion, exclusive access (EXOKAY), all four responses, and
ID/USER/QOS/REGION. ID and USER widths are parameters, and 0 means the
signal is absent. Not covered: AXI3 (write interleaving, WID, locked
transfers), AXI5 and ACE. AXI4-Lite is a possible later addition.

## Running

The first time, and after any dependency change:

```
ivpm update -a                       # fetch dependencies into packages/
uv pip install --python packages/python/bin/python --no-deps \
    -e packages/fw-hdl/python        # fw-hdl's dfm plugin (ivpm does not install it)
direnv allow .                       # .envrc puts packages/ tools on PATH
```

Then (`direnv exec .` may be dropped in a shell that direnv has loaded):

```
direnv exec . dfm run tests          # every suite x view (tlm, xtor)
direnv exec . dfm run tests --tests l2_mem   # one suite
direnv exec . dfm run smoke          # the per-commit suite set
direnv exec . dfm run lint-rtl       # Verilator lint, held to zero findings
direnv exec . dfm run fv-cover       # reachability under the checker's rules
direnv exec . dfm run fv-prove       # unbounded proof of the register slice
direnv exec . dfm run fv-teeth       # planted bugs must each fail formal
direnv exec . dfm run fv             # BMC of the cores back to back (~6.5 min)
ci/run.sh                            # what CI runs (CI_SKIP_BOOTSTRAP=1 reuses
                                     #   packages/; CI_FV_BMC=1 adds fv)
```

`dfm` can hang rather than exit on a task-graph cycle, so wrap scripted runs
in `timeout`.

## Layout

| Path | Contents |
|---|---|
| `src/types/` | `axi4_types_pkg`: `axi4_param_t`, BURST/SIZE/RESP enums, beat structs, burst helpers, stream widths |
| `src/checker/` | `axi4_checker`: the pin checker (rules and spec references in its header and in [docs/overview.md](docs/overview.md)) |
| `src/cores/` | `axi4_slice` (2-entry skid buffer), `axi4_mgr_core`, `axi4_sub_core` |
| `src/xtor/` | `axi4_xtor_if`, `axi4_mgr_xtor`, `axi4_sub_xtor`, `axi4_mon_xtor(_if)` |
| `src/class/` | `fw_proto_axi4_pkg`: L1 interfaces, socket/mirror types, `axi4_cfg`, endpoints, wire packing, `axi4_xact`, adapters, `axi4_mem_model`, `axi4_to_mem`, monitor classes. `fw_proto_axi4_xtor_pkg`: bridges from classes to the transactors |
| `tests/unit/` | SVUnit suites `types`, `chk_teeth`, `l1_basic`, `l2_basic`, `l2_mem` |
| `tests/env/` | `axi4_test_pkg` (envs, random stimulus, test target) and one harness per level and view (`tlm/`, `xtor/`) |
| `tests/formal/` | checker cover harness, back-to-back harness, slice proof, `run_sby.sh`, `teeth.sh` |
| `tests/lint/` | lint tops (everything synthesizable, cores and transactors back to back) |
| `ci/run.sh` | the CI checks |

## Trademarks and the specification

AMBA and AXI are trademarks of Arm Limited. This project is independent and
is not endorsed by Arm. It implements the AMBA AXI Protocol Specification
(IHI0022, Issue H), which is available from Arm.

The specification text is not part of this repository and must not be
committed (`IHI*` is in `.gitignore`). Source files cite sections, for
example `IHI0022H A3.4.1`.
