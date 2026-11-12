# sv-weave: upstreaming plan

Status 2026-11-12: **implemented.** The PR list in §4 became the commit order on
`fw-proto-axi-new` (A, B, C, D, gap 2, gap 1, gap 3, then `sv-weave 0.2.0`), merged
fast-forward into sv-weave `main`. API 0.2, default plugin range `">=0.2,<0.3"`. Tag
`v0.2.0` not yet made (it releases). Choices made in implementation: the Weave task's
`init` param is a bool ANDed with the config's `init` (dv-flow has no tri-state param);
`svweave.Init` errors on an upstream Weave that wrote its own init; a 0.1
`sv_weave_init.sv` in the sources is also detected.
Covers the sv-weave rows of [plan-new-style.md](plan-new-style.md) §8: the feature work
already on the branch, and the three gaps to fix (§11: we fix and upstream them).

## 1. State of packages/sv-weave

| | |
|---|---|
| origin | `ssh://git@a9550.perch-char.ts.net:222/sv-weave/sv-weave.git` (Forgejo) |
| GitHub | `https://github.com/sv-weave/sv-weave.git` (what `ivpm.yaml` names); same `main` |
| branch | `fw-proto-axi-new`, no commits of its own: points at `7391a50` |
| base | `7391a50` "sv-weave 0.1.0: generator, weavers, example bindings, CI and docs" (2026-11-08), tag `v0.1.0` |
| behind upstream | 0. `git fetch` (2026-11-12): `origin/main` = `7391a50`; GitHub `main` = `7391a50` |
| conflicts | none possible yet: upstream has not moved since the base |
| work | uncommitted: 13 modified files, 2 new (`frontend/decl.py`, `tests/unit/test_decl.py`); +220/-15 plus 345 new lines |

Baseline, 2026-11-12, with the uncommitted work, `packages/python` and Verilator 5.055:
`pytest -q` **227 passed, 3 xfailed, 3 deselected** (77 s). The 3 xfail are xezim
(`test_registration_xezim`, strict, documented in `docs/design/notes/registration-trigger.md`);
the 3 deselected are `perf` (excluded by `addopts`). Log: `rundir/logs/sv-weave-pytest.log`.

### 1.1 The uncommitted diff as logical commits

Several files carry hunks of more than one commit (`run.py`, `frontend/model.py`,
`tests/unit/test_design.py`, `docs/authoring/weavers.rst`). `git add -p` is interactive;
split with `git diff <file> > x.patch`, edit, `git apply --cached x.patch`.

| # | Commit | Files (hunks) | Tests |
|---|---|---|---|
| A | **SvDecl: a class's declaration as written** (S1-S3, plus the `_txt` fix: text rebuilt from tokens so a leading comment does not hide `interface` or leak into headers and types) | `frontend/decl.py` (new); `frontend/model.py`: `decl` properties on `SvGenericClass`/`SvClass`, `_decl_of` | `tests/unit/test_decl.py` (4, incl. `test_comments_are_not_text`) |
| B | **`sources.top`: the modules slang elaborates** (S6) | `config.py` (`SourcesCfg.top`, `source_spec`), `filelist.py` (`SourceSpec.tops`, `extend`), `frontend/loader.py` (`CompilationOptions.topModules`, `Compilation(bag)`), `verify.py` (`Compilation(loaded.bag)`), `run.py` (`tops` in `_input_hash`) | `test_loader.py`: `test_implicit_top_elaborates_every_module`, `test_tops_limit_elaboration`, `test_config_top` |
| C | **A woven package repeats its user package's wildcard imports** | `frontend/model.py` (`SvPackage.imports`, `WildcardImport`), `run.py` (`new_pkg`), `weavers.rst` first hunk, golden `two_packages/expect/ext_pkg_woven.sv` | `test_design.py::test_woven_package_repeats_user_imports`, golden |
| D | **`DesignCtx.add_file`: weaver-generated whole files** (S5) | `weave/design.py`, `bus.py` (`files`), `render.py` (`render_file`), `run.py` (clash check, compile order), `weavers.rst` second hunk | `test_design.py`: `test_add_file_module_compiles_last`, `test_add_file_error_maps_to_weaver`, `test_add_file_errors` (6 params) |

A-D touch disjoint behaviour and each passes on its own (B's hash line and D's run.py
hunks do not overlap). Before opening each, fill these holes found in review:

- A: `SvDecl` is undocumented and fw_proto imports it from `sv_weave.frontend.decl` (31
  uses). Document `cls.decl` in `docs/authoring/weavers.rst`; export the `SvDecl*` classes
  from `sv_weave.api` so plugins do not import internals.
- B: document `top` in `docs/user/config.rst:46`. For parity add `--top` to the CLI
  (`cli.py` has `-f -I -D` only) and a `top` param to `svweave.Weave` (`dfm/flow.dv`).
- C: `docs/authoring/bindings.rst:52` ("besides the user package") now understates the
  imports. Note in the changelog: woven packages import more, so a name two of those
  packages export now needs qualifying in woven code only if woven code uses it.
- All: `API_VERSION` stays `(0, 1)`? `add_file`, `decl` and `top` are additions ("minor
  bumps add"), but the default plugin range is `">=0.1,<0.2"` (`plugin.py:32,68`), so a bump
  to 0.2 rejects every plugin that keeps the default, fw_proto's included. Decide at release:
  bump `API_VERSION` and the defaults together, or stay at 0.1 for 0.1.x.

## 2. The three gaps

### Gap 1: an edited weaver is reported up to date under dfm

Root cause, two parts:

- dfm decides. `svweave.Weave` (`src/sv_weave/dfm/flow.dv:22-53`) declares no `uptodate:`,
  so dfm's default check runs (`packages/dv-flow-mgr/src/dv_flow/mgr/task_node_leaf.py:602-700`):
  params, implementation (`run:` body), the upstream FileSets' content and the outputs
  present. The weaver's Python source is none of these, nor is the content of the
  `sv-weave.yaml` the `config` param points at. The task is skipped; `Weave()` never runs.
- sv-weave's own hash could not tell anyway. `_input_hash` (`src/sv_weave/run.py:80-93`)
  takes `plugins` = `{name: cls.version}` (`run.py:150,154`), and `version` defaults to
  `"0"` (`plugin.py:33,69`; fw_proto's are a fixed `"0.1"`). sv-weave's own code enters
  only as `__version__` (`run.py:91`), so an editable sv-weave is stale too. Inside a run
  the effect is small (the verify cache, `verify.py:134-138`, also keys on `output_hash`),
  but it makes the stored `input_hash` useless as an up-to-date key.

Fix:

1. Fingerprint plugin source. New `plugin.source_fingerprint(cls)`: sha256 over the bytes
   of every `.py` file under the class's top-level package directory (or its one module
   file), sorted by relative path. A plugin may override with a classmethod
   `fingerprint()` (for code outside its package, or data files). `run.py` records
   `{name: {"version", "source"}}` and hashes that; the same for sv-weave itself (its
   package directory) in place of `__version__`. Hash files from disk, not module
   objects, so an import cached in the dfm process does not matter.
2. Factor `run.py:142-170` (bindings, weavers, source spec, runtime files) into
   `prepare(cfg, spec) -> Prepared` and `input_hash(prepared, texts)`, used by `run()` and
   by step 3. No slang work in either.
3. `uptodate: sv_weave.dfm.tasks.WeaveUpToDate` on `svweave.Weave`. It loads the config as
   `Weave()` does (factor the shared part out of `tasks.py:72-93`), builds the spec from
   `ctxt.inputs` (`_upstream_spec`), and returns `ctxt.memento["input_hash"] ==
   input_hash(...)`. dfm calls it only after its own checks pass, and the memento already
   stores `input_hash` (`tasks.py:112`). Any exception returns False (dfm already treats
   it so).

Tests:

- `tests/unit/test_plugin.py`: `test_fingerprint_follows_source`: a weaver package in
  `tmp_path` (module + helper module); fingerprint changes when the helper's body changes
  with `version` unchanged, and not when only mtime changes.
- `tests/unit/test_weave.py` (or a new `test_run.py`): `run()` twice with an edited weaver:
  `input_hash` differs.
- `tests/sim/test_factory.py`, beside `test_incremental`: `test_incremental_weaver_edit`:
  Weave, edit the case's weaver (copied to `tmp_path`), Weave again: the task runs and
  `changed` is True; and `test_incremental_config_edit` for `sv-weave.yaml`. Check that
  pytest-dfm's `runTask` goes through dfm's up-to-date path (if it does not, drive `dfm
  run` in a subprocess for these two).

Here: nothing to change. Remove the "gap" note from the dependency log when it lands;
`ci/run.sh` needs no forced re-weave.

### Gap 2: `sv_weave_init.sv` fails Verilator DECLFILENAME

Root cause: `render.py:183` names the file `sv_weave_init.sv`; `render_init`
(`render.py:186-221`) puts `package sv_weave_init_pkg` and then `module sv_weave_init_m` in
it. Verilator reports the first declaration whose name is not the file's base name.
Checked with 5.055: renaming the file to `sv_weave_init_pkg.sv` only moves the warning to
the module. Split into two files and both are clean.

Also found: with `sv_weave_init_m` elaborated, `-Wall` reports UNUSEDSIGNAL on `m_done`
(`render.py:217`). Not hit here because our lint does not elaborate it.

Fix:

- Two files: `sv_weave_init_pkg.sv` (the package) and `sv_weave_init_m.sv` (the module),
  in that order, last in the compile order as now. `INIT_FILE` becomes a pair;
  `run.py:172` (skip the stub when the user supplies the init) checks either name;
  `run.py:260,277-279` and the add_file clash set use both.
- Wrap `m_done` in `/* verilator lint_off UNUSEDSIGNAL */ ... lint_on`.
- Output names change: say so in the changelog. Update `docs/user/dvflow.rst:29`,
  `docs/design/initial-design.md:98,517`.

Tests: update the expected names in `tests/sim/test_factory.py:50`,
`tests/unit/test_design.py:88,105,135,157`, `tests/unit/test_weave.py:238`,
`tests/unit/test_cli_gen.py:29`. Add `tests/sim/test_lint.py::test_init_lint_clean`
(marker `sim`): Verilator `--lint-only -Wall` over the two init files with
`sv_weave_init_m` as top, no findings.

Here, after the bump: delete the DECLFILENAME waiver (`lint-waivers-xtor.yaml:7-9`);
`fw_proto/python/tests/test_weave.py:189` filters `sv_weave_init.sv` by name, change it to
the two new names; `dfm run lint-rtl` stays at zero findings.

### Gap 3: two `svweave.Weave` tasks in one image both define `sv_weave_init_pkg`

Root cause: every run writes the init package under one fixed name (`render.py:186-221`,
added unconditionally at `run.py:260`, compiled at `run.py:277-279`), listing only that
run's woven packages. Two sibling Weave tasks feeding one image give two
`sv_weave_init_pkg` and two `sv_weave_init_m`. Chained is no better: a Weave downstream
of another sees the first one's init among its sources (`run.py:172` then skips the stub),
writes its own, and `passthrough: all` forwards both. `registration: static` does not help:
the init file is still written. Today the error surfaces in the simulator, not in sv-weave.

Options:

- (a) Unique names per run (`sv_weave_init_<hash>_pkg`). Breaks the documented entry points
  (`sv_weave_init_m`, `sv_weave_init_pkg::sv_weave_init()`); rejected.
- (b) Merge in the downstream Weave. Covers chains only, and the downstream task cannot drop
  the upstream init from the passthrough. Rejected.
- (c) **Proposed.** Separate the init from the weave:
  - config `init: true|false` (default true, today's behaviour) and a Weave param `init`
    overriding it. With false, no init files; the load stub stays (user code may still
    name `sv_weave_init_m`).
  - the manifest lists the packages to register, in order (`"register": [...]`), so a
    consumer need not infer them from `compile_order`.
  - new task `svweave.Init`: consumes the jsonManifest FileSets of upstream Weave tasks,
    writes one init (via `render_init`, given the union of `register` lists in input order;
    duplicates kept once) as a systemVerilogSource FileSet. Passthrough all.
  - detection: a Weave with `init: true` whose sources already hold a generated init file
    (header line `// Generated by sv-weave`) is an error naming the fix ("set init: false
    on the Weave tasks and add svweave.Init"). That turns the simulator's duplicate
    definition into an sv-weave diagnostic for the chained case. The sibling case is only
    visible to the image; document it in `docs/user/dvflow.rst`.

Tests:

- unit: `init: false` writes no init files, `compile_order` ends with the last woven
  package; manifest `register` lists the woven packages (and `sv_weave_gen_pkg` when
  present, in `__register` order).
- unit: chained sources holding a generated init with `init: true` give the error.
- sim (`tests/sim/test_factory.py`): `test_two_weaves_one_init`: `lib_a` and a second
  library woven by two Weave tasks (`init: false`), one `svweave.Init`, one image; both
  factories return their woven classes on Verilator.

Here: optional. `tests/weave/sv-weave.yaml` (one run over core and synth) works and is the
simpler flow; keep it and update its comment to point at `svweave.Init`. Split it only if we
want the suite to reuse `src`'s `woven` export (then `woven` needs `init: false`, which
changes what `src` exports; images built from `woven` alone would need an Init task too).
Recommend: keep the single run.

## 3. Contribution conventions

- No CONTRIBUTING file, no changelog, no PR template in the repo.
- CI is a pair: `.github/workflows/ci.yml` and `.forgejo/workflows/ci.yml` (keep them in
  step; the file says copy as a pair). Triggers: push to **any branch**, tags `v*`, PRs. The
  build job: `python -m build`, `twine check`, install the wheel, `pytest -q` (Python 3.11;
  we test on 3.12). Publish only on a `v*` tag with the dvkit.org release-authority switch,
  and the tag must equal `version_info` in `src/sv_weave/__version__.py`.
- So pushing a topic branch runs CI on that forge; GitHub and Forgejo are mirrored by
  git-sync (dvkit). Confirm with the sync policy which forge takes the PR before pushing.
- History is two squash-style commits; message style "<subject>: <summary>". Tests run
  from the wheel, so new data files (golden, sim cases) must be inside `tests/` (they are)
  and anything the package reads at run time must be in the wheel.
- Docs are Sphinx (`tests/docs/test_docs_build.py` builds them); the config schema
  `docs/_generated/sv-weave.schema.json` is generated (gitignored), so B's and gap 3's new
  config keys appear there without edits.

## 4. PR plan

Each PR is one branch off `main`, rebased as earlier ones merge, full suite green
(227 + its new tests). Release after PR 5 or 7 as 0.2.0 or 0.1.1 per the API decision in §1.1;
then bump the ivpm pin here.

| PR | Content | Depends on | Notes |
|---|---|---|---|
| 1 | A: `SvDecl` + `_txt` fix, docs, `sv_weave.api` exports | — | largest new surface; fw_proto needs it |
| 2 | B: `sources.top`, docs, `--top`, Weave `top` param | — | needed to weave fw-hdl |
| 3 | C: woven package repeats user imports | — | changes golden output |
| 4 | D: `DesignCtx.add_file` | — (touches `run.py` beside 2 and 3; trivial rebase) | needed for the xtor weave |
| 5 | Gap 2: split init file, `m_done` lint, lint test | 4 (D's clash set and compile order name `INIT_FILE`) | renames outputs |
| 6 | Gap 1: source fingerprint, `prepare`/`input_hash` factoring, `WeaveUpToDate` | 2 (hash includes `tops`) | |
| 7 | Gap 3: `init` option, manifest `register`, `svweave.Init`, detection | 5 (two init files), 6 (Weave task refactor in `tasks.py`) | needs the `init` decision confirmed |

1-4 are independent and can be opened together; 5-7 follow in order. Here, after each
lands: PR 5 drops the DECLFILENAME waiver and updates `fw_proto/python/tests/test_weave.py`;
PR 7 updates the `tests/weave/sv-weave.yaml` comment. Re-run `ci/run.sh` and the sv-weave
suite after each bump.
