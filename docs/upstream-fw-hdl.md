# fw-hdl: test failures and upstreaming plan

Status 2026-11-12: **done** except E1/E2/E3. F1-F3 and X1-X4 merged to fw-hdl `main`
(`4b9a66a`, `--no-ff`) and pushed; one extra commit `eb37ce4` (formal: svunit found via
`$SVUNIT_INSTALL` and the ivpm workspace, same cause as G3 in library code). Results:
`tests/python` 291 pass / 2 skip, xls-conformance 16 fail (G6 only) / 483 pass, rv_proto 9/9.
The plan below is kept as written.
Covers the fw-hdl rows of [plan-new-style.md](plan-new-style.md) §8: the feature work on the
branch, and the pre-existing test failures (§11: we fix and upstream them).

Runs were made in scratch worktrees (upstream `main`, and our branch plus its uncommitted
diff), with `packages/python` and Verilator 5.055. Logs are in the session scratchpad, not
kept.

## 1. State of packages/fw-hdl

| | |
|---|---|
| origin | Forgejo `featherweight-hdl/fw-hdl` (the tailnet host; see §4 on keeping it out of tracked files) |
| GitHub | `https://github.com/featherweight-hdl/fw-hdl.git` (what `ivpm.yaml` names); `main` = `6f45fe0`, same as Forgejo |
| branch | `fw-proto-axi-new` |
| base | `6f45fe0` "CI: install fw-hdl into the workspace venv; add dv-flow-libproject" (2026-11-08) |
| behind upstream | 0. `git fetch` (2026-11-12): `origin/main` = `6f45fe0`. The other remote branches (`xls-backend`, `wpk/*`, `ci/ivpm-setup`) are all contained in `main` |
| upstream fixes | none: upstream has not moved, so it fixes nothing |
| commits on branch | `f82a636` rv kit: valid low in reset; `depth`/`max_gap` knobs; monitor first-valid event (10 files, +341/-66) |
| | `b9a32e0` `fw_extern`: struct-port pin maps `pin`, `prefix`, `upper()`, `slot()` (`src/fw_extern.svh`, +83) |
| uncommitted | `src/std/rv/fw_rv_monitor_xtor_core.sv`: `pending` cleared when VALID drops without a handshake (+7/-1) |

GitHub CI is red at `6f45fe0`: run 42508800409 ran the regression for 1 h 34 min, then "the
hosted runner lost communication with the server" (starved of memory). G8 below is the
likely cause. The four runs before it failed within 2 minutes on the install step, which
`6f45fe0` fixed.

## 2. What runs where

Two suites, and CI runs only one of them:

| Suite | How | CI |
|---|---|---|
| `tests/python` (pytest `testpaths`) | `pytest tests/python` | **not run** by either workflow. This is how 34 failures went unnoticed since July |
| `dfm run tests` (root task in `flow.yaml`) | the sim/formal/SVUnit tests plus `xls.xls-conformance`, which runs `pytest tests/xls packages/zuspec-be-xls/tests` | GitHub workflow only. The Forgejo workflow checks identifiers and packaging, no tests |

Both assume a standalone checkout: tool paths are `REPO/packages/...`. Inside this packet
fw-hdl is itself `packages/fw-hdl`, so there is no `packages/fw-hdl/packages`. Then tests
that look for tools there are **skipped silently**, and `xls-conformance` fails with exit
127. To run as CI does, the worktrees had a `packages -> <packet>/packages` symlink (the
same trick §8 uses for `tests/rv_proto`).

## 3. Results at 6f45fe0

| Suite | Without symlink (as in the packet) | With symlink (as CI) |
|---|---|---|
| `pytest tests/python` | 34 failed, 239 passed, 18 skipped | **42 failed**, 240 passed, 9 skipped (the 8 Verilator system tests now run and fail; `test_dfm_resolve` runs and passes) |
| `dfm run tests` | `xls-conformance` exit 127, `tests` blocked | 45 tasks pass, including `order.selftest` (11/11) and `stdlib.unit` (46/46); **`xls-conformance` fails: 22 of 501** (33 min) |

Our branch (with the uncommitted diff, symlinked): the same results. `tests/python` has the
same 34 failures without the symlink. `dfm run tests`: 70 tasks done, `rv_proto` passes,
only `xls-conformance` fails, with the same 22 tests. Our changes add no failures.

So "order" in §8 was not a real failure: it was blocked by the exit-127 task. The 42 failing
`tests/python` tests plus the 22 XLS tests make **64 failing tests, in 8 groups**.

## 4. Failures by root cause

Fix the test when the library is right and the test is stale or brittle; fix the library when
it is wrong. "Ext" means the fix belongs in another repo.

| # | Tests | Count | Cause (file:line) | Fix | Where | Effort |
|---|---|---|---|---|---|---|
| G1 | `unit/test_regmap` (8), `test_regblock_emit` (6), `test_regblock_usage` (3), `test_regblock_ports::…dma_channel`, `test_regblock_provider`, `test_reg_consumer`; system `test_regblock_sim`, `test_regblock_equiv` | 20 + 2 | The register front end is stale. `be03c6f` (2026-07-01) changed the SV API so a register self-registers through a required `parent` (`src/fw_reg.svh:17`, `src/fw_reg_base.svh:74,97`: `new(name, parent, offset, reset, sw_wmask, hw_wmask, rclr_mask, access, pulse_mask)` then `parent.add(this, offset)`). `python/fw/hdl/fe/reg_mapper.py` still reads the old form: formal indices `reset=1, sw=2, hw=3, rclr=4` (`:27-28`), and only an explicit `add(r)` puts a register in the block (`:149-186`). `tests/reg_dma/dma_regmap.svh` uses the new form, so `dma_channel_regs` comes out empty: `python/fw/hdl/emit/regblock.py:48,122` "has no registers" | **Library.** In `_scan_ctor_stmt`, take `r = new(name, this, ...)` as an add at the `offset` formal (index 2; -1 = cursor), in source order. Shift the formal indices to reset 3, sw 4, hw 5, rclr 6. Keep `add_block(sub, off)` as it is. Keep `add(r)` too, for a register made with another parent. Read `access` (7) and `pulse_mask` (8) from `a4eada1` (2026-10-17) into `Register`. If the emitter cannot honour them yet, record them as `unresolved` (the module's stated rule: never silently dropped) | fw-hdl `python/fw/hdl/fe/reg_mapper.py`, `regmap.py` | 1 day |
| G2 | `unit/test_mmio` (4), `test_mmio_gated` (2), `test_mmio_lower` (2), `test_mmio_multi` (2), `test_structural_top` (2), `test_cli_synth_mmio`, `test_regblock_ports::…emitted_header`; system `test_mmio_sim` (2), `test_mmio_gated_sim` (2), `test_mmio_multi_sim` (2) | 14 + 6 | The test sources were not ported in `be03c6f`: `tests/mmio/mmio_regs.svh:11-15`, `tests/mmio_gated/gated_regs.svh:12-15`, `tests/mmio_multi/multi_regs.svh:13-20` call `new("ctrl", .sw_wmask(...))` without `parent` and then `add(ctrl)`. slang: "argument 'parent' is missing a value". The `KeyError: 'mmio_fsm'` / `'mmio_regs'` failures are the same elaboration error, reported later | **Test.** Pass `this`; drop the `add()` calls (keeping them would add each register twice, which is `$fatal` at run time). Tried in scratch: the sources then elaborate, and the tests fail on G1 ("update() on an unresolved register"). So G2 lands with G1 | fw-hdl `tests/mmio*` | 0.5 h |
| G3 | silent skips: `unit/test_knobs::test_dfm_resolve`, the 8 system tests above, the `tests/xls` dfm tests; hard failure: `xls.xls-conformance` exit 127 | (hides 9; blocks 1 task) | Tools are found only at `REPO/packages/...`: `tests/python/unit/test_knobs.py:174`, `tests/python/system/*.py` (`VERILATOR = REPO/"packages"/"verilator"/…`, e.g. `test_mmio_sim.py:22`; `test_regblock_formal.py:20` for sby), `tests/xls/xls_harness.py:43`, `DFM = …` in 9 `tests/xls/test_*.py` (e.g. `test_dfm_markers.py:13`, `test_compose.py:264`), `tests/xls/flow.yaml:17` (`packages/python/bin/pytest`) | **Test.** Add one helper (in `tests/python/conftest.py` and `tests/xls/conftest.py`) that resolves a tool by: env override (`FW_HDL_DFM`, `VERILATOR`, …), then `REPO/packages/...`, then `shutil.which`, then the bin dir of `sys.executable` (dfm, pytest). `test_blinky_sim.py:17` already uses `shutil.which`. `flow.yaml`: run `python -m pytest` (the env's python), not `packages/python/bin/pytest`. Also run `zuspec-be-xls/tests` from where that package is installed, not from `packages/` | fw-hdl tests | 3 h |
| G4 | `xls/test_dfm_markers::test_lowering_error_is_a_located_marker[ir,part]` | 2 | Brittle text check (`tests/xls/test_dfm_markers.py:44`): the marker *is* located, but dfm's rich console wraps the long path at 80 columns (`twice_pkg.` / `sv:18:67`). Passes with `COLUMNS=400` | **Test.** Read the marker's `loc` from `rundir/out/latest/results.json` (or the task's `exec_data.json`) instead of the console. Setting `COLUMNS` would only hide the problem | fw-hdl tests | 0.5 h |
| G5 | `xls/test_compose::test_t1_through_dv_flow[chain-rtl, chain-rtl-recipe]` | 2 | Stale expectation (`tests/xls/test_compose.py:281`): Integrate's output now always lists the channel RTL `RTL_LIB` (`python/fw/hdl/dfm_tasks.py:30`: `fw_rv_fifo`, `fw_valid_check`, `fw_xls_fifo_wrapper`, `fw_sram_fifo`, two RAM models; from `01e1d2d`, `3203e28`, `f0300e8`). The test still expects `fw_rv_fifo` + the 4 design files | **Test.** Expect `[p.name for p in RTL_LIB] + [design files]`, importing `RTL_LIB`, so the test follows the list | fw-hdl tests | 0.5 h |
| G6 | `xls/test_engine_path` (4, ImportError `CODEGEN_DEFAULTS`), `test_block_codegen` (3), `test_latency_contract` (2), `test_latency_report` (2), `test_resp_tracker` (2), `test_multi_proc` (2, `xls_fifo_wrapper` missing), `test_sp_mem` | 16 | **Dependency skew (environment).** The XLS engine adapter `zuspec-be-xls/src/zuspec/be/xls/engine.py:76` and fw-hdl's knob plumbing (`xlsCodegenOptions`, `python/fw/hdl/dfm_tasks.py:102,343`) need three dv-flow-libsynth commits that are only on its unmerged branch `wpk/results-ir` (`0a300a1` Codegen defaults/argv for the engine adapter, `822e27e` per-module options `xlsCodegenOptions`, `aaceb9a` `--io_constraints` join). Without them the per-block stage counts are ignored (e.g. latency 2 not 4, stages `[0,0]` not `[2,2]`). Checked: all 16 pass with `PYTHONPATH=<libsynth wpk/results-ir>/src` | **Ext: dv-flow-libsynth.** Merge `wpk/results-ir` to libsynth `main` (it is 3 ahead, 0 behind). Nothing to change in fw-hdl. It is not an adapter bug: the adapter is right, its dependency is not released | dv-flow-libsynth | 0.5 h + its CI |
| G7 | `xls/test_canary_gcd::test_bcd_interface_schedule_and_validity` | 1 | **Front end, not XLS.** The zuspec-dataclasses half of the canary builds Zuspec IR whose `Arg.datatype` is `None` (`zuspec-dataclasses/src/zuspec/dataclasses/data_model_factory.py:611,663`: `Arg(arg=…, annotation=…)`, the type is never resolved). The XLS engine adapter rightly rejects it (`zuspec-be-xls/src/zuspec/be/xls/lower_fn.py:813`, "argument 'a' has no type"). The SV half (fw-hdl front end) sets `datatype` and is fine. `Arg.datatype` was added to zuspec-ir-core in `1cf4740` (2026-10-03); the zdc factory (last commit `abd40d4`, 2026-09-01) predates it | **Ext: zuspec-dataclasses.** Resolve the annotation to an IR datatype in the factory (both sites). Do not make the XLS adapter guess types from annotations: typing is the front end's job. In fw-hdl, mark the test `xfail(strict=True, reason=…)` until the zdc fix is released | zuspec-dataclasses; fw-hdl xfail | 0.5 day |
| G8 | `xls/test_corpus::test_c4_aes128_ctr` | 1 | **Tool (environment).** The class model builds. Verilator 5.055 is then killed (signal 9) on the XLS-generated RTL (`xls_s1/xls_rtl.sv`, 60 KB): peak RSS **~50 GB** on this 60 GB host. Run alone, unloaded, it still fails. Builds are run from `tests/xls/xls_harness.py:66` (`--binary --timing -j 0`). A 16 GB GitHub runner cannot survive this: most likely what killed CI run 42508800409. Not checkable on older Verilator: 5.042 cannot parse fw-hdl (`src/dbg/fw_dbg_ctx.svh:14`) | **Test now, tool later.** Mark the test `bigmem` (or skip it below a memory threshold) so CI stays up. Reduce the RTL to a Verilator repro (as in `repro/verilator-class-localparam/`) and raise it. Try `-O0` / `--x-assign fast` / no `--timing` for the RTL-only build. Not an engine-adapter fix | fw-hdl tests; Verilator issue | 2 h + repro |

Counts: G1 22, G2 20, G4 2, G5 2, G6 16, G7 1, G8 1 = **64** failing. G3 hides the
system tests and causes the exit 127.

XLS failures, by the architecture rule (XLS is one engine behind the engine interface;
fw-hdl must not become XLS-centric):

- No failure is an XLS engine-adapter bug. G6 is an unreleased dependency of the adapter
  (environment). G8 is a tool limit. G4 and G5 are stale or brittle tests. G7 is a front-end
  gap in the Zuspec IR, and the adapter is right to reject it.
- None of the proposed fixes emits XLS IR or DSLX, inside or outside the adapter. G7 is
  deliberately fixed in the Zuspec front end, not by making the adapter more permissive.
- Existing debt, seen while tracing these; not touched by this plan: `python/fw/hdl/lib/xls_ir.py`
  is hand-written XLS IR in fw-hdl, outside the adapter. `python/fw/hdl/xls_flow.py` and
  `dfm_tasks.py` produce the XLS-specific `xlsCodegenOptions` in fw-hdl. Both are paths to
  migrate behind the engine interface (separate work).

## 5. Contribution conventions (fw-hdl)

- Forgejo `origin` is where work lands. GitHub is the published copy, and its Actions run the
  regression. History is mostly direct commits on `main`. Larger work goes on a `wpk/<name>`
  branch merged with a merge commit ("Merge wpk/cosynth: …"). One GitHub PR so far (#1).
- Forgejo CI (`.forgejo/workflows/ci.yml`): fails on any internal identifier in a tracked file
  (the tailnet host name, `*.ts.net`, CGNAT addresses). Check every commit for them, including
  docs and test fixtures. It also statically checks `pyproject.toml`.
- GitHub CI (`.github/workflows/ci.yml`): `ivpm-setup` with dep-set `default-dev`, editable
  install, then `direnv exec . dfm run -j 64 tests` with `DFM_CORES=1`. New suites must be
  added under the root `tests` task (`flow.yaml:12`) or they are not gated. Note that
  `tests/formal` is included but not in the root task.
- Commits: subject "area: what" in plain words (e.g. "rv kit: hold up_valid low in reset;
  per-channel depth/max_gap knobs"); a body saying why; the `Co-Authored-By` trailer.
- Pushing upstream sends it to CI and notifies the team. The user does all pushes and PRs
  (global rule). This plan only names the branches.

## 6. PR plan

Our feature work and the failure fixes are separate PRs. Fix PRs branch from `origin/main`,
not from `fw-proto-axi-new`. No file is shared between the two sets, so they can land in any
order. In the fix set, the order below keeps each PR green on what it touches.

| # | Branch | Content | Depends on | Tests that turn green |
|---|---|---|---|---|
| F1 | `wpk/rv-kit-knobs` | `f82a636`: rv cores gate valid with reset (AXI A3.1.2); initiator/target `depth`/`max_gap`; monitor first-valid event (`up_first`/`up_xfer`, `get_ev`); `rv_knobs_tb`; formal hold properties exempt reset | — | `tests/rv_proto` (9/9) |
| F2 | same branch, 2nd commit | the uncommitted monitor change: `pending` cleared on a VALID retraction, so a retraction shows as two pres without a post | F1 (same file) | `tests/rv_proto` |
| F3 | `wpk/extern-pin-maps` | `b9a32e0`: `fw_extern_map` `pin`, `prefix`, `upper()`, `slot()` | — | none in fw-hdl yet; consider a small fw-hdl test (it is data-only, exercised today only by fw-proto-axi) |
| X1 | `fix/test-tool-paths` | G3: tool lookup helper; `tests/xls/flow.yaml` runs `python -m pytest` | — | nothing turns green, but the 8 system tests stop being skipped (and fail until X2) in a packet checkout. CI is unchanged (standalone) |
| X2 | `fix/regmap-self-registering` | G1 library + G2 test sources, one PR (G2 cannot pass without G1) | — (X1 lets it be checked in a packet) | 42 `tests/python` |
| X3 | `fix/xls-tests` | G4 results-json marker check; G5 expectation from `RTL_LIB`; G7 `xfail(strict)` with reason; G8 `bigmem` marker (excluded from the CI run) | — | 4 pass, 2 marked |
| E1 | dv-flow-libsynth: merge `wpk/results-ir` | G6 | — | 16 xls |
| E2 | zuspec-dataclasses: `Arg.datatype` from annotations | G7 | — | then drop the xfail in a follow-up fw-hdl commit |
| E3 | Verilator issue (repro) | G8 | — | then drop the marker |
| X4 | `ci/gate-python-tests` | add a dfm task that runs `pytest tests/python` (and `-m "not bigmem"` for xls) under the root `tests` task, so CI gates the suite that rotted | X2, X3, E1 | — |

Order to land: E1, X1, X2, X3, X4 (fix set); F1+F2 and F3 whenever. With E1, X2 and X3 in,
`dfm run tests` and `pytest tests/python` should both be green, with 2 tests marked.

Before each PR: run both suites from a standalone clone (as CI does) and from the packet. Log
to files. Check for internal identifiers.
