# fw-proto-axi, new style: implementation, test and documentation plan

This is the working plan for building the package described in
[design-new-style.md](design-new-style.md) (the "design"). It is also the tracking file:
update the status table (§1) and the task checkboxes as work lands. A fresh session should
be able to resume from this file alone.

## 1. Status

| Phase | State | Note |
|---|---|---|
| P0 Foundations (deps, sv-weave extensions, flow) | done | S5 (weaver file output) done with P4.2 |
| P1 Generic weavers (bases, listeners, proxies, imps) | done | rv pilot passes (`rv_pilot`); per-field imp (step 2) waits for P6 |
| P2 AXI4 core specification | done | `types_ns` passes |
| P3 Bundle derivatives + struct-port runtime | mostly done | runtime, field tables, role ports, inboxes, sprint/compare done; pin-map presets wait for fw-hdl `pin`/`prefix` (P6) |
| P4 Transactors and back-to-back | done | `l1_ns` (2 views × 3 P), stalls by path, `lint-xtor-ns`, `fv` on the generated cores (`axi4_fv_ns`); core spec split into a synthesizable and a class package (D-fv) |
| P5 Behaviour: adapters, memory model, transaction API | done | streaming `axi4_burst_if` + convenience shim (D10); `l2_ns` 24/24, `l2_mem_ns` 27/27 in both views; `dfm run tests` 18 of 19 (the old `l2_basic` xtor failure) |
| P6 Abstractors, extern wrapping, reference IPs | in progress | runtime and glue done; `axi_ram`, `demofull`, `axi_crossbar` pass (`dfm run ip`); preset tests and docs open. See [p6-abstractors.md](p6-abstractors.md) |
| P7 Rules in simulation | not started | |
| P8 Retire the old package | not started | |
| Later: formal generation (A4), monitor transactions (A5), systems (A6) | not planned in detail | §9 |

**Last update:** 2026-11-11 (P5). The derivation runs as dv-flow tasks: `dfm run woven`
(`src/flow.yaml`, `svweave.Weave` + `src/weave/sv-weave.yaml`) writes
`fw_proto_axi4_core_pkg_woven.sv` to `rundir/fw.proto.axi.woven/woven/`. From the core it
derives:
- for `axi4_xact_if` and the bundle's channel APIs `axi4_req_if`/`axi4_rsp_if`:
  `_listener`, `_listener_base`, `_listener_fanout`, `_base`, `_proxy`, `_imp`;
- from `axi4_bundle`: `axi4_req_if_inbox`/`axi4_rsp_if_inbox` (scripted endpoints, with
  `clear`/`idle`), `axi4_sp` (the field table), `axi4_mgr_sp`/`axi4_sub_sp` (typed
  `link`/`bind_inner`) and `axi4_payloads` (`<ch>_sprint`/`<ch>_compare`).

The runtime they build on is `fw_proto/src/fw_proto_pkg.sv`: `fw_sp_base`, `fw_field_t`,
`fw_rv_ch` (with `add_ctl`), `fw_inbox`.

Passing (`dfm run tests`: 14 of 15, the failure below; `dfm run lint-rtl`: both lint tasks at zero findings; `formal.bmc-ns`, `cover-b2b-ns`, `teeth-ns` pass):
- `types_ns` 7/7: burst helpers, lanes, exclusive access, 64-bit addresses;
- `weave_ns` 5/5: widths, proxy/listener order, remove, fan-out, imp, channel APIs over
  `P_MIN`/`P_DEF`/`P_WIDE`; synthetic `#(type T, int N)` API;
- `bundle_ns` 5/5: field table vs. the AMBA pin list by hand for all three P;
  totals vs. `axi4_checker`'s port widths (`P_WIDE`); role-port link/bind/directions;
  sprint/compare with absent fields; tlm link through the channel proxies, an inbox
  stall holding AW only, and a listener's pre/post order;
- `rv_pilot`: fw-hdl's `tests/rv_proto` run as is and with its sink's
  `FW_RV_TARGET_IMP` replaced by the generated `fw_rv_target_if_imp` (behind an
  `fw_export`); identical sink transcripts (8 beats, same times);
- `xtor_ns` 3/3: the generated `axi4_{mgr,sub,mon}_xtor` and bridges back to back, one
  link per P, `axi4_checker` (COUNT_ONLY) at zero; every beat checked at the far end and
  at the monitor (pre and post); fails as it should with a corrupted `wlast` splice;
- `l1_ns` 15/15 in each view (`tlm`, `xtor`): channels one at a time, all five
  concurrently, AW stalled while W/AR/R flow, every response code and burst type (EXOKAY
  on exclusive accesses), and stalls set by path, each for `P_MIN`/`P_DEF`/`P_WIDE`.
  Protocol-legal traffic; in `xtor` the link is generated manager → old `axi4_sub_core`
  → `axi4_mgr_core` → generated subordinate, with `axi4_checker` (COUNT_ONLY) at zero on
  both pin segments. Fails as it should with WLAST forced to 1 (checker counts) and
  with the path-set gaps zeroed (timing check);
- `lint-xtor-ns` (part of `lint-rtl`): Verilator `-Wall --timing` of the generated
  wrappers, bridges and woven package for the three P, zero findings (fw-hdl's own files
  and sv-weave's init-file name waived by path, `lint-waivers-xtor-ns.yaml`);
- `pytest fw_proto/python/tests`: 17/17 (goldens incl. the nine xtor files and the defs woven package; sv2v of the class-free layer; derived-class
  list, Verilator `-Wall` of the woven package and of each wrapper + bridge for all three P);
- `pytest packages/sv-weave/tests`: 227 passed (needs Verilator 5.055 first on `PATH`; §3.1).

Old suites: all pass except `l2_basic` xtor view, `concurrent_ids`, which trips the
checker's MAX_OUT capacity assertion (`axi4_checker.sv:432`). It fails the same way with
this work's tracked changes stashed, so it predates this work.

Stale-output gap: a weaver's Python source is not part of the weave's up-to-date check
(sv-weave hashes only the plugin's version string). After editing
`fw_proto/python/fw_proto_weave`, delete `rundir/fw.proto.axi.*woven*` (or bump the
weaver's `version`) before `dfm run`.

**P4.1 done (2026-11-11):** fw-hdl's rv transactors have run-time `depth` and `max_gap`,
and the monitor reports first-valid events (`get_ev`). fw-hdl's tests that touch the rv
kit: 135 passed (83 skipped: they need the XLS tools), including the new
`test_runtime_knobs`. `ivpm.yaml` now declares yosys (sby) directly.

**P4.2 done (2026-11-11):** `dfm run woven-xtor` (`src/weave/sv-weave-xtor.yaml`, weaver
option `xtor: true`, inputs add `fw-hdl.hdl.sv-src`/`rv-src`) writes, beside the woven
package, `axi4_{mgr,sub,mon}_xtor.sv` and `axi4_{mgr,sub,mon}_xtor_if.sv`, and adds to the
woven package `axi4_<role>_xtor_chans` (the five rv vifs) and the bridges
`axi4_mgr_xtor_bridge` (implements `axi4_req_if`, B/R to `m_rsp`), `axi4_sub_xtor_bridge`
(implements `axi4_rsp_if`, AW/W/AR to `m_req`) and `axi4_mon_xtor_bridge` (`req`/`rsp`
listener fan-outs, `<ch>_pre` on first valid, `<ch>_post` on handshake). An image uses
`woven` or `woven-xtor`, not both. Generator: `fw_proto/python/fw_proto_weave/xtors.py`.

**P4.3 so far (2026-11-11):** suite `l1_ns` (`tests/unit/l1_ns_unit_test.sv`, cell
`tests/env/axi4_l1_ns_cell.sv`, one `axi4_l1_ns_link` per view in `tests/env/{tlm,xtor}/`);
the generated `axi4_<role>_xtor_chans` gained `set_knob("<ch>.<knob>", v)` (`depth`, and
`max_gap` except on the monitor), reached by path as `"<role>.<ch>.<knob>"`; task
`lint-xtor-ns` (`tests/lint/axi4_lint_xtor_ns*.sv`); the weaver wraps classes whose
methods leave their arguments unread (API and listener interface classes, `_base`) in a
scoped `verilator lint_off UNUSEDSIGNAL`.

**D-fv decided (2026-11-11, option 1) and done:** the core spec is two packages, each
with a generated counterpart (design §3): `fw_proto_axi4_defs_pkg` (class-free: parameters,
encodings, burst arithmetic; task `defs`) with `fw_proto_axi4_defs_pkg_woven` (generated:
`axi4_<payload>_bits(P)`), and `fw_proto_axi4_core_pkg` (classes) with
`fw_proto_axi4_core_pkg_woven`. The bundle names its class-free package
(`fw_defs_pkg`). The weaver generates `axi4_<role>_xtor_core` (synthesizable: fw-hdl rv
cores plus the splice, flat payloads in struct packing) and `axi4_<role>_xtor` is now that
core plus the rv interfaces. `axi4_fv_ns` (`tests/formal/axi4_fv_ns.sv`, run by
`tests/formal/fv_ns.sh`) is `axi4_fv` on the generated cores: BMC depth 16 passes
(~2 min), 6/6 covers reached, 4/4 planted bugs caught. Roots `fv`, `fv-cover`,
`fv-teeth` run the old and the new harness. The BMC found a real fw-hdl bug: the rv
cores' valid outputs were undefined in the first reset cycle (fixed, dependency log).

**fw-hdl full suite after the reset fix (2026-11-11):** `pytest tests/python` in
`packages/fw-hdl` (Verilator 5.055): 245 passed, 43 failed, 3 skipped (log
`rundir/logs/fw-hdl-pytest.log`). None of the failures come from this work. 42 (regmap,
regblock, mmio*, structural_top) fail the same way on a clean worktree of fw-hdl HEAD
`6f45fe0`. The tests' register sources call `new(...)` without the now-required
`parent`, and `dma_channel_regs` has no registers. That's an upstream inconsistency in
fw-hdl. The 43rd, `test_knobs::test_dfm_resolve`, expects fw-hdl's own
`packages/python/bin/dfm`, which exists only in a standalone checkout. It passes with a
temporary `packages -> ..` link. All rv tests pass.

**P5 done (2026-11-11), with decision D10 (below).** `src/behav/fw_proto_axi4_behav_pkg.sv`
(tasks `behav` over `woven`, `behav-xtor` over `woven-xtor`; needs fw-hdl for `fw_mem_if`):
- `axi4_mgr_adapter #(P)` extends `axi4_rsp_if_base`, implements `axi4_burst_if`; sends on
  `req` (`axi4_req_if`). Matches responses per ID; a write's W beats follow its AW;
- `axi4_sub_adapter #(P)` extends `axi4_req_if_base`; calls `tgt` (`axi4_burst_if`),
  answers on `rsp`, with BID/RID from the request and RLAST on the last beat. Per-ID
  turns; `max_delay` in time units through an overridable `delay(n)`;
- `axi4_mem_model #(P)` extends `axi4_burst_if_base` (per-beat responses);
- the shims `axi4_xact_on_burst` (the convenience API over the streaming one) and
  `axi4_burst_on_xact` (a plain-API target behind the streaming API, lossy). These and
  `axi4_attr` (attr against AW/AR, lanes, worst response) are the only code that converts
  between the two APIs;
- `axi4_to_mem #(P, ADDR, DATA, STRB)` implements fw-hdl's `fw_mem_if` over `axi4_xact_if`.

No macros, no `fw_component`. Each adapter zeroes the fields the parameter set leaves off the
pins with the generated `axi4_payloads::<ch>_mask` (new in `endpoints.py`, beside sprint and
compare), so both views deliver the same beats with no hand-written field list. Each link
view gained `attach(mgr_end, sub_end)` to put the adapters where the inboxes were.

**D10 (decided 2026-11-11, `p5-open-issues.md`):** the core's transaction API is the
streaming `axi4_burst_if` (`write_burst(aw, w[$], b)`, `read_burst(ar, r[$])`, in the
channel payload types: nothing lost, and a new payload field needs no other edit).
`axi4_xact_if` is a convenience layer on top, implemented by a shim; its `read` takes a
beat count (`beats`). Design §3.4 updated.

Suites (each view × `P_MIN`/`P_DEF`/`P_WIDE`; `tests/env/axi4_l2_ns_env.sv`, the test
record `tests/env/axi4_l2_ns_pkg.sv`):
- `l2_ns` 24/24 in `tlm` and `xtor`:
  - single write/read, random bursts, backpressure set by path (timing check where there
    are pins), concurrent IDs with reordering, error responses (and the R beats on the
    link), every link beat seen by the link observer (now in both views);
  - a listener on the convenience proxy (pre/post order, arguments, remove; each call
    passes the streaming API once);
  - `burst_fidelity`: streaming bursts with every field random (USER on every beat) to a
    streaming target with random per-beat RRESP/USER and garbage RID/RLAST. Both
    directions arrive exactly, absent fields zeroed;
- `l2_mem_ns` 27/27 in `tlm` and `xtor`: `fw_mem_if` 32/128-bit, strobes and fill, narrow
  unaligned INCR, WRAP, FIXED, random INCR readback, exclusive access, error ranges
  (per-beat RRESP OKAY, OKAY, DECERR, DECERR on the streaming API, as in the old suite),
  concurrent `fw_mem_if`. Expectations are per byte address and lane, so they hold at any
  bus width.
- Teeth (bugs planted in the package, `tlm`):
  - no per-ID turns → `concurrent_ids`;
  - strobes ignored → `strobes_and_fill`, `random_incr_readback`;
  - reservations not cleared → `exclusive`;
  - WRAP addressed as INCR → `wrap_burst`;
  - RLAST left as the target gave it → `burst_fidelity`;
  - the shim's response not the worst, or the memory's one response per burst →
    `error_ranges`;
  - the plain-target shim dropping strobes → `random_bursts`, `backpressure`,
    `concurrent_ids`;
  - BID not taken from the request, or absent fields not zeroed → responses lost, caught
    by the env's watchdog (a fatal error when calls stay open with no progress for 100 µs).

  The ID not zeroed at `ID_W` = 0 passes in `tlm` (nothing drops it) and is caught by the
  watchdog in `xtor`.

Old against new: the new suites draw their traffic differently (other generators, all
three P, protocol-legal attributes), so a same-seed comparison is not meaningful. Per test,
every old `l2_basic` and `l2_mem` test has a passing counterpart, per-beat RRESP included.
The old failure (`l2_basic` xtor `concurrent_ids`, checker MAX_OUT 16) passes in its port
(MAX_OUT 32).

Regression: `dfm run tests` 18 of 19 (`l2_ns`, `l2_mem_ns` both views pass; the one
failure is the old `l2_basic` xtor, above); `dfm run lint-rtl` passes; `pytest
fw_proto/python/tests` 17/17 with the goldens refreshed (`axi4_burst_if`'s derived
classes, `_mask`).

Verilator 5.055 faults (or runs out of memory) on `axi4_to_mem` when its bytes-per-beat
is a localparam and DATA is narrower than the bus; it is a run-time member instead.

Proposed P5 commit set (yours to make):
- `src/behav/`; `src/core/fw_proto_axi4_core_pkg.sv` (`axi4_burst_if`, `beats`);
- `fw_proto/python/fw_proto_weave/endpoints.py` (`_mask`) and the goldens;
- `src/flow.yaml` (`behav`, `behav-xtor`), `flow.yaml` (`tests` root), `tests/flow.yaml`
  (two suites);
- `tests/env/axi4_l2_ns_{pkg,env,cell}.sv`, `tests/env/axi4_l2_mem_ns_cell.sv`,
  `tests/unit/l2_{,mem_}ns_unit_test.sv`;
- `attach()` in `tests/env/{tlm,xtor}/axi4_l1_ns_link.sv` and its line in
  `tests/env/axi4_l1_ns_cell.sv`;
- `docs/design-new-style.md` §3.4, `docs/p5-open-issues.md`, this file.

P5 follow-ups (`p5-open-issues.md` §3, all decided as proposed, 2026-11-11):
- `lint-xtor-ns` now also lints `fw_proto_axi4_behav_pkg`: every class is specialized for
  the three P in `tests/lint/axi4_lint_xtor_ns_b2b.sv` (task needs `behav-xtor`). Zero
  findings. Fixed: constructor arguments that hid members (now `<name>_`), `serve_read`'s
  `ar` hiding the `ar()` method, an initializer for `max_delay`. Scoped
  `lint_off UNUSEDSIGNAL` with a reason where the unused bits are deliberate: `of_aw`/`of_ar`
  take only the attribute fields, the memory ignores cache/prot/QOS/region/USER, and the
  shim reads only B's response. The core's two API interface classes are wrapped the way
  the weaver wraps its own (prototype arguments). `l2_ns`/`l2_mem_ns` re-run in both views:
  pass.
- The Verilator fault is reduced to about 60 lines and saved with a run script and notes in
  `repro/verilator-class-localparam/` (dependency log below), for you to fix or report.
- `max_delay` stays in time units; the old `l2_basic` xtor failure stays until P8; Jinja
  templates come with the P6 emitter.

  Commit set for these follow-ups: `flow.yaml` (`lint-xtor-ns-top` needs `behav-xtor`),
  `tests/lint/axi4_lint_xtor_ns_b2b.sv`, `src/behav/`, `src/core/fw_proto_axi4_core_pkg.sv`,
  `repro/verilator-class-localparam/`, `docs/`.

P6 status (2026-11-11, see [p6-abstractors.md](p6-abstractors.md)):
- Runtime (`fw_proto/src/fw_proto_abs.svh`) and generated glue (`fw_proto_weave/abs.py`)
  done. fw-hdl (`packages/fw-hdl`, branch): `fw_pin_rule::upper()`, `slot()`,
  `pin(..., slot)`.
- `dfm run ip`: `axi_ram`, `demofull` and `axi_crossbar` (2x2) pass: data against a
  reference, netlist equal to a hand-written one, Yosys synth. The crossbar shows ID
  widening (both memories see both slave ports) and 13 reads out of order on `s0`.
  `+plant` teeth caught for `axi_ram` and `demofull`.
- Found on the way: the emitter writes parameters wider than 32 bits sized (`64'h...`;
  Yosys truncated the unsized decimal); Yosys 0.70 reads a copy of RTL with `$error` as
  `$display` (`ip_checks.py`); verilog-axi's crossbar does not accept R beats of different
  IDs interleaved, hence the subordinate adapter's `r_interleave` knob (off by default; the
  L2 reorder tests turn it on). The behaviour's `#n` delays are in the package's 1 ns unit.
- D11 (burst API split into request and response) done mid-P6: core, behaviour, L2 env and
  cells, IP bench, lint top. `l2_ns` 24/24 and `l2_mem_ns` 27/27 in both views; lint 0
  findings; pytest 17/17. Not yet: planted bugs on the new paths.
- Follow-up: analysis for deadlocks of the two-way API, e.g. a response call that blocks
  on a channel the same process must drain (D11 rule 2). Possible hosts: the generated
  listeners, or fw-hdl's debug tracking of blocked runnables.
- Still open: D11 teeth; pin-map preset tests; `docs/reference-ips.md`; the old `l2_basic`
  failure (P8).

**Next action:** D11 teeth (planted bugs), preset tests, `docs/reference-ips.md`.

Open question raised by the user, not yet decided: move the weavers' SV text into Jinja
templates (pilot on `xtors.py`; best as an sv-weave `render(template, ctx)` that keeps the
origin line map).

## 2. Decisions to confirm before P1

These come from the design's open questions plus decisions this plan needs. Each has a
recommendation. The plan below assumes the recommendation.

| # | Decision | Recommendation |
|---|---|---|
| D1 | Parameterization | One struct value `axi4_param_t P` on every class and module (design §2). Verilator only; xezim out of scope |
| D2 | Where the protocol-agnostic pieces live (weavers, struct-port runtime, rule library) | **In this repo for now**, in a separate tree `fw_proto/` (Python + SV) that names no protocol. It moves to fw-hdl once a second protocol package reuses it. This keeps the work in one place while the shapes settle |
| D3 | Changes to dependencies | sv-weave and fw-hdl are editable checkouts under `packages/`. Changes are made there on a branch named `fw-proto-axi-new` in each repo, and listed in §8. I make no commits or pushes in them; you upstream them |
| D4 | Optional fields | **Done:** `(* fw_opt = "<P member>" *)` on the struct member; the field exists on the pins iff `P.<member> != 0`. So `HAS_QOS`/`HAS_REGION` are `int unsigned` 0/1, keeping one rule for all optional fields |
| D5 | AW/AR user widths | **Done:** separate `aw_t`/`ar_t` structs (no clean way to share one definition with different user widths) |
| D6 | Transaction API | Plain-argument `write`/`read` (design Q4) |
| D7 | Generated sources | Build output only, not committed. `weave-report.md` plus a `dfm run weave` target for inspection (design Q5) |
| D8 | Pin-level pre/post | `_pre` on the first `valid` cycle, `_post` on the handshake (design Q6) |
| D10 | Transaction APIs (after P5) | **Done:** streaming `axi4_burst_if` in the core on the channel payloads; `axi4_xact_if` a convenience shim on top, `read` by beat count (`p5-open-issues.md`) |
| D11 | Burst API direction (during P6) | **Done:** `axi4_burst_if` (blocking call/return) splits into `axi4_burst_req_if` and `axi4_burst_rsp_if`, carried by a socket and mirror. Responses are calls back, as they complete; no thread per outstanding transaction above the transactors. Blocking forms (`axi4_burst_blocking`, `axi4_xact_if`) are shims on top (design §3.4) |
| D9 | Repo | New style built next to the old code in this repo. The old code is deleted in P8, once its suites are ported (design Q7) |

## 3. Working conventions

### 3.1 Dependencies

- **Verilator:** use the project's `packages/verilator` (5.055). The `/tools` 5.041 that
  may be first on `PATH` fails sv-weave's sim tests (pre-existing, "CLASSREFDTYPE under a
  DOT"). For scripted runs: `export PATH=$PWD/packages/verilator/bin:$PATH`.

- **sv-weave**: `ivpm.yaml` dev dep, `dep-set: use`. Its own dev set would pull in the
  edapack RTL tools. Python 3.12.3 and pyslang 12.1.0 are already in the venv.
- **fw-hdl**: already a dependency. Two pieces of fw-hdl work exist only as uncommitted
  changes in the fw-hdl-sv-weave packet:
  - `pin`/`prefix` in `src/fw_extern.svh` (+60 lines);
  - the abstractor prototype in `tests/abstractor_proto`.

  P6 brings the first into `packages/fw-hdl`. It ports the second into `fw_proto/`
  (D2) as library code, not as a test.
- After `ivpm update`, re-run `uv pip install --no-deps -e packages/fw-hdl/python` (see
  the README). Check that the `svweave` and `fw-hdl` dfm plugins both load.

### 3.2 Logs, runs, commits

- Build, sim and formal output go to log files under `rundir/` or the scratchpad. Report
  pass/fail and the tail of the log.
- Wrap scripted `dfm` runs in `timeout`.
- No commits or pushes unless you ask for them in that message. Each phase ends with a
  proposed commit set for you to review.

### 3.3 Test configurations

Every class-level and RTL test runs over these parameter sets (`P_*` localparams in
`tests/env/axi4_test_params.svh`):

| Name | ADDR | DATA | ID | USER (all) | QOS/REGION | Purpose |
|---|---|---|---|---|---|---|
| `P_MIN` | 32 | 32 | 0 | 0 | off | absent fields everywhere |
| `P_DEF` | 32 | 64 | 4 | 0 | on | default |
| `P_WIDE` | 64 | 512 | 8 | 4/2/1/3/5 (distinct) | on | wide data; distinct user widths catch mix-ups |

## 4. Target layout

```
fw_proto/                      protocol-agnostic (moves to fw-hdl later, D2)
  python/fw_proto_weave/       sv-weave binding + weavers
    binding.py                 minimal fw binding
    bases.py  listeners.py  proxies.py  imps.py
    bundle.py                  channel APIs, field tables, bridges, wrappers, pin presets
    model.py                   shared reading of (* fw_* *) attributes
  python/tests/                pytest: golden outputs + Verilator compile checks
  src/                         SV runtime used by derived code
    fw_proto_pkg.sv
    fw_sp_base.svh  fw_rv_ch.svh  fw_bundle_base.svh
    fw_rule.svh  fw_count.svh  fw_flag.svh  fw_any.svh       (P7)
    fw_abs_base.svh  fw_emitter.svh  fw_proto_factory.svh     (P6, from the prototype)
  flow.yaml
src/
  core/fw_proto_axi4_core_pkg.sv     the hand-written specification (design §3)
  weave/sv-weave.yaml                weave configuration
  behav/                             adapters, memory model, endpoints (hand-written)
  rules/                             AXI4 rules (P7)
  cores/axi4_slice.sv                kept
  flow.yaml                          core -> weave -> behav filesets
  (old: class/ types/ xtor/ checker/ cores/axi4_*_core.sv, deleted in P8)
tests/
  weave/        pytest: AXI4-specific golden checks on the woven package
  unit/         SVUnit suites (new: *_ns_unit_test.sv while the old ones still exist)
  env/          harnesses (tlm, xtor views), test params
  ip/           reference-IP wrapper tests (P6)
  formal/       existing + new
docs/
```

## 5. Phases

Each task lists what it delivers, then how it is tested. A phase is done when all its
tasks are checked and its exit test passes.

### P0 Foundations

**P0.1 Import sv-weave.**
- [x] Add the dependency to `ivpm.yaml`; `ivpm update -a`; check the CLI and dfm plugin load.

**P0.2 Smoke test sv-weave in this tree.**
- [x] Superseded by `dfm run woven` on the real core (no separate smoke example): the venv, plugin and pyslang work here, and the woven package compiles in the `weave_ns` suite.

**P0.3 sv-weave model extensions** (in `packages/sv-weave`, branch `fw-proto-axi-new`).
Each gets a unit test in sv-weave's own `tests/unit`, in its existing style.
- [x] **S1 Generic class members.** Model the methods, arguments, typedefs and parameter
  header of a parameterized class, including an interface class, from its generic
  declaration. A specialization isn't required. Argument types are printed as written in
  the source (`ax_t`, not a resolved specialization).
- [x] **S2 Class-scope typedefs.** Expose `typedef` items of classes and interface
  classes, with their source text.
- [x] **S3 Packed-struct members.** For a typedef'd packed struct, expose the members in
  declaration order. Each member has a name, its width expression as written, the width
  value evaluated for a given specialization, and its `(* *)` attributes.
- [x] **S4 Design-level hook output.** Check that `on_design` + `add_item` can emit
  parameterized classes into `<pkg>_woven` without a woven target class. If a binding is
  mandatory, add a `null` binding option.
- [x] **S5 Weaver file output.** Let a weaver contribute a file (an SV module), not only
  package items. This is needed for the generated RTL role wrappers (P4). *`DesignCtx.add_file(name, text)`; the file compiles after the woven packages and init package and is verified with them. 226 sv-weave tests pass.*
- Test: `pytest packages/sv-weave/tests` passes in full (no regressions), plus a new test
  per item.

*Done (S1-S3):* one addition, `sv_weave.frontend.decl` (`SvDecl`), exposed as
`.decl` on `SvGenericClass` and `SvClass`. It reads the class's syntax only: parameter
header and names, `extends`/`implements`, attributes, typedefs (with packed-struct
members, their types as written and their attributes), methods (kind, return type,
arguments with direction, type, unpacked dims and default; implicit directions
inherited) and properties. It needs no specialization. Not provided: evaluated widths
(S3). Generated SV computes widths itself (`$bits`), so nothing needs them yet.
Test: `tests/unit/test_decl.py`.
*S4:* no change needed. A binding with no roots (`fw_proto_weave:FwProtoBinding`) and an
`on_design` handler with `add_item` produce `<pkg>_woven` with no woven classes; full
verify passes.

**P0.4 Flow skeleton.**
- [x] `fw_proto/flow.yaml` defines the `fw-proto-sv` SV fileset. The weaver plugin path is set in each `sv-weave.yaml` (`plugin-path`), not in the flow.
- [x] `src/flow.yaml` adds a `core` fileset and a `woven` task (`svweave.Weave`, config `src/weave/sv-weave.yaml`). `behav` comes with P5.
- [x] The existing filesets stay unchanged. `flow.yaml` imports `svweave` and adds the `fw_proto/flow.yaml` fragment.
- Test: `dfm run tests` (the old suites) still passes; `dfm run woven` runs on an empty core.

**Exit P0:** S1-S5 merged on the sv-weave branch and tested. The flow runs a weave step.

### P1 Generic weavers (pilot on fw-hdl's ready/valid APIs)

The weavers are proven on `fw_rv_initiator_if`/`target_if` (one method, `type T`
parameter) before AXI4. That pilot keeps them protocol-agnostic. Each weaver reads only
`(* fw_api *)` / `(* fw_listener *)` and the method model.

The pilot needs a header that is not `axi4_param_t`. The weavers re-emit **whatever
parameter header the source interface class has** (from S1), so `#(type T)` and
`#(axi4_param_t P)` are handled the same way.

**Implementation note.** One weaver, `fw_proto_weave:FwProtoWeaver` (`fw-proto`), with a
module per derivative (`listeners.py`, `bases.py`, `proxies.py`, `imps.py`, `bundle.py`).
They are not separate sv-weave weavers because the derivatives depend on each other (a
proxy needs the listener, a base is made for the listener too), and one `on_design`
handler emits them in declaration order. Options: `include` (more API names without the
attribute) and `derive` (a subset of the kinds).

Derived classes re-declare the API's typedefs as `typedef <if> #(P)::<name> <name>;`,
because an implementing class does not inherit an interface class's typedefs.

**P1.1 `model.py` + `binding.py`.**
- [x] Attribute parsing, the method/argument model on top of S1, and a minimal fw binding.

**P1.2 Base classes, `bases.py`** (design §4, "Base class").
- [x] `<if>_base` for every `fw_api` and listener interface.
- [x] Default bodies: empty for listeners; for APIs, an error naming the class and method, with outputs zeroed (a cast for named types, so enums are legal; `{}` for queues). The error is `$error` for now, not fw-hdl's `fw_error`, which needs a debug domain; the derived code has no fw-hdl dependency yet.
- [x] `(* fw_default *)` override.

**P1.3 Listener interfaces, `listeners.py`** (design §4.1).
- [x] `<api>_listener` with `<m>_pre(inputs)` and `<m>_post(inputs, outputs)`, all `void` functions. A non-void function's `_post` also gets `input <ret> __ret`.
- [x] Tagged `(* fw_listener *)`; P1.2 makes their bases.

**P1.4 Proxies and fan-outs, `proxies.py`** (design §4.2).
- [x] `<api>_proxy`: target, `add_listener`/`remove_listener`, pre → forward → post. For a task the post runs after the forwarded call returns, and it is also correct for functions with a return value.
- [x] `<api>_listener_fanout`.

**P1.5 Imps, `imps.py`** (design §4.4 step 1).
- [x] `<api>_imp #(<params>, type IMP)`: forwards to `IMP`. A plain class for now; making it an `fw_export` waits for the fw binding (P6).
- [ ] Step 2 (the per-field weaver) is deferred until the fw binding has factory support (P6).

**Tests:**
- [x] `fw_proto/python/tests`: golden output per weaver for the rv APIs and for a synthetic API covering task/function, output args, queues, a non-void function and a `#(type T, int N)` header. Goldens are refreshed by a flag and reviewed in the diff.
- [x] Compile check: Verilator `--lint-only -Wall` on the woven packages with two specializations (`test_lint_wall`).
- [x] Behaviour (SVUnit, `tests/unit/weave_ns_unit_test.sv`, suite `weave_ns`; on the AXI4 APIs and the synthetic one rather than rv):
  - a proxy calls pre and post in order around a blocking `send`, with two listeners;
  - remove works;
  - the fan-out reaches all listeners;
  - a `_base` subclass overriding one method compiles (the error path itself is checked in the golden, not run: `$error` stops Verilator);
  - `fw_default="empty"` is silent.
- [x] Replace `FW_RV_TARGET_IMP` with the generated imp in one copy of an fw-hdl rv test (in this repo, not in fw-hdl), and check that it behaves identically. *Suite `rv_pilot` (`tests/rv_pilot`, `tests/weave/rv/sv-weave.yaml`): the weaver's `include` option names the three rv APIs (no attribute in fw-hdl). The generated imp is the `fw_export`'s implementation object, and the sink implements `put()`. fw-hdl's original runs beside it, and the two sink transcripts are compared.*
- [x] `fw_proto/README.md`.

**Exit P1:** pytest goldens and compile checks pass; `rv_pilot` passes. *Met.*

### P2 AXI4 core specification

**P2.1 `src/core/fw_proto_axi4_core_pkg.sv`** (design §3.1-3.4).
- [x] `axi4_param_t` (now with `HAS_QOS`/`HAS_REGION`), the defaults, `w1`, the enums, and the burst arithmetic, ported from `axi4_types_pkg` (at 64-bit addresses, independent of `P`).
- [x] `axi4_types #(P)` with the channel structs and `fw_opt` attributes (D4, D5), plus `attr_t`, `addr_t`, `data_t`, `strb_t` for the transaction API.
- [x] `axi4_bundle #(P)`.
- [x] `axi4_xact_if #(P)` (D6), with the local typedef block (design §6.2 rule).
- Target: ≤ 200 lines, all of it read in review. *Actual: 225, of which ~60 are burst arithmetic.*

**P2.2 Weave config.**
- [x] `src/weave/sv-weave.yaml` enables the P1 weavers on the core.

**Tests:**
- [x] `tests/unit/types_ns_unit_test.sv`: port of `types_unit_test` (burst arithmetic, legality, 4 KB) onto the new package. *Plus exclusive-access legality and above-4 GB cases; the lane helpers and `axi4_excl_legal` were ported into the core for it (and for the P5 memory model).*
- [x] Width checks: `$bits` of each payload for `P_MIN`/`P_DEF`/`P_WIDE`, against values worked out by hand in the test.
- [x] (in `fw_proto/python/tests/test_weave.py`) the woven package contains `axi4_xact_if_{base,listener,listener_base,proxy,listener_fanout,imp}`, and Verilator compiles it for all three P.

**Exit P2:** types suite passes for all three P; the woven package compiles. *Met (the helpers are independent of P).*

### P3 Bundle derivatives and struct-port runtime

**P3.1 Struct-port runtime** (`fw_proto/src`).
- [x] `fw_sp_base`: field table, `link`, `bind_inner`. Port it from the prototype (`abs_lib.svh:124-238`) as library code. *Without the prototype's `fw_realized` owner and `connect()`: those need the fw-hdl component model and arrive with the abstractors (P6). The role is an index into the bundle's roles; the typed `link`/`bind_inner` are generated.*
- [x] `fw_rv_ch #(type T)`: the rv family. It holds the valid/ready fields and a payload; the payload fields come from the bundle weaver. *`add_ctl(sp, ch, dir)` adds `<ch>valid`/`<ch>ready`.*
- [x] `fw_bundle_base`: an ordered list of channels with their fwd/rev direction. *Not a separate class: the generated field table already lists the channels in order with their directions, and nothing yet needs channels without pins.*
- [x] `fw_inbox #(T)` (from `axi4_l1_inbox`): the per-channel queue the generated inboxes use.

**P3.2 Bundle weaver, `bundle.py`.** It reads `(* fw_proto_bundle *)`, the channels, the payload struct members (S3) and `fw_opt`.
- [x] Channel APIs `axi4_req_if`/`axi4_rsp_if` (design §4.3), tagged `fw_api`, so P1 makes their bases, listeners, proxies and imps.
- [x] Socket and mirror typedefs per role. *As the role ports `axi4_mgr_sp`/`axi4_sub_sp`. The API side of a socket (port of `req` + export of `rsp`) needs fw-hdl's `fw_port`/`fw_export`; it is generated with the abstractor glue in P6.*
- [x] Field table per bundle and specialization. Pin names are `<ch><signal>`/`<ch><member>`, and absent fields are dropped. *`axi4_sp::build_fields()`; widths are `$bits(<ch>.<member>)`, presence is `if (P.<fw_opt> != 0)`. IDs are now `fw_opt = "ID_W"`.*
- [x] Endpoint helpers (`clear`/`idle` over the channels). *`<api>_inbox` per channel API.*
- [x] sprint/compare per payload. *`axi4_payloads #(P)::<ch>_sprint/_compare`, hex values.*
- [ ] Pin-map presets `axi4_preset_{s_axi,m_axi,S_AXI,M_AXI}`. These are generated, but they need `pin`/`prefix` from fw-hdl, so their tests run in P6.

**Tests:**
- [x] Goldens + Verilator compile for all three P.
- [x] Field-table test (SVUnit `bundle_ns_unit_test`): the generated table for each P equals the AMBA pin list worked out by hand in the test, with names, widths, directions, and absent fields missing under `P_MIN`.
- [x] The total fwd/rev bit counts match `axi4_checker.sv`'s port widths for the same P. That gives a cross-check against the existing RTL. *For `P_WIDE`, where every field is present; the checker carries absent fields as w1() bits, so for the others only the hand pin lists apply.*
- [x] Channel API: a test manager and subordinate built from `axi4_req_if_base`/`axi4_rsp_if_base`, linked directly (tlm view), exchange beats through proxies, and a listener records pre/post. *The generated inboxes are the endpoints.*

**Exit P3:** field-table and tlm channel tests pass for all three P. *Met; the presets stay open for P6.*

### P4 Transactors and back-to-back

**P4.1 fw-hdl rv transactor changes** (in `packages/fw-hdl`, branch `fw-proto-axi-new`).
- [x] Run-time queue depth (up to a maximum `localparam`). *`depth` (default 4 initiator/target, 8 monitor), `MAX_DEPTH` = 16, in the `_xtor_if` interfaces.*
- [x] Run-time stall settings on the target and initiator sides, carrying over today's `max_gap` behaviour. *`max_gap` (default 0), applied on the link side, so the synthesizable cores are unchanged: initiator, valid stays low a random 0..max_gap cycles before each beat; target, link ready is held low that long before each beat. The target core's 1-deep buffer still takes one beat, so on the pins ready drops from the next beat on.*
- [x] The rv monitor must report the first valid cycle (for `_pre`) as well as the handshake. *The monitor core gains `up_first`/`up_xfer` link outputs (one link beat per pin cycle with an event); the interface adds `get_ev(t, first, xfer)`, and `get()` still returns transfers only, so `fw_rv_monitor_bridge` is unchanged.*
- Test: fw-hdl's rv tests still pass (run in `packages/fw-hdl`). *135 passed, 83 skipped (XLS tools absent); new `tests/rv_proto/rv_knobs_tb.sv` + `test_runtime_knobs`. fw-hdl's harness expects `<fw-hdl>/packages`; run it with a temporary `packages -> ..` symlink and `packages/yosys/bin` on `PATH` (for sby).*

**P4.2 Generated role wrappers** (S5).
- [x] `axi4_mgr_xtor`, `axi4_sub_xtor`, `axi4_mon_xtor`: modules `#(axi4_param_t P)` that instantiate five rv transactors and splice the payload structs onto the AMBA pins, using checker names, so `axi4_checker` binds with `.*`. *Weaver option `xtor`, task `woven-xtor`. Clock and reset from the bundle's `fw_clock`/`fw_reset_n`. Pins as wide as the fields (an absent field keeps a one-bit pin, tied to 0); enum fields are `logic` pins. The class side is `u_if` (`axi4_<role>_xtor_if`), which holds an `axi4_<role>_xtor_chans` handle (an interface may not hold vifs) and a `bound` flag the bridges wait for. Same names as the old modules: the two are never compiled into one image (P8 deletes the old ones).*
- [x] Generated bridges per role (design §4.5) drive the channel proxies. *`new(vif, <in-api> handle)`; outbound `<ch>(t)` → `vif.chans.<ch>.send(t)`; `run()` forks one `recv → m_<api>.<ch>(t)` loop per inbound channel; the monitor bridge calls `<ch>_pre`/`<ch>_post` on `req`/`rsp` listener fan-outs. Test: suite `xtor_ns` (3/3), `pytest fw_proto/python/tests` (goldens + `-Wall` per wrapper and P).*

**P4.3 Back-to-back.**
- [x] Manager wrapper → `axi4_slice`-based cores → subordinate wrapper, with `axi4_checker` on the link. *`l1_ns` xtor view: `axi4_sub_core` → `axi4_mgr_core` between the generated wrappers, joined by their packed user streams; a checker on each pin segment.*
- [x] Port `l1_basic` to the new channel API as `l1_ns`, running in both views (`tlm`: direct link; `xtor`: through pins), as today. *Traffic made protocol-legal (the checkers must stay at zero). `cfg_masks` and `wire_round_trip` are not ported: they test the old run-time `axi4_cfg` masking and stream packing, which the new types replace with compile-time P (covered by `types_ns`/`bundle_ns`).*
- [x] Backpressure from outside: random stalls configured per channel by path. *`set_knob("<role>.<ch>.max_gap|depth", v)`; the test runs the same traffic with and without gaps and requires the gapped run to take at least 25% longer on the pins.*

**Tests:**
- [x] `l1_ns` passes in both views for all three P, with `axi4_checker` in COUNT_ONLY mode reporting zero violations.
- [x] Verilator lint of the generated wrappers at zero findings (`lint-rtl` extended). *Task `lint-xtor-ns`; a separate top because the generated wrappers reuse the old transactors' names.*
- [x] Formal: the existing `axi4_fv` back-to-back BMC is re-pointed at the generated wrappers' cores. The bound stays the same. *`axi4_fv_ns` beside `axi4_fv` (the old cores stay in use until P8): depth 16, same checkers and capacities; the cores' links carry the old stream layout, so `axi4_stream_chk` is reused and the widths are cross-checked at elaboration. Covers and teeth as above.*

**Exit P4:** `l1_ns` (2 views × 3 P), lint, and `fv` pass. *Met.*

### P5 Behaviour: adapters, memory model, transaction API

**P5.1 Port the behavioural code** to the new types (`src/behav/`):
- [x] the manager adapter (`axi4_xact_if` → beats; per-ID matching; AW+W kept together);
- [x] the subordinate adapter (beats → `axi4_xact_if`; W joined to AW; per-ID turns; `max_delay` reordering);
- [x] the memory model (strobes, narrow/unaligned bursts, exclusive access, error ranges);
- [x] `axi4_to_mem`.

These extend generated `_base`/`_imp` classes. No `FW_AXI4_*` macros remain.

**P5.2 Endpoints.**
- [x] The L1 inbox and endpoints rebuilt on generated helpers and `_base` classes. *Done in P3: the generated `axi4_{req,rsp}_if_inbox` on `fw_inbox`.*

**Tests:**
- [x] Port `l2_basic` (with the backpressure test) and `l2_mem` as `l2_ns`/`l2_mem_ns`, in both views, for `P_DEF` and `P_WIDE` (and `P_MIN` where IDs make no difference). *All three P for every test.*
- [x] A test with a listener on the transaction-API proxy recording `write_pre`/`write_post`. *`xact_listener`.*

**Exit P5:** all ported suites pass. Compare the old and new suite results on the same seeds; any difference is explained in the status note.

### P6 Abstractors, extern wrapping, reference IPs

**P6.1 fw-hdl `pin`/`prefix`.**
- [x] Apply the fw-hdl-sv-weave packet's `src/fw_extern.svh` change to `packages/fw-hdl` (branch). *Applied from that packet's working copy (same base, fw-hdl `6f45fe0`). Added `fw_pin_rule::upper()` for upper-case pin names (wb2axip).*
- [x] Add a bit-slice `pin` form for packed-vector pins (crossbar). *The change's `pin(name, ep, field, msb, lsb)` slices the field (one field over several pins). Added for the crossbar: `fw_pin_rule::slot(k)` and `pin(..., slot)`, a field in slot k of a packed pin; the emitter concatenates a pin's slots and checks they are 0..n-1, each once.*

**P6.2 Abstractor runtime** (`fw_proto/src`), ported from `tests/abstractor_proto/abs_lib.svh`:
- [x] the abstractor base; *`fw_proto_abs.svh`, included in `fw_proto_pkg`, which now imports `fw_hdl_pkg`. `fw_sp_base` is an `fw_endpoint` with an owner.*
- [x] the emitter (netlist + simulation wrapper + shells); *monitor shells dropped until a monitor is generated (A5).*
- [x] the factory stand-in (`fw_proto_factory`) until fw-hdl's factory is wired in;
- [x] configuration by path (`fw_proto_cfg`). *Handles pass knobs set for their path to the channel transactors.*

Fix the known prototype issues where they block: resolution order (brief §8), and never
`$cast` to an interface class.

**P6.3 Bundle-derived abstractor glue** (design §4.5): `connect()` overloads with
auto-insertion of `<port>_abs` per role, and the emitter string tables.
*Done in `fw_proto_weave/abs.py` (xtor option): `<proto>_<role>_socket` (fw_socket/fw_mirror),
`_abs`, `_abs_h`, and `connect()` on the role ports. Goldens not yet refreshed.*

**P6.4 Reference IPs**, fetched with ivpm (git) into `packages/`:
- [ ] verilog-axi (`axi_ram`, `axi_crossbar`);
- [ ] wb2axip (`demofull`).

PULP waits on brief Q2.

**Tests:**
- [ ] `tests/ip/axi_ram`: an extern class plus one preset line. The emitted netlist equals a hand-written instantiation (text compare after normalization) and synthesizes in Yosys. It is driven through inserted abstractors from a class test running the `l2_mem_ns` scenarios. Stalls set by path reach the pins (checked by counting idle cycles).
- [ ] `tests/ip/demofull`: upper-case preset, active-low reset, extra non-AXI pins tied or left open.
- [ ] `tests/ip/axi_crossbar` (2×2): bit-slice mapping, ID widening, out-of-order across IDs accepted by the manager adapter.
- [ ] Pin-map preset tests: each preset resolves every field of `P_DEF` and `P_WIDE` against the IP's module header, with no unmapped bit (fw-hdl's checks).

**Exit P6:** the three IP tests pass; their netlists match; Yosys synth passes.

### P7 Rules in simulation (brief A3)

**P7.1 Rule library** (`fw_proto/src`):
- [ ] `fw_rule #(type L)` extends `L`'s `_base`;
- [ ] `fw_count`, `fw_flag`, `fw_any #(T)` (simulation: evaluates every value seen, as a set of tracked keys).
- [ ] Record vocabulary gaps for brief Q3.

**P7.2 AXI4 rules** (`src/rules/`): the brief §5 set, each a class on a channel-API listener.
- [ ] correspondence;
- [ ] same-ID order (read and write);
- [ ] R grouping;
- [ ] W grouping;
- [ ] B after AW and last W;
- [ ] burst legality;
- [ ] outstanding capacity;
- [ ] exclusive access (escape hatch).

**P7.3 Signal-level rules** on `fw_rv_ch` from `_pre`/`_post` (design §4.1).

**P7.4 Attachment.** Rules attach by path to proxies (contract), producers (guarantee) and consumers (requirement).

**Tests:**
- [ ] All rules are attached in every P4-P6 test and pass.
- [ ] Teeth: port `chk_teeth` to `rules_teeth_ns`. Each rule has a seeded-bug scenario (a misbehaving `_base`-derived model) that must fire, with the report naming the API event (method, ID, beat index).
- [ ] The same seeded bugs run against `axi4_checker` give agreeing verdicts.

**Exit P7:** rules pass on all IPs; every teeth case fires exactly its rule.

### P8 Retire the old package

- [ ] Delete `src/class`, `src/types`, `src/xtor`, `src/cores/axi4_{mgr,sub}_core.sv` and the old test envs and suites, once every old suite has a passing `_ns` port (§6.2 map).
- [ ] Rename the `_ns` suites.
- [ ] Decide `axi4_checker`'s fate (kept as reference until A4).
- [ ] Update `ci/run.sh` and the flows.
- Test: `ci/run.sh` passes from a clean bootstrap (`CI_SKIP_BOOTSTRAP` unset).

## 6. Test plan summary

### 6.1 Layers

| Layer | Tool | Where | Runs in CI |
|---|---|---|---|
| Weaver goldens | pytest | `fw_proto/python/tests`, `tests/weave` | yes, new `pytest` step in `ci/run.sh` |
| Compile matrix | Verilator `--lint-only`, 3 P | same | yes |
| sv-weave extensions | pytest | `packages/sv-weave/tests` | sv-weave's CI (after upstreaming); locally per change |
| Class/tlm behaviour | SVUnit via dfm | `tests/unit` | yes (`tests`) |
| Pin-level behaviour | SVUnit, xtor view | `tests/unit` | yes |
| Reference IPs | SVUnit + emitter + Yosys | `tests/ip` | yes (`smoke` takes `axi_ram` only) |
| RTL lint | Verilator, zero findings | `lint-rtl` | yes |
| Formal | SymbiYosys | `tests/formal` | `fv-cover`, `fv-prove`, `fv-teeth` per commit; `fv` (BMC) with `CI_FV_BMC=1` |

### 6.2 Old suite → new suite

| Old | New | Phase |
|---|---|---|
| `types_unit_test` | `types_ns` | P2 |
| `l1_basic` | `l1_ns` | P4 |
| `l2_basic` (incl. backpressure) | `l2_ns` | P5 |
| `l2_mem` | `l2_mem_ns` | P5 |
| `chk_teeth` | `rules_teeth_ns` (+ checker cross-check) | P7 |
| formal `axi4_fv` | re-pointed at generated wrappers | P4 |
| formal `axi4_slice_fv`, `axi4_checker_fv`, `teeth.sh` | unchanged | — |
| lint tops | extended with generated wrappers | P4 |

## 7. Documentation plan

| Doc | Content | When |
|---|---|---|
| `docs/design-new-style.md` | Kept current as decisions settle (§2 answers folded in) | each phase |
| `docs/plan-new-style.md` | This file; status and checkboxes | each task |
| `docs/core-spec.md` | A reading guide to the core package: what each declaration means and which derivatives it produces | P2 |
| `docs/derived-classes.md` | Every generated class: naming (`<if>_base`, `<api>_listener`, `<m>_pre/_post`, `<api>_proxy`, …), default bodies, when to extend which. Written by hand, with an example of each taken from the woven output | P1, extended P3 |
| `docs/writing-a-protocol-package.md` | How to build the next protocol in this style: the core declarations, the attributes, the weave config, the tests to write. This is the reusable deliverable of the work | P5, finished P7 |
| `docs/rules.md` | The AXI4 rules, their kind, attachment, and the vocabulary gaps found | P7 |
| `docs/reference-ips.md` | How each IP is wrapped (the one-line presets), and what each tests | P6 |
| `docs/overview.md`, `README.md` | Rewritten for the new structure. The old content is dropped in P8 | P8 |
| `docs/brief-answers.md` | Answers to the brief's §10 questions, for the fw-hdl-sv-weave packet | P6/P7 |
| sv-weave docs | `docs/concepts.rst` and the model reference updated for S1-S5 (in sv-weave) | P0 |
| `fw_proto/README.md` | What the protocol-agnostic tree is and that it moves to fw-hdl | P1 |

## 8. Dependency changes log

Changes made in editable dependencies, for upstreaming. Branch `fw-proto-axi-new` in each.

| Repo | Change | Status |
|---|---|---|
| fw-proto-axi (this) | `ivpm.yaml`: sv-weave dev dep | done, uncommitted |
| sv-weave | S1-S3: `frontend/decl.py` (`SvDecl`), `.decl` on `SvGenericClass`/`SvClass` (`frontend/model.py`), `tests/unit/test_decl.py` | done, uncommitted, branch `fw-proto-axi-new` |
| sv-weave | S4: none needed | — |
| sv-weave | S6 `sources.top` (config) / `SourceSpec.tops`: the top modules slang elaborates (`frontend/loader.py`, `verify.py`, `config.py`, `filelist.py`, hash in `run.py`; 3 tests in `test_loader.py`). Needed to weave fw-hdl: `fw_root`'s `type Tbind = int` cannot elaborate as an implicit top | done, uncommitted, branch `fw-proto-axi-new` |
| sv-weave | Fix in S1: `decl.py` `_txt` rebuilds text from tokens, so a comment before `interface` no longer hides it (`is_interface` was false for fw-hdl's rv APIs) and comments stay out of headers and types; test in `test_decl.py` | done, uncommitted, branch `fw-proto-axi-new` |
| sv-weave | Gap found: the run's input hash covers a plugin's version string, not its source, so an edited weaver gives a stale "up to date" result under dfm | to raise |
| sv-weave | S5 weaver file output: `DesignCtx.add_file(name, text)` (`weave/design.py`, `bus.py` passes `files`), rendered with the header and origin line map (`render.render_file`), compiled after `sv_weave_init.sv`, verified like the packages; clashes with sv-weave's own file names and differing re-adds are errors (`run.py`); 8 tests in `test_design.py` | done, uncommitted, branch `fw-proto-axi-new` |
| slang (pyslang 12.1.0) | Bug found: two distinct packed structs with the same members are taken for one type in an interface's type parameter (`virtual ifc #(b_t)` resolves as `ifc #(a_t)`), so legal vif assignments fail. Repro: two `typedef struct packed {logic [3:0] a;}` in a class, `ifc #(a_t) ia(); ifc #(b_t) ib();`, assign each to its vif. Worked around: the `woven-xtor` weave elaborates under an empty stub top (`src/weave/xtor_weave_top.sv`) so verify does not elaborate the wrappers; Verilator lints them | to raise (slang) |
| sv-weave | A woven package now repeats its user package's wildcard imports (`SvPackage.imports`, `frontend/model.py`; `run.py` `new_pkg`), so woven code sees the user package's scope; golden `two_packages` updated; test `test_woven_package_repeats_user_imports`. 227 tests pass | done, uncommitted, branch `fw-proto-axi-new` |
| fw-hdl | Bug found by `axi4_fv_ns`: the rv cores' `valid` (initiator) / `up_valid` (target, monitor) were registers cleared only at the first reset edge, so undefined in the first reset cycle (AXI A3.1.2 needs VALID low throughout reset). Now gated: `assign valid = valid_q & !reset` (`fw_rv_{initiator,target,monitor}_xtor_core.sv`). fw-hdl's own core proof (`tests/rv_proto/formal/fw_rv_cores_fv.sv`) held valid stable into a mid-run reset; its two hold properties now exempt cycles with reset high. `tests/rv_proto` 9/9; the full fw-hdl suite has 45 failures (mmio/regblock, xls, order), identical on a clean worktree of fw-hdl HEAD, so not from this work | done, uncommitted, branch `fw-proto-axi-new` |
| sv-weave | `sv_weave_init.sv` declares `sv_weave_init_pkg`, so Verilator `-Wall` reports DECLFILENAME on it; waived by path in `lint-waivers-xtor-ns.yaml` | to raise |
| Verilator 5.055 | Bug found: internal fault (V3Param "Expected module parameterization") on a virtual interface whose type parameter is a class-scoped type of a parameter (`virtual fw_rv_target_xtor_if #(ty #(P)::b_t)`). Worked around in the generated code: a local `typedef ty #(P)::b_t b_t;` first | to raise (Verilator) |
| sv-weave | Gap found: two `svweave.Weave` tasks in one image both define `sv_weave_init_pkg`. Worked around by weaving the test sources in one run (`tests/weave/sv-weave.yaml`) | to raise |
| fw-hdl | rv transactor run-time `depth`/`max_gap`; monitor first-valid event (`up_first`/`up_xfer`, `get_ev`); `tests/rv_proto/rv_knobs_tb.sv`, `test_runtime_knobs` (`src/std/rv/fw_rv_{initiator,target,monitor}_xtor_if.sv`, `fw_rv_monitor_xtor{,_core}.sv`). Lint: the new state (`gap_left`, `drawn`) has no declaration initializer, so `-Wall` adds nothing to fw-hdl's existing PROCASSINIT warnings | done, uncommitted, branch `fw-proto-axi-new` |
| fw-proto-axi (this) | `ivpm.yaml`: yosys (sby) declared directly (was only via fw-hdl) | done, uncommitted |
| fw-hdl | Found at HEAD `6f45fe0`, not caused here: 42 regmap/regblock/mmio/structural_top tests fail (register sources omit the now-required `parent` argument; `dma_channel_regs` has no registers). `test_knobs::test_dfm_resolve` assumes a standalone checkout (`packages/python/bin/dfm`) | to raise |
| Verilator 5.055 | Bug found: internal fault (endless recursion after V3Class; segfault or OOM) on a class `localparam` from `$bits(type param)` used in nested loop bounds and part-select indices, with the indexed queue filled by an interface-class call. Reduced repro with script and notes: `repro/verilator-class-localparam/`. Worked around in `axi4_to_mem` (a run-time member) | to raise / fix (repro saved) |
| fw-hdl | `fw_extern` `pin`/`prefix` (from fw-hdl-sv-weave) + bit-slice form | planned (P6) |

## 9. Later (outlined only)

- **A4, formal generation:** rules → SVA through the field table; SymbiYosys job per wrapped IP; comparison with wb2axip `faxi_slave`. It needs the rules restricted to the formal vocabulary (P7 records where they aren't).
- **A5, monitor transactions:** assemble transactions from channel listener events with ID matching. Data-integrity rule.
- **A6, systems:** manager → interconnect → RAM assembled at class level; monitors on internal links; DMA as a manager IP.
- **pyhdl-if:** generate API definitions from the `fw_api` model once pyhdl-if is in the workspace.
- **Move `fw_proto/` to fw-hdl** (D2).

## 10. Risks

| Risk | Mitigation |
|---|---|
| S1 (generic class members) is larger than it looks in sv-weave's pyslang front end | Fallback from the design §6.2: weave from the default specialization and re-emit the header. P1's pilot shows which is needed early |
| Verilator issues with parameterized classes (downcasts fail silently; `$cast` to interface classes) | Derived code never casts. Handles are typed by interface class. Add a Verilator check to the P1 compile matrix that exercises the generated classes through interface-class handles |
| Struct payloads lose their typedef name in the emitter (`logic [W-1:0]`) | The generated wrappers and bridges use the struct type directly; the emitter only passes `P` |
| The fw-hdl abstractor and pin-map work is still uncommitted in another packet | Ported here (D2, P6.1-P6.2). Coordinate before that packet lands its own version |
| Long BMC (`fv` ~6.5 min) slows P4 iteration | Run it per phase, not per edit; `fv-cover` per commit |
