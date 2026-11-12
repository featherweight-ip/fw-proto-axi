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
| P2 AXI4 core specification | done | `types` passes |
| P3 Bundle derivatives + struct-port runtime | mostly done | runtime, field tables, role ports, inboxes, sprint/compare done; pin-map presets wait for fw-hdl `pin`/`prefix` (P6) |
| P4 Transactors and back-to-back | done | `l1` (2 views × 3 P), stalls by path, `lint-xtor`, `fv` on the generated cores (`axi4_fv`); core spec split into a synthesizable and a class package (D-fv) |
| P5 Behaviour: adapters, memory model, transaction API | done | streaming `axi4_burst_if` + convenience shim (D10); `l2` 24/24, `l2_mem` 27/27 in both views; at P5 `dfm run tests` was 18 of 19 (the old `l2_basic` xtor failure, gone with P8) |
| P6 Abstractors, extern wrapping, reference IPs | done but the deadlock follow-up | `axi_ram`, `demofull`, `axi_crossbar`, presets pass (`dfm run ip`); D11 teeth 9/10 caught (one known gap). See [p6-abstractors.md](p6-abstractors.md), [reference-ips.md](reference-ips.md) |
| P7 Rules in simulation | done (regression below) | rule library in `fw_proto/src`, nine AXI4 rules in `src/rules`; on every L1/L2/b2b link and every IP abstractor (by path); `rules_teeth` 17/17 both views, `rules_pins` 13/13 (agrees with `axi4_checker`). See [rules.md](rules.md) |
| P8 Retire the old package | done | old package, cores and suites deleted; `_ns` names dropped; `ci/run.sh` from a clean bootstrap passes (lint-rtl, tests 14/14, fv-cover, fv-prove, fv-teeth). §5 P8 |
| P9 Docs, Jinja assessment, upstream fixes | in progress | §11 |
| Later: formal generation (A4), monitor transactions (A5), systems (A6) | not planned in detail | §9 |

**Last update:** 2026-11-12 (P8 committed and pushed, `e71d2b5`; P9 started, §11). Names: the dated notes from P2 to
P7 use the `_ns` suite, file and task names of the time; P8(c) (§5) maps them to the
current ones. The derivation runs as dv-flow tasks: `dfm run woven`
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

Passing (2026-11-12, `ci/run.sh` from a clean bootstrap: `dfm run tests` 14 of 14 runs; `dfm run lint-rtl` (`lint`, `lint-xtor`) at zero findings; `fv-cover`, `fv-prove`, `fv-teeth` pass; outside the per-commit set, `dfm run fv` (BMC depth 16, 122 s) and `dfm run ip` also pass, logs `rundir/p8d/{fv,ip}.log`):
- `types` 7/7: burst helpers, lanes, exclusive access, 64-bit addresses;
- `weave` 5/5: widths, proxy/listener order, remove, fan-out, imp, channel APIs over
  `P_MIN`/`P_DEF`/`P_WIDE`; synthetic `#(type T, int N)` API;
- `bundle` 5/5: field table vs. the AMBA pin list by hand for all three P;
  totals vs. `axi4_checker`'s port widths (`P_WIDE`); role-port link/bind/directions;
  sprint/compare with absent fields; tlm link through the channel proxies, an inbox
  stall holding AW only, and a listener's pre/post order;
- `rv_pilot`: fw-hdl's `tests/rv_proto` run as is and with its sink's
  `FW_RV_TARGET_IMP` replaced by the generated `fw_rv_target_if_imp` (behind an
  `fw_export`); identical sink transcripts (8 beats, same times);
- `xtor` 3/3: the generated `axi4_{mgr,sub,mon}_xtor` and bridges back to back, one
  link per P, `axi4_checker` (COUNT_ONLY) at zero; every beat checked at the far end and
  at the monitor (pre and post); fails as it should with a corrupted `wlast` splice;
- `l1` 15/15 in each view (`tlm`, `xtor`): channels one at a time, all five
  concurrently, AW stalled while W/AR/R flow, every response code and burst type (EXOKAY
  on exclusive accesses), and stalls set by path, each for `P_MIN`/`P_DEF`/`P_WIDE`.
  Protocol-legal traffic; in `xtor` the link is generated manager → pins → one `axi4_slice`
  per channel each way → pins → generated subordinate, with `axi4_checker` (COUNT_ONLY) at zero on
  both pin segments. Fails as it should with WLAST forced to 1 (checker counts) and
  with the path-set gaps zeroed (timing check);
- `lint-xtor` (part of `lint-rtl`): Verilator `-Wall --timing` of the generated
  wrappers, bridges and woven package for the three P, zero findings (fw-hdl's own files
  and sv-weave's init-file name waived by path, `lint-waivers-xtor.yaml`);
- `lint` (part of `lint-rtl`): `axi4_checker` and `axi4_slice` under the three P
  (`tests/lint/axi4_lint_rtl.sv`), zero findings;
- `l2`, `l2_mem`, `rules_teeth` in both views, `rules_pins`, `rv_pilot`: see P5 and P7 below;
- `pytest fw_proto/python/tests`: 17/17 (goldens incl. the nine xtor files and the defs woven package; sv2v of the class-free layer; derived-class
  list, Verilator `-Wall` of the woven package and of each wrapper + bridge for all three P);
- `pytest packages/sv-weave/tests`: 227 passed (needs Verilator 5.055 first on `PATH`; §3.1).

Old suites: deleted in P8. Before that all passed except `l2_basic` xtor view,
`concurrent_ids` (the checker's MAX_OUT capacity assertion), which predated this work;
its port (`l2`) passes.

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
- D11 teeth (2026-11-11): `tests/teeth/behav_teeth.py` plants 10 bugs in the D11 paths
  (blocking shim, both adapters, the xact target), runs `l2_ns`/`l2_mem_ns` in both views
  and the crossbar, and restores the file; table in `rundir/teeth/summary.md`. The first
  run caught 4 of 10. The misses were test gaps, now closed:
  - a response inside the request call never reached the shim or the manager adapter
    (the subordinate adapter always decouples): new `inline_responses`, over a direct
    path `blk_d -> mgr_d -> isub` (a stub that answers inside the call);
  - the shim serializes writes, so nothing overlapped two writes at the manager adapter:
    new `concurrent_writers`, callers straight on `mgr_d` with a time unit per W beat;
  - `test_target` answered in zero time, so per-ID order was never tested at the xact
    target: `concurrent_ids` now delays each call 0..300 at random and answers SLVERR in
    the upper half of the address space (a B given to the wrong caller shows).

  Now 9 of 10 caught. Known gap: B sent from inside the subordinate adapter's response
  call (`sub_b_inline`) only slows these topologies; it deadlocks only in a cycle, so it
  belongs to the deadlock follow-up below. The burst-target checks moved into the env
  (`check_bursts`), shared by `burst_fidelity` and `inline_responses`.
- Pin-map presets: `tests/ip/presets`, in the `ip` root. `docs/reference-ips.md` written.
- Regression after these: `l2_ns` 30/30 and `l2_mem_ns` 27/27 in both views; `dfm run ip`
  passes (three IPs and presets); `lint-rtl` passes; pytest 17/17; `dfm run tests` fails
  only the old `l2_basic` xtor (P8).
- Still open: the deadlock analysis (follow-up above); the Jinja question below.

- P7 (2026-11-12): rules in simulation, see [rules.md](rules.md).
  - Library (`fw_proto/src`): `fw_rule`, `fw_count`, `fw_flag`, `fw_value`, `fw_any`,
    `fw_rule_node`, `fw_rule_set`, `fw_rv_hold`. AXI4 (`src/rules`, filesets `rules` /
    `rules-xtor`): `resp_match`, `r_burst`, `w_burst`, `b_order`, `burst_legal`,
    `w_lanes`, `capacity`, `exclusive` (free form), `rv_hold` (pins).
  - Attached in `xtor_ns`, `l1_ns`, `l2_ns`, `l2_mem_ns` and the three IPs; all pass.
    The IP rules attach by path (`axi4_observers`, new in `abs.py`). Its first form
    attached at the handle's `run()` and lost the first AW on `demofull` and the
    crossbar (a B with no write outstanding), so a handle now registers when built.
  - Teeth: `rules_teeth_ns` 17/17 in both views (the xtor view's checker agrees on the
    side); `rules_pins_ns` 13/13 (chk_teeth's pin sequences).
  - fw-hdl: the rv monitor drops `pending` when VALID falls (§8); without it
    `valid_retract` is invisible to the rules (checked: 12/13).
  - Lint: the rules are in the xtor lint top, zero findings. Verilator 5.055 limits hit:
    `w1()` in a typedef used as a class's type parameter fails to link (a localparam
    instead); `wire`, `release`, `join` are keywords (method names changed).

- Docs still owed from §7: `core-spec.md`, `derived-classes.md`,
  `writing-a-protocol-package.md` (due "P5, finished P7") and `brief-answers.md` (Q3 is
  answered in `rules.md`'s gaps; Q1 in design §3.3; Q2 and Q4 are open).

**Next action:** P9 (§11). The deadlock analysis is on hold: it is to be done statically,
not in simulation (decided 2026-11-12). P8 is done, committed and pushed (2026-11-12).

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
| D12 | Rule form in simulation (P7) | **Done:** a rule extends its protocol's rule base (`axi4_rule`: `fw_rule` + both channel listeners; requests at pre from a proxy, at post from pins), not `fw_rule #(type L)` (a rule needs two listener interfaces). `fw_any` is simulated by one instance per value seen (a probe twin discovers values; state copied through registered `fw_count`/`fw_flag`/`fw_value`); `retire()` drops discharged instances. Rules attach to an abstractor by path through the generated `axi4_observers` (`rules.md`) |
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
  core/fw_proto_axi4_defs_pkg.sv     its synthesizable part (parameters, encodings, burst helpers)
  checker/axi4_checker.sv            reference pin checker until A4 (on the defs package)
  cores/axi4_slice.sv                kept
  flow.yaml                          core -> weave -> behav filesets
  (old class/ types/ xtor/ cores/axi4_*_core.sv: deleted in P8)
tests/
  weave/        pytest: AXI4-specific golden checks on the woven package
  unit/         SVUnit suites (*_unit_test.sv; `_ns` while the old ones existed, until P8)
  env/          harnesses (tlm, xtor views), test params
  ip/           reference-IP wrapper tests (P6)
  formal/       existing + new
docs/
```

House SV style: one class per `.svh`, named after the class, in the package's directory and
`include`d by the package (`<pkg>.sv` keeps imports, typedefs and free functions). Applied
to the hand-written new-style packages (`fw_proto/src`, `src/core`, `src/behav`, `tests/ip`)
on 2026-11-11. Generated packages (`*_woven.sv`) are one file per package.

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
- [x] verilog-axi (`axi_ram`, `axi_crossbar`);
- [x] wb2axip (`demofull`). *Revisions in [reference-ips.md](reference-ips.md).*

PULP waits on brief Q2.

**Tests:**
- [x] `tests/ip/axi_ram`: an extern class plus one preset line. The emitted netlist equals a hand-written instantiation (text compare after normalization) and synthesizes in Yosys. It is driven through inserted abstractors from a class test running the `l2_mem_ns` scenarios. Stalls set by path reach the pins (checked by counting idle cycles).
- [x] `tests/ip/demofull`: upper-case preset, active-low reset, extra non-AXI pins tied or left open.
- [x] `tests/ip/axi_crossbar` (2×2): bit-slice mapping, ID widening, out-of-order across IDs accepted by the manager adapter.
- [x] Pin-map preset tests: each preset resolves every field of `P_DEF` and `P_WIDE` against the IP's module header, with no unmapped bit (fw-hdl's checks). *`tests/ip/presets` (`dfm run ip.presets`): `s_axi_`/`m_axi_` and upper case, on both roles, for both P; the emitted netlists linted against stub headers from an AMBA table (`presets.py`), not from the bundle. A missing pin, an extra pin and a wrong width each fail it (checked by hand).*

**Exit P6:** the three IP tests pass; their netlists match; Yosys synth passes.

### P7 Rules in simulation (brief A3)

**P7.1 Rule library** (`fw_proto/src`):
- [x] `fw_rule #(type L)` extends `L`'s `_base`; *as D12: `fw_rule` is the base; the protocol's rule base (`axi4_rule`) implements both channel listeners and maps pre/post to accepted events.*
- [x] `fw_count`, `fw_flag`, `fw_any #(T)` (simulation: evaluates every value seen, as a set of tracked keys). *Plus `fw_value #(T)` (bounded register; fw-hdl has an `fw_reg`), `fw_rule_node`/`fw_rule_set` (one instance per value seen, several variables, `retire()`), `fw_rv_hold #(T)`.*
- [x] Record vocabulary gaps for brief Q3. *12 in `rules.md`.*

**P7.2 AXI4 rules** (`src/rules/`): the brief §5 set, each a class on a channel-API listener.
- [x] correspondence; *`resp_match`*
- [x] same-ID order (read and write); *read in `r_burst`, write in `b_order` (keyed on ID and index); beyond lengths and ordering only data shows it (`rules.md` gap 5)*
- [x] R grouping; *`r_burst`*
- [x] W grouping; *`w_burst` (W ahead of AW allowed)*
- [x] B after AW and last W; *`b_order`*
- [x] burst legality; *`burst_legal` (with exclusive legality); plus `w_lanes` (narrow WSTRB)*
- [x] outstanding capacity; *`capacity`, declared at the attachment (crossbar master ports: `M_ISSUE`+1; the first declaration, `M_ISSUE`, was wrong and the rule caught it under the D11 mutant `blk_rd_done_first`, see rules.md)*
- [x] exclusive access (escape hatch). *`exclusive`, free form*

**P7.3 Signal-level rules** on `fw_rv_ch` from `_pre`/`_post` (design §4.1). *Done: `fw_rv_hold` per channel in `rv_hold`, pins only. fw-hdl's rv monitor now reports a new first after VALID drops, so a retraction is an event (§8).*

**P7.4 Attachment.** Rules attach by path to proxies (contract), producers (guarantee) and consumers (requirement). *Done: links and proxies directly (`add_listener`); abstractors by path through the generated `axi4_observers` (each handle registers its proxies when built, a test its listeners; whichever comes second joins them). The role only changes the report in simulation.*

**Tests:**
- [x] All rules are attached in every P4-P6 test and pass. *`xtor_ns` (monitor), `l1_ns`, `l2_ns`, `l2_mem_ns` (link, both views; and the direct path), `axi_ram`, `demofull`, `axi_crossbar` (every abstractor). Presets carry no traffic.*
- [x] Teeth: port `chk_teeth` to `rules_teeth_ns`. Each rule has a seeded-bug scenario (a misbehaving `_base`-derived model) that must fire, with the report naming the API event (method, ID, beat index). *`rules_teeth_ns`: 13 cases plus 3 event-level `rv_hold` cases, both views; each fires exactly its rule.*
- [x] The same seeded bugs run against `axi4_checker` give agreeing verdicts. *In `rules_teeth_ns` (xtor view, the link's checker) and `rules_pins_ns` (chk_teeth's 13 pin sequences, monitor + rules + checker): all agree but `valid_in_reset`, which no rule can state.*

**Exit P7:** rules pass on all IPs; every teeth case fires exactly its rule.

### P8 Retire the old package

Decisions (2026-11-12):
- `axi4_checker` stays as the reference checker until A4, ported to `fw_proto_axi4_defs_pkg`
  (which gains `axi4_addr_t` and the `axi4_{ax,wd,b,r}_bits` stream-width helpers). The
  second parameter struct (`CP`) goes everywhere; `src/types` is deleted.
- The xtor view of the L1 link keeps RTL in the middle: one `axi4_slice` per channel each
  way between the two pin segments, in place of the old `axi4_{mgr,sub}_core`.
- Formal: `axi4_fv`, `bmc`, `cover-b2b` (old cores) go; `prove` (slice), `checker_fv` and the
  `_ns` runs stay; `teeth` drops its three core mutants.

Steps: (a) port the checker and the L1 xtor link, re-run the suites; (b) delete the old
code, flows and formal pieces, fix `lint-rtl`/`smoke`; (c) rename the `_ns` suites;
(d) docs, `ci/run.sh` from a clean bootstrap.

- [x] (a) Checker on the defs package; L1 xtor link on `axi4_slice`. `tests` 21/22 (only the old `l2_basic` xtor), `ip`, `lint-rtl`, `fv`, `fv-prove`, `fv-cover`, `fv-teeth` pass.
- [x] Delete `src/class`, `src/types`, `src/xtor`, `src/cores/axi4_{mgr,sub}_core.sv` and the old test envs and suites, once every old suite has a passing `_ns` port (§6.2 map). (b) done: `git rm` of those, the old envs/harnesses, `types`/`chk_teeth`/`l1_basic`/`l2_basic`/`l2_mem` suites, old lint tops, `axi4_fv.sv`; the `CHK_P` shims went with them.
- [x] Rename the `_ns` suites. (c) done: the `_ns`/`-ns` suffix dropped from suites, files, modules, packages and macros (`types_ns`→`types`, … `rules_pins_ns`→`rules_pins`; `axi4_l1_ns_link`→`axi4_l1_link` etc.). Tasks: `lint-xtor-ns`→`lint-xtor` (`lint-waivers-xtor.yaml`, `axi4_lint_xtor{,_b2b}.sv`); formal `bmc-ns`→`bmc`, `cover-b2b-ns`→`cover-b2b`, `teeth-ns`→`teeth-gen` (`teeth` is the slice/checker mutants); `axi4_fv_ns.sv`→`axi4_fv.sv`, `fv_ns.sh`→`fv_b2b.sh`.
- [x] Decide `axi4_checker`'s fate (kept as reference until A4). On the defs package; linted by the new `tests/lint/axi4_lint_rtl.sv` (checker + slice under P_MIN/P_DEF/P_WIDE).
- [x] Update `ci/run.sh` and the flows. (b): `src/flow.yaml` keeps `checker`, `slice` (no `cores`); `src-rtl` = checker + slice; `lint` on `axi4_lint_rtl`; `smoke` = types_ns + l1_ns + rules_pins_ns; `fv` = bmc-ns, `fv-cover` = checker-cover + cover-b2b-ns; formal drops fv-sv2v/bmc/cover-b2b, `teeth.sh` its 3 core mutants. `ci/run.sh` needed no change then. (d): its bootstrap failed installing fw-hdl's dfm plugin from `packages/fw-hdl/python` (fw-hdl's `pyproject.toml` is now at its root, and `ivpm update` installs fw-hdl editable, entry point included), so that step is dropped from `ci/run.sh` and `README.md`.
- [x] (d) Docs: `README.md` and `docs/overview.md` rewritten for the new structure; stale names fixed in the design, P5, P6, rules and reference-IP notes.
- [x] Test: `ci/run.sh` passes from a clean bootstrap (`CI_SKIP_BOOTSTRAP` unset; `rundir/fw.proto.axi.*` removed first; the bootstrap reuses every package in `packages/`): lint-rtl, tests 14/14, fv-cover, fv-prove, fv-teeth. Log `rundir/p8d/ci.log`. Before committing: `tests/lint/axi4_lint_rtl.sv` and `axi4_lint_rtl_p.sv` are untracked and must be added, or `lint-rtl` fails on a clean checkout.

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

The old suites were deleted in P8, and the `_ns` suffix dropped (P8(c)); the last column is
the name today.

| Old | New (P2-P7) | Final (P8) | Phase |
|---|---|---|---|
| `types_unit_test` | `types_ns` | `types` | P2 |
| `l1_basic` | `l1_ns` | `l1` | P4 |
| `l2_basic` (incl. backpressure) | `l2_ns` | `l2` | P5 |
| `l2_mem` | `l2_mem_ns` | `l2_mem` | P5 |
| `chk_teeth` | `rules_teeth_ns` (+ checker cross-check), `rules_pins_ns` | `rules_teeth`, `rules_pins` | P7 |
| formal `axi4_fv` | re-pointed at generated wrappers (`axi4_fv_ns`) | `axi4_fv` (`fv_b2b.sh`; old one deleted) | P4, P8 |
| formal `axi4_slice_fv`, `axi4_checker_fv`, `teeth.sh` | unchanged | unchanged (`teeth.sh` lost its 3 core mutants; `teeth-gen` for the generated cores) | P8 |
| lint tops | extended with generated wrappers (`lint-xtor-ns`) | `axi4_lint_rtl` (`lint`), `axi4_lint_xtor` (`lint-xtor`) | P4, P8 |

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
| sv-weave | `sv_weave_init.sv` declares `sv_weave_init_pkg`, so Verilator `-Wall` reports DECLFILENAME on it; waived by path in `lint-waivers-xtor.yaml` | to raise |
| Verilator 5.055 | Bug found: internal fault (V3Param "Expected module parameterization") on a virtual interface whose type parameter is a class-scoped type of a parameter (`virtual fw_rv_target_xtor_if #(ty #(P)::b_t)`). Worked around in the generated code: a local `typedef ty #(P)::b_t b_t;` first | to raise (Verilator) |
| sv-weave | Gap found: two `svweave.Weave` tasks in one image both define `sv_weave_init_pkg`. Worked around by weaving the test sources in one run (`tests/weave/sv-weave.yaml`) | to raise |
| fw-hdl | rv transactor run-time `depth`/`max_gap`; monitor first-valid event (`up_first`/`up_xfer`, `get_ev`); `tests/rv_proto/rv_knobs_tb.sv`, `test_runtime_knobs` (`src/std/rv/fw_rv_{initiator,target,monitor}_xtor_if.sv`, `fw_rv_monitor_xtor{,_core}.sv`). Lint: the new state (`gap_left`, `drawn`) has no declaration initializer, so `-Wall` adds nothing to fw-hdl's existing PROCASSINIT warnings | done, uncommitted, branch `fw-proto-axi-new` |
| fw-proto-axi (this) | `ivpm.yaml`: yosys (sby) declared directly (was only via fw-hdl) | done, uncommitted |
| fw-proto-axi (this) | `ci/run.sh`: the separate `uv pip install -e packages/fw-hdl/python` step dropped; fw-hdl's `pyproject.toml` moved to its root and `ivpm update` now installs it (with the dfm plugin) (P8(d)) | done, uncommitted |
| fw-hdl | Found at HEAD `6f45fe0`, not caused here: 42 regmap/regblock/mmio/structural_top tests fail (register sources omit the now-required `parent` argument; `dma_channel_regs` has no registers). `test_knobs::test_dfm_resolve` assumes a standalone checkout (`packages/python/bin/dfm`) | to raise |
| Verilator 5.055 | Bug found: internal fault (endless recursion after V3Class; segfault or OOM) on a class `localparam` from `$bits(type param)` used in nested loop bounds and part-select indices, with the indexed queue filled by an interface-class call. Reduced repro with script and notes: `repro/verilator-class-localparam/`. Worked around in `axi4_to_mem` (a run-time member) | to raise / fix (repro saved) |
| fw-hdl | `fw_extern` `pin`/`prefix` (from fw-hdl-sv-weave) + bit-slice form | planned (P6) |
| fw-hdl | rv monitor (`src/std/rv/fw_rv_monitor_xtor_core.sv`): `pending` cleared when VALID drops without a handshake, so the next VALID is a new first and a retraction shows as two pres without a post (needed by P7's `rv_hold`; `rules_pins_ns` `valid_retract` fails without it). `tests/rv_proto` 9/9 (with the `packages -> ..` symlink) | done, uncommitted, branch `fw-proto-axi-new` |
| Verilator 5.055 | Limit found: a class typedef whose width calls a package function (`logic [w1(P.ID_W)-1:0]`), used as another class's type parameter (`fw_any #(id_t)`), gives an internal error (V3Width "Unlinked"). Worked around with a localparam width in `axi4_rule` | to raise (Verilator) |

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

## 11. P9: docs, Jinja assessment, upstream fixes (started 2026-11-12)

Decisions (2026-11-12):
- Deadlock analysis of the two-way burst API: held; to be done statically, not by run-time
  tracking. `sub_b_inline` stays the known teeth gap until then.
- The sv-weave gaps in §8 are fixed by us in `packages/sv-weave` and upstreamed by us.
- The fw-hdl test failures at HEAD (§8) are resolved here in `packages/fw-hdl` and
  upstreamed by us.
- Weaver SV text into Jinja templates: assess feasibility first.

| Task | Deliverable | Status |
|---|---|---|
| Owed docs (§7) | `docs/core-spec.md`, `docs/derived-classes.md`, `docs/writing-a-protocol-package.md`, `docs/brief-answers.md` | written, uncommitted |
| Jinja feasibility | `docs/jinja-feasibility.md`, pilot `docs/jinja-pilot.patch` (not applied) | done: go with conditions, ~4 days |
| sv-weave fix plan | `docs/upstream-sv-weave.md` | plan done; baseline 227 pass / 3 xfail |
| fw-hdl test-failure plan | `docs/upstream-fw-hdl.md` | plan done; 64 failures in 8 groups (G1-G8) |

Notes (2026-11-12):
- Brief found: `axi4-package-brief.md` (repo root), §10 Q1-Q4. Q1, Q3 settled; Q2 partly
  (PULP struct pins, taxi interface ports open); Q4 open until A4 (`brief-answers.md`).
- Jinja: pilot on `xtors.py` is byte-identical (17/17 pytest, 12 goldens). Conditions and
  order in `jinja-feasibility.md`: missing goldens first; sv-weave owns `render()`.
- sv-weave: branch has no commits, on `v0.1.0` = upstream head. PRs A-D (existing work), then
  gap 2 (split init file), gap 1 (Weave task up-to-date check + source hash; the stale result
  is mostly dfm's check), gap 3 (`init: false`, `svweave.Init`). Open: API version (0.1.x vs
  0.2 and the plugin range), which forge takes the PRs.
- fw-hdl: upstream still `6f45fe0`; our branch adds no failures. CI never runs
  `pytest tests/python`. Fixes: E1 merge dv-flow-libsynth `wpk/results-ir`; X1 tool lookup;
  X2 register front end + mmio sources; X3 XLS test fixes/markers (AES Verilator ~50 GB);
  X4 CI runs pytest; E2 zuspec-dataclasses arg types; features F1-F3 independent.
- Design-doc drift found while writing `derived-classes.md` (to fix in `design-new-style.md`):
  `_base` reports with `$error` not `fw_error`; §3.2/§4.1 still show one `ax_t`; hand-written
  `axi4_{ax,wd,b,r}_bits` duplicate the generated `axi4_<x>_t_bits(P)` and both are used;
  burst sockets are hand-written; sockets are classes, the mirror is `axi4_sub_socket`;
  `connect()`/sockets/abs/observers only with `xtor: true`; `fw_reset`, defaults,
  `fw_listener`, `fw_default` not in the core header comment; `mon` reserved role;
  presets are not derived (§4.6); optional fields keep `w1` pins on the transactors.

Decided (2026-11-12): sv-weave goes to 0.2.0 (plugin range defaults move with it). No PRs:
the sv-weave and fw-hdl work is committed on each `fw-proto-axi-new` branch, merged to that
repo's `main` and pushed (the PR plans in the upstream docs become the commit order).

Next: implement and merge the sv-weave plan, then the fw-hdl plan; re-run `ci/run.sh` here.
