# P5 open issues: alternatives and proposal

Status 2026-11-11. **All decided.** Issues 1 and 2: C, and b (plan D10), done. Issue 3: all
five rows as proposed. The `-Wall` lint is done (zero findings), and the Verilator fault is
reduced and saved for fixing (see the plan's dependency log).

P5 is built and passing (see [plan-new-style.md](plan-new-style.md) §1).
This note covers the questions it left open. Issue 1 is the one that matters; 2 follows from
it; 3 is small housekeeping.

## 1. What the transaction API loses

D6 gave `axi4_xact_if` plain arguments:

```systemverilog
task write(input addr_t addr, input data_t data[$], input strb_t strb[$],
           input attr_t attr, output axi4_resp_e resp);
task read (input addr_t addr, input int unsigned len, input attr_t attr,
           output data_t data[$], output axi4_resp_e resp);
```

The old `axi4_xact` object carried things this signature does not:

| Lost | AXI meaning | Effect today |
|---|---|---|
| per-beat RRESP | a subordinate may fail some beats of a read and not others (A3.4.4) | the subordinate adapter sends the read's one response on every R beat. The memory model's per-beat error ranges come out as "every beat DECERR" |
| WUSER per beat | sideband per W beat | always sent as 0 |
| BUSER, RUSER per beat | sideband on responses | dropped |

A second problem is not visible in the tests. The design's test of the core/derived split
(§1) is that **adding a field to a channel is a one-line change to the core**. The adapters
fail it:
- `attr_t` restates the AW/AR fields;
- `axi4_xact::to_aw`/`to_ar`/`from_aw`/`from_ar` copy them field by field.

A new AW field would need edits in three places, and nothing would flag a forgotten one.

### Alternatives

**A. Keep it (status quo).** The losses are documented, and per-beat detail is observed
through the channel listeners (as `l2` `error_responses` does).
- For: smallest API; nothing to do.
- Against: a subordinate model behind the adapter (the memory model now, a wrapped IP's
  model in P6) cannot return per-beat errors or USER, so the class view of a link is less
  capable than the pins. The field-copy problem stays.

**B. Widen the plain API.** For example `wuser[$]` into `write`, `buser` out, and
`ruser[$]`/`rresp[$]` out of `read`.
- For: one API, nothing lost.
- Against: every call grows by arguments most users never set, and at `P_MIN` they are
  zero-width noise. It does not fix the field copies: `attr_t` and the conversions stay.

**C. Two APIs: a full one on the channel payload structs, and the plain one on top.**
Add to the core:

```systemverilog
(* fw_api *)
interface class axi4_burst_if #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    // typedefs aw_t, w_t, b_t, ar_t, r_t from axi4_types #(P)
    pure virtual task write_burst(input aw_t aw, input w_t w[$], output b_t b);
    pure virtual task read_burst (input ar_t ar, output r_t r[$]);
endclass
```

A transaction is its address beat, its data beats and its response beat(s), in the
core's own payload types.

- **Nothing is lost.** Per-beat RRESP, every USER field, QOS/REGION and the ID all ride in
  the structs.
- **No field copies.** The adapters pass `aw_t`/`w_t`/... through unchanged. A new channel
  field reaches the transaction level with no edit, which meets the §1 test.
- **pyhdl-if friendly.** It keeps the API conventions: tasks, input/output only, packed
  structs and queues of them.
- **Generated support comes free.** `fw_api`, so the weavers make its base, listener,
  proxy, fan-out and imp. The listener (`write_burst_pre/post`) sees whole transactions,
  which is what the rules (P7) and monitor transactions (A5) want.
- **Layering:**
  - `axi4_mgr_adapter` implements `axi4_burst_if` natively;
  - `axi4_sub_adapter` calls a target through `axi4_burst_if`;
  - `axi4_mem_model` implements `axi4_burst_if` (per-beat errors restored).
- **The plain `axi4_xact_if` stays** for test writers and Python. Two small hand-written
  shims sit between the APIs:
  - `axi4_xact_on_burst` implements `axi4_xact_if` over an `axi4_burst_if`. It builds the
    AW from addr/attr and reports the worst R response;
  - `axi4_burst_on_xact` lets a plain-API target sit behind the subordinate adapter. It is
    lossy, by its nature.

  Only the shims know `attr_t` and do field conversions, in one place.
- Against: a second hand-written API in the core, so the design's "the only API written
  by hand" (§3.4) becomes two. There's some redundancy (`w.last`, `r.last`, `r.id`): the
  adapters set and check these. The P5 code needs a rework of about a day: adapters, memory
  model, env, and both cells' call sites.

**D. Go back to the `axi4_xact` object as the API (design Q4).** Lossless, but a class
handle in the signature breaks the pyhdl-if conventions, and the object's fields are a
third copy of the payloads. Rejected for the same reasons as in D6.

### Proposal: C

C is the only option that removes the losses and also restores the design's own test (one
edit to add a field). Its cost is one more short interface class in the core. The plain
API keeps its shape (with the change in issue 2), so D6 stands for test writers.

Sequence, about one session:
1. Add `axi4_burst_if` to `fw_proto_axi4_core_pkg`. Check that the weavers derive its
   classes, and add it to the goldens.
2. Rework the adapters and the memory model onto it. Add the two shims. `axi4_xact` and
   its field copies shrink to the shims.
3. Run `l2`/`l2_mem` against the full API, and put back the old suite's per-beat
   checks: `error_ranges` expects RRESP OKAY, OKAY, DECERR, DECERR again; WUSER, BUSER and
   RUSER round-trip at `P_WIDE`. Keep the plain-API tests through the shim, including
   `xact_listener`.
4. Plant bugs (as for P5) on the new paths, then a full regression.

## 2. What `len` means in `read`

The current implementation takes `len` as AxLEN (beats − 1), as in AXI.

| Option | For | Against |
|---|---|---|
| a. AxLEN, as now | matches the AXI field name | `read(addr, 4, ...)` returns 5 beats; asymmetric with `write`, whose beat count is `data.size()` |
| b. Beat count, renamed `beats` | symmetric with `write`; what a test writer means; 0 is an obvious error | the AXI encoding (−1) moves into the adapter (or the shim, under C) |
| c. Drop it, put `len` in `attr` | one fewer argument | `attr` would then hold a field that `write` must ignore or check against `data.size()` |

**Proposal: b**, renamed to `beats`, so nobody reads it as AxLEN. Under C the AXI encoding
lives only in `aw_t`/`ar_t`, where it belongs, and the plain API speaks in beats.

## 3. Smaller loose ends

| Issue | Options | Proposal |
|---|---|---|
| Subordinate adapter `max_delay` is in time units (`#n`), through an overridable `delay(n)` | a. keep; b. hand the adapter a clock event (a `virtual` handle or an `event` the env triggers) so it counts cycles | **a**, keep. It only reorders responses, and the delay need not be exact. Revisit if a test needs cycle-exact reordering |
| `fw_proto_axi4_behav_pkg` not linted at `-Wall` (a few WIDTHEXPAND on address sums) | a. add it to `lint-xtor`; b. its own lint task | **a**: the same top already has the class side and `--timing`. Fix the warnings with explicit casts |
| Verilator 5.055 faults or runs out of memory on a class `localparam` derived from `$bits(type param)` used in loop bounds and part-selects (`axi4_to_mem` with DATA narrower than the bus) | reduce to a small repro and raise it; or leave only the workaround | Reduce and raise it, with the other Verilator item in the plan's dependency log. Keep the workaround (a run-time member) |
| Old `l2_basic` xtor `concurrent_ids` fails (checker MAX_OUT 16 against 32 concurrent transactions) | a. raise MAX_OUT in the old harness; b. leave it until P8 deletes the old suites | **b** (done: P8 deleted the suite). It predates this work, its port passes, and P8 removes the old suite. Fixing it costs a change to old code for no lasting value |
| Weaver SV text in Jinja templates (open since P4) | a. now; b. with P6, when the abstractor emitter adds a large generator | **b**: do it when the emitter is written, so the pattern is set once with real templates (pilot on `xtors.py` at that point) |

## Decisions needed

1. Issue 1: **C** (`axi4_burst_if` plus the plain API on top)? Or A/B?
2. Issue 2: **b** (`beats`, a count)?
3. Issue 3 table: agree, or take any row differently?

With 1 and 2 agreed, the next step is the C rework above, before P6. P6's wrapped IPs
would otherwise be built on the lossy target interface.
