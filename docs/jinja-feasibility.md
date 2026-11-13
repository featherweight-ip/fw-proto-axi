# Jinja templates for the fw-proto weavers: feasibility

Status 2026-11-12: assessment, plus a pilot on `xtors.py` that reproduces all 9
xtor goldens byte for byte. The pilot is [jinja-pilot.patch](jinja-pilot.patch)
(not applied; `git apply docs/jinja-pilot.patch` from the repo root).

Scope: the SV text the `fw_proto_weave` package (`fw_proto/python`) builds in
Python. `src/weave` and `tests/weave` hold sv-weave configs and stub tops only;
no Python there. This stays SV text generation; nothing here touches XLS.

**Recommendation: go with conditions** (§7). Effort about 4 days (§6).

## 1. Inventory

All weavers build a `list[str]` of lines with `%` formatting (no f-strings),
then `"\n".join(out)`. Indentation is literal spaces inside each string.
Shared helpers: `sv.py` (`proto`, `zero_of`, `end_of`, `args_unused`),
`model.Api` (`spec`, `header`, `typedef_block`, `default_of`), `bundle.Bundle`
(`spec`, `params_ref`, `struct_param`), `ports._opt_cond`.

"Emit lines": lines of functions that build SV text. "Control": `for`, `if`,
conditional expressions and comprehensions inside them.

| File | Lines | Emit lines | Control | What it emits | Text vs logic |
|---|---|---|---|---|---|
| `xtors.py` | 430 | 268 | 57 | xtor core/module/if files, chans class, bridges, `_bits` fns | most logic: per-channel/per-member loops, LSB sums, port commas, role/kind switches |
| `abs.py` | 284 | 189 | 7 | socket, abs, observers, handle, `connect()` | mostly literal blocks with a few substitutions; easiest to template |
| `ports.py` | 111 | 83 | 14 | `<proto>_sp`, role sps | field table loops, `fw_opt` guards |
| `endpoints.py` | 88 | 64 | 15 | inbox, payloads | channel loops, inline joins |
| `proxies.py` | 78 | 55 | 9 | proxy, fanout | per-method loops, arg-list joins |
| `bases.py` | 31 | 18 | 6 | `<api>_base` | per-method/per-output, calls `proto`/`zero_of` |
| `listeners.py` | 49 | 20 | 2 | `<api>_listener` | small; most code derives the listener `Api`, not text |
| `imps.py` | 28 | 17 | 3 | `<api>_imp` | small |
| total | 1099 | ~714 | 113 | | |

`weaver.py` (133) only sequences the render functions and calls
`d.add_item` / `d.add_file`; it stays Python. `model.py`, `bundle.py` build the
model; no text.

## 2. How sv-weave renders and maps origins today

- A weaver hands sv-weave a finished string: `DesignCtx.add_item(pkg, text)`,
  `add_file(name, text)` (`weave/design.py`), or `ClassCtx` field/item calls
  (`weave/ctx.py`). Each becomes one `SvFragment(text, Origin)`.
- `Origin` = (weaver, ext_set, file, line). file:line is `call_site()`: the
  first frame outside the sv_weave package. For fw-proto that is the
  `d.add_item` / `d.add_file` call in `weaver.py` (lines 118, 123, 129, 131,
  133), not the render function.
- `render.Emitter.frag()` writes the fragment's lines (after
  `textwrap.dedent`, `strip("\n")`, per-line `rstrip`) and records one
  `LineSpan(first, last, origin)` for the whole fragment. `render_file` puts
  the header on line 1, so an `add_file` fragment is lines 2..N.
- Consumers: `verify.py:46` and `verify_rules.py:81` call
  `RenderedFile.origin_at(line)` to name the weaver behind a diagnostic.

So the map today is fragment-grained and points at `weaver.py`. Checked on
`axi4_mgr_xtor_core.sv`: one span, `(2, 170, fw-proto[core] at weaver.py:133)`.
Templates cannot make this worse; they can make it better.

### What a `render(template, ctx)` API in sv-weave needs

Keep the Jinja dependency in sv-weave, optional, and keep the map engine-neutral
(text in, text plus spans out):

1. `DesignCtx.render(template, **ctx) -> SvText` (and the same on `ClassCtx`):
   renders, and returns the text plus a list of `(rel_first, rel_last,
   template_file, template_line)`. `add_item` / `add_file` / class items accept
   `SvText` as well as `str`.
2. `SvFragment` gains optional sub-spans. `Emitter.frag` emits one `LineSpan`
   per sub-span, offset by the fragment's first line, falling back to the
   whole-fragment span for plain strings. Sub-spans must be computed on the
   *normalized* text (after dedent and blank-line strip), or the strip of
   leading blank lines shifts them.
3. `Origin` keeps contributor/ext_set; file:line becomes the template's. Keep
   the Python call site too (a second field), since "which render call" is
   still what you want when a context value is wrong.
4. Environment: `trim_blocks`, `lstrip_blocks`, `keep_trailing_newline`,
   `StrictUndefined`, no autoescape; a loader per weaver package
   (`PackageLoader` or a path next to the module).

How to get template lines per output line (prototyped, works): drive
`template.root_render_func(ctx)` as a generator; after each chunk, walk
`gi_yieldfrom` to the innermost generator and map its `gi_frame.f_lineno`
through `template.get_corresponding_lineno()`. Lines inside a multi-line
chunk get the chunk's template line plus their offset. On `core.sv.j2`:
748 chunks for 169 lines; static lines map exactly, lines produced by a loop
map to the loop's `{% for %}` line or the expression line (off by 0..2 around
block tags). Good enough for "this came from core.sv.j2 near line 23".
It uses Jinja internals (`root_render_func`, `new_context`); pin jinja2 3.1
and test it. The cheap fallback, one span per render at template line 1, is
already better than today.

### Jinja availability

- `packages/python` has jinja2 3.1.6 and markupsafe 3.0.4, pulled in by the
  docs tools (sphinx, myst-parser, sphinxcontrib-mermaid). Nobody declares it
  for weaving.
- No Jinja use in sv-weave, fw-hdl or zuspec-be-sv (no imports, no `.j2`
  files). sv-weave's deps are pyslang, pydantic, pyyaml.
- Add `jinja2>=3.1,<3.2` as an sv-weave extra (`sv-weave[templates]`) with a
  lazy import in `render`, or as a direct dep of whatever installs
  `fw_proto_weave`.

## 3. Pilot: `xtors.py`

Done in a scratch copy; the real weaver is unchanged. Patch:
[jinja-pilot.patch](jinja-pilot.patch).

Templates (`fw_proto_weave/templates/xtors/`, 157 lines total):

| Template | Replaces | Lines |
|---|---|---|
| `chans.sv.j2` | `render_chans` | 28 |
| `core.sv.j2` | `render_xtor_core` | 27 |
| `if.sv.j2` | `render_xtor_if` | 8 |
| `module.sv.j2` | `render_xtor_module` | 31 |
| `role_bridge.sv.j2` | `render_role_bridge` | 34 |
| `mon_bridge.sv.j2` | `render_mon_bridge` | 29 |

Context: one view object per (bundle, role), built in Python.
- `XtorView`: `name`, `role`, `b` (the `Bundle`), `chans`, `knobs`, `what`,
  `clk`, `rst_hi`, `dp`, `imports`, `req`/`rsp`, `vif`; for roles also
  `sends`, `recvs`, `out_api`, `in_api`, `in_var`; `ports(uplink)`.
- `_Chan`: `name`, `payload`, `payload_name`, `kind`, `up`, `verb`,
  `bits_fn`, `sigs`, `api`, `fan`, `members`.
- `_Member`: `up`, `lsb`, `lhs`, `rhs` (the `fw_opt` guard already applied).

Stays Python: `check`/`check_defs`, `_width`, `_pin_type`, `_param_type`,
`_opt_cond`, the LSB sums, `_ports` (comma placement that skips blank
separator lines), `render_bits_fns` (small, wrapped by `args_unused`),
`render_files`/`render_bridges` (sequencing). `xtors.py` goes 430 -> 308
lines; total with templates 476. It does not shrink; it moves SV out of
Python.

Current code (`render_role_bridge`, tail):

```python
    for c in sends:
        out += ["",
                "    virtual task %s(input %s t);" % (c.name, c.payload_name),
                "        wait (vif.bound);",
                "        vif.chans.%s.send(t);" % c.name,
                "    endtask"]
    out += ["",
            "    // One loop per received channel, so a stalled channel holds up no other.",
            "    virtual task run();",
            "        wait (vif.bound);",
            "        fork"]
    for c in recvs:
        out.append("            forever begin %s t; vif.chans.%s.recv(t); %s.%s(t); end"
                   % (c.payload_name, c.name, in_var, c.name))
    out += ["        join", "    endtask", "endclass"]
```

Template (`role_bridge.sv.j2`, same output):

```jinja
{% for c in x.sends %}

    virtual task {{ c.name }}(input {{ c.payload_name }} t);
        wait (vif.bound);
        vif.chans.{{ c.name }}.send(t);
    endtask
{% endfor %}

    // One loop per received channel, so a stalled channel holds up no other.
    virtual task run();
        wait (vif.bound);
        fork
{% for c in x.recvs %}
            forever begin {{ c.payload_name }} t; vif.chans.{{ c.name }}.recv(t); {{ x.in_var }}.{{ c.name }}(t); end
{% endfor %}
        join
    endtask
endclass
```

Where it got worse: long single-line connection lists. Python's
`", ".join(conns)` became `{%- for %}...{{ ", " if not loop.last }}` and a
`{%- if %}` splice in `core.sv.j2` and `module.sv.j2`. Rule for the real
migration: build such lists in the view (`c.conns`) and write
`{{ c.conns|join(", ") }}`.

Result: `pytest fw_proto/python/tests` against the pilot, 17 passed (all 12
goldens, the three Verilator lint tests). A one-character template edit
fails exactly the 3 `*_xtor_core.sv` goldens, so the templates are what
ran.

## 4. Golden tests

`fw_proto/python/tests/test_weave.py` already compares byte for byte
(`text == fp.read()`), regenerated with `FW_PROTO_REGEN=1`:
- `test_golden`: `fw_proto_axi4_core_pkg_woven.sv` (listeners, bases,
  proxies, imps, inboxes, sps, payloads, chans, bridges, abs glue),
  `fw_proto_axi4_defs_pkg_woven.sv` (`_bits` fns), `weave_synth_pkg_woven.sv`
  (synthetic API).
- `test_xtor_golden`: the 9 `axi4_{mgr,sub,mon}_xtor{,_core,_if}.sv`.
- `test_lint_wall`, `test_xtor_lint_wall`, `test_xtor_cores_class_free`:
  Verilator on the woven code.

Every weaver writes into at least one golden (2043 lines total). Migration
rule: never regenerate goldens in a migration commit; the diff must be empty.

Gaps, to close before migrating (they are the risky paths):
- Only one bundle (AXI4): active-low reset only (`fw_reset_n`), always a
  struct parameter. Active-high `fw_reset` and the no-struct-param branch of
  `render_sp` (`return "";`) are never emitted.
- `tests/weave/rv` (fw-hdl rv APIs, `#(type T)` header) has no pytest golden.
- `fw_default` variants in `bases.py` are only as covered as the two APIs use
  them.

Add a golden for the rv config and a small synthetic bundle (active-high
reset, no struct param, an `fw_opt` member) to `tests/weave/synth` first.
Note that sv-weave's dedent/rstrip normalization hides trailing whitespace
and leading blank lines from the goldens; that is fine (the final file is
what matters) but means a template's raw output can differ from the golden
in those places.

## 5. Risks

| Risk | Seen in pilot | Mitigation |
|---|---|---|
| Whitespace control (blank lines between blocks, trailing newline) | handled by `trim_blocks` + `lstrip_blocks`; first try matched | fixed env settings; goldens |
| Inline joins on one line | ugly `{%-` / `loop.last` | lists built in the view, `join` filter |
| Indentation of nested blocks (`args_unused` wrap, `typedef_block(indent)`, a multi-line value inside an indented line) | not hit in xtors; will be in bases/listeners (`typedef_block`) | keep wrappers in Python around `render()`; `indent` filter or pass pre-indented lines |
| Debuggability | `StrictUndefined` names the missing attribute and template line; tracebacks show template file:line | view objects with plain attributes, no logic in templates beyond loops/ifs |
| Line-map fidelity | template line per output line, off by 0..2 lines around block tags; relies on Jinja internals | pin jinja2 3.1; test; fall back to one span per render |
| Logic leaking into templates | small | rule: compute in the view, templates only loop and substitute |
| Two places to read per generator | real cost for small weavers | migrate only the big, text-heavy ones (§7) |
| Packaging | templates are package data | `package-data` in whatever installs `fw_proto_weave`; plugin-path use works as is |
| New dependency | jinja2 only present via docs tools | declare it (sv-weave extra) |

## 6. Effort

| Item | Days |
|---|---|
| Gap goldens (rv config, synthetic bundle) | 0.5 |
| sv-weave `render()` + `SvText` + sub-span line map + tests | 1.5 |
| `xtors.py` (land the pilot, view lists for joins, drop dead `_typedefs`) | 0.5 |
| `abs.py` | 0.5 |
| `ports.py`, `endpoints.py`, `proxies.py` | 0.5 |
| `bases.py`, `listeners.py`, `imps.py` (+ `proto`/`zero_of` as filters) | 0.5 |
| total | ~4 |

Without the line-map work (one span per render): ~2.5 days.

## 7. Recommendation

**Go with conditions:**
1. Goldens cover the untested branches first (§4).
2. sv-weave owns `render()` and the line map; weavers never call Jinja
   directly, so the map and the env settings are in one place.
3. Templates hold no logic beyond `for`/`if` and substitution; lists and
   expressions are built in Python view objects.
4. Each step is a separate change with an empty golden diff.
5. Stop after step 5 below if the small weavers read no better as templates.

Order:
1. Gap goldens.
2. sv-weave `render()` with fragment-level origin (template file, line 1).
3. `xtors.py` (pilot, cleaned up).
4. `abs.py` (most literal SV, least logic: the best gain).
5. sv-weave per-line sub-spans; check `verify` diagnostics name template lines.
6. `ports.py`, `endpoints.py`, `proxies.py`.
7. `bases.py`, `listeners.py`, `imps.py`, if still worth it.

## 8. After step 5

Status 2026-11-13: steps 1-5 of §7 done (plan §12, P10), uncommitted; per-step
patches in `rundir/p10/`. Every golden stayed byte-identical through steps 2-5.

### Line counts

| | Before (Python) | After: Python | After: templates | After: total |
|---|---|---|---|---|
| `xtors.py` | 430 | 324 | 156 (6 files) | 480 |
| `abs.py` | 284 | 167 | 132 (4 files) | 299 |

As predicted, nothing shrinks: SV moves out of Python, and the views that feed the
templates cost lines. `xtors.py` keeps the checks, `_width`/LSB sums, `_ports`,
`render_bits_fns` and ~100 lines of view classes (`XtorView`, `_Chan`, `_Member`)
that build every list the templates join; `abs.py` keeps the names, `connect_method`
(it feeds `ports.py`'s role sp, so it moves with step 6) and two flat views.

### Readability

`abs.py` is the clear win. Before (`render_abs`), the SV is a list of `%`-formatted
strings with the arguments a line or two away:

```python
           "// %s methods never return; at run time %s replaces it."
           % (sends, handle_name(b, role)),
           "class %s %s extends fw_boundary implements %s;"
           % (name, b.header, b.spec(sends))]
    for c in chans:
        out.append("    typedef %s::%s %s;" % (b.spec(sends), c.payload_name, c.payload_name))
```

After (`templates/abs/abs.sv.j2`), it reads as the SV it produces:

```jinja
// {{ v.sends }} methods never return; at run time {{ v.handle }} replaces it.
class {{ v.abs }} {{ v.header }} extends fw_boundary implements {{ v.sends_spec }};
{% for c in v.send_chans %}
    typedef {{ v.sends_spec }}::{{ c.payload_name }} {{ c.payload_name }};
{% endfor %}
```

`observers.sv.j2` and `handle.sv.j2` (long literal classes, a dozen names) gain the
most: no `\"`/`%%` escaping, indentation is the SV's. In `xtors/` the templates
also read well once the lists live in the views (`{{ c.core_conns|join(", ") }}`
replaces the pilot's `{%- for %}...loop.last`); the cost is reading two files and
a view attribute per name (`x.in_spec`, `c.vif_type`). With view attributes named
after what they print, that has been cheap in practice.

### The line map

sv-weave maps each woven line to the template line it came from (step 5):
the render generator is driven chunk by chunk; an expression chunk takes the
template line from Jinja's debug info, and a static chunk (which Jinja yields with
no line marker) is placed by the template's own `TemplateData` nodes between the
markers around it. Measured on the xtor run (AXI4 + synx): all 1778 non-blank
template-produced lines map to a template line whose literal text is on that
output line; loop iterations map to the loop body line. Planted errors in a scratch
copy came back as:

```
.../templates/xtors/role_bridge.sv.j2:30: error: use of undeclared identifier 'xx'
  [woven code .../fw_proto_axi4_core_pkg_woven.sv:1176, from fw-proto[core] at
   .../role_bridge.sv.j2:30 (rendered at .../xtors.py:301)]
.../templates/xtors/core.sv.j2:17: error: expected ';'
  [woven code .../axi4_mgr_xtor_core.sv:80, ...]
```

That is better than before templates, where every diagnostic named `weaver.py`'s
`add_item` line. It depends on Jinja 3.1 internals (`root_render_func`,
`new_context`, `debug_info`, the parser's `TemplateData`); the extra pins
`jinja2>=3.1,<3.2`, a test covers it, and any failure falls back to template line 1.

### Findings along the way

- The xtor run's AXI4 package (chans, bridges, abstractor glue) had no golden; §4
  was wrong to list them under `fw_proto_axi4_core_pkg_woven.sv`. Added
  `fw_proto_axi4_core_pkg_woven_xtor.sv`, generated by the string weavers.
- Active-high `fw_reset` only reaches xtors/abs, which need a struct parameter, so
  one synthetic bundle could not cover both gaps: `synb` (no struct parameter) is in
  the plain run, `synx` (struct parameter, `fw_reset`) in the xtor run.
- A template edit must re-weave: sv-weave's plugin fingerprint now hashes `.j2`
  files as well as `.py`.

### Recommendation for steps 6-7

| Weaver | Lines | Recommendation | Why |
|---|---|---|---|
| `ports.py` | 111 | migrate (step 6) | the role sp classes are literal SV; brings `abs.connect_method` along, so abs is all-template |
| `endpoints.py` | 88 | migrate (step 6) | `render_payloads` is three per-member loops full of `%%0h` and `\"` escapes, the kind of text templates fix; `render_inbox`'s joins go to a view |
| `proxies.py` | 78 | leave | per-method logic (return variable, pre/post argument lists, `typedef_block`, the header `replace("  ", " ")`) would move into a view as large as the template |
| `bases.py`, `listeners.py`, `imps.py` | 31 / 49 / 28 | leave (skip step 7) | small, mostly calls to `proto`/`zero_of`/`typedef_block`; two files to read for 20 lines of SV is a loss |

So: do step 6 for `ports.py` and `endpoints.py` only, and stop there. Mixed
styles in one package are acceptable: the rule is "text-heavy generators use
templates", and the remaining four are logic-heavy.
