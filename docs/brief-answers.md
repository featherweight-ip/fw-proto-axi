# Answers to the brief's open questions

The brief is `axi4-package-brief.md` (repo root), written in the fw-hdl-sv-weave packet
(`../../featherweight-hdl/fw-hdl-sv-weave/axi4-package-brief.md`; the two copies differ
only by a path note). Its §10 asks the package agent to settle four questions and report
back. This is that report, as of 2026-11-12 (plan P0-P8 done; formal generation, A4, not
started).

| # | Question | State |
|---|---|---|
| Q1 | Do channel struct ports compose into a bundle cleanly? | settled |
| Q2 | SV struct and interface ports in reference IPs; the Yosys route | partly settled; PULP not wrapped |
| Q3 | Rule vocabulary gaps | settled: 12 gaps, [rules.md](rules.md) |
| Q4 | What the generated formal harness needs from the user | best current answer; A4 not built |

## Q1. Channel struct ports in a bundle

**Answer: yes, as a bundle of channels declared once, generated into one struct port.**
Neither option in the brief exactly; parts of both.

- **Declared** as a bundle of channels: one class, one member per channel, each a
  handshake family over a payload struct (`src/core/axi4_bundle.svh`;
  [design-new-style.md](design-new-style.md) §3.3).
- **Generated** as one struct port per role, with one flat field table whose fields
  carry the channel prefix (`awvalid`, `awaddr`, ..., `rlast`): `axi4_sp`,
  `axi4_mgr_sp`, `axi4_sub_sp` (`fw_proto/python/fw_proto_weave/ports.py`).
  `connect()`, `link()` and `bind_inner()` take the whole port.
- **Per-channel access** comes from the derivatives, not from separate struct ports:
  - the channel APIs have one method per channel (`axi4_req_if::aw`), and their
    listeners `<ch>_pre`/`<ch>_post`, so monitors and rules see each channel;
  - the pin map works on field names, so `prefix(sp, "s_axi_")` maps all five channels
    in one line; `rename`, `pin(..., msb, lsb, slot)` reach a single field;
  - the generated transactors are one fw-hdl rv transactor per channel, with knobs by
    path per channel (`"<role>.<ch>.max_gap"`).

Cross-channel facts (W beats per AW, B after the last W, ID matching) are not in the
bundle. They are rules, so `protocol-ports.md`'s `relations()` strings are not needed.

Evidence: `bundle` suite (field table against the AMBA pin list typed by hand, for three
parameter sets), `l1` in both views, three IPs and the presets (`dfm run ip`).

## Q2. SV struct and interface ports; the Yosys route

### What is settled

- **Packed-vector pins** (several ports' fields in one wide pin, verilog-axi's
  crossbar): `.slot(k)` on a prefix rule, or `pin(pin, sp, field, msb, lsb, slot)`. The
  emitter concatenates a pin's slots and checks they are 0..n-1, each once. Added to
  fw-hdl's `fw_extern_map` (plan §8). `axi_crossbar` 2x2 passes
  ([reference-ips.md](reference-ips.md)).
- **The Yosys route used so far:**
  - native Yosys 0.70 reads verilog-axi and wb2axip (plain Verilog). Two workarounds:
    sized parameter values over 32 bits (the emitter), and `$error` patched to
    `$display` in a copy of the RTL (`tests/ip/ip_checks.py`);
  - sv2v for this package's own SystemVerilog going to SymbiYosys
    (`tests/formal/fv_b2b.sh`, `tests/formal/run_sby.sh`), and for the class-free layer in
    the pytest suite. sv2v is in `packages/yosys/bin`;
  - yosys-slang was not needed and is not installed (no plugin in
    `packages/yosys/share/yosys/plugins`).

  **Recommendation:** sv2v is the route for heavy SystemVerilog. Try yosys-slang only if
  sv2v fails on PULP.
- **The emitter's netlist** declares one flat net per field and connects pins by name
  (`fw_proto/src/fw_emitter.svh`). It has no notion of a struct-typed or
  interface-typed module port.

### What is open: PULP struct pins

PULP IPs are not wrapped (PULP is not fetched). What wrapping one needs, from reading
the netlist and pin map code:

1. **Type parameters.** PULP modules take `req_t`/`resp_t` as type parameters. The
   extern map has `param(name, longint)` and `param_str(name, string)`, which emits a
   quoted string. Neither can pass a type. The netlist would also need the typedefs
   (`AXI_TYPEDEF_ALL(...)`) in scope.
2. **Member pins.** A module port connection takes one expression, so
   `x.pin("slv_req_i.aw.addr", ...)` cannot become a `.pin(net)` connection. The emitter
   would declare a net of the IP's struct type and assign each member from (or to) the
   field nets.
3. **Whole-struct binding** (a struct pin to a struct port when layouts match) does not
   fit as is. PULP's request struct carries valid and ready bits beside the channel
   structs, and its AW channel has `atop` (AXI5), which our `aw_t` lacks. This is from
   PULP's typedef macros as documented, not checked against its source here.

Options:

| Option | Cost | Gives |
|---|---|---|
| A. Member-path pins: type parameters in the extern map; the emitter declares struct nets and assigns members | fw-hdl extern map + emitter work | PULP wrapped with a prefix-like rule; the brief's first option |
| B. A flat shim module per IP, written by hand (or generated from the typedef) | one file per IP; no fw-hdl change | PULP wrapped today, as a plain-pin IP; the shim is in the netlist |
| C. Whole-struct binding | needs payload layouts that match the IP's, which they don't | nothing for PULP |

**Recommendation:** B for `axi_cut` now, to get a PULP IP under test with no fw-hdl
change; A once a second struct-port IP family is wanted. **Undecided:** A versus B as
the long-term answer, and how the netlist names a typedef source (a package, or the
macro call text).

### What is open: SV interface ports (taxi)

Not attempted. taxi was not shortlisted (CERN-OHL-S-2.0, interface ports only).
**Recommendation:** don't support interface ports in the pin map; wrap such IPs in a
flat shim (option B above). **Undecided:** confirm, or name an IP that needs them.

## Q3. Rule vocabulary gaps

Answered in [rules.md](rules.md), "Vocabulary gaps found". In short:

| # | Gap |
|---|---|
| 1 | Which call accepts a request differs by source: pre on a proxy, post on pins. Formal must be told which |
| 2 | Bounded registers are needed (`fw_value`), not only counters and flags |
| 3 | Pure functions of the event (burst arithmetic), from the synthesizable defs package |
| 4 | Several quantified variables per rule (an ID plus an index within it) |
| 5 | Same-ID order shows only through lengths and data; data integrity (A5) catches the rest |
| 6 | Capacity needs a declared fact; today it is an argument at the attachment |
| 7 | The exclusive rule is free form; it could be restricted. Exclusive read/write pairing is not checked |
| 8 | Reset and X are not events; they stay with the pin checker or the rv family |
| 9 | A VALID retraction must be an event (fixed in fw-hdl's rv monitor; a final drop is still silent) |
| 10 | Liveness is not expressible; formal needs a bounded-response form |
| 11 | Which side a rule binds is a comment, not data |
| 12 | `retire()` is a simulation hint with no formal meaning |

Added to the vocabulary to cover 2 and 4: `fw_value #(T)`, and `fw_rule_set` with
`fw_rule_node` (one instance per value seen, several variables, `retire()`). All nine
AXI4 rules are in it but `exclusive`, the deliberate escape hatch.

## Q4. What the generated formal harness needs from the user

Formal generation (A4) is not built. This answer comes from the hand-written harness for
the generated transactor cores (`tests/formal/axi4_fv.sv`), the pin checker
(`src/checker/axi4_checker.sv`) and the rule gaps. It separates what the user must give
from what the harness should derive.

### From the user, beyond the wrapper

| Input | Why | Evidence |
|---|---|---|
| **Capacity:** outstanding reads and writes per port (total; per ID if the IP limits that) | Bounds the harness's bookkeeping, and the solver's state. Also a rule (`capacity`) | The crossbar's master ports carry `M_ISSUE`+1, not `M_ISSUE`; the first declaration was wrong and the rule caught it ([rules.md](rules.md)) |
| **Small parameters for the solver:** the IP's widths, through `P` | Proofs scale with address, data and ID width | `axi4_fv` runs at ADDR 12, DATA 8, ID 1, `MAX_OUT` 2; BMC depth 16 takes about 2 min |
| **Depth**, and proof mode (BMC, cover, induction) | A job setting, as in `tests/formal/flow.yaml` | |
| **A response bound**, if liveness is wanted | Gap 10: no rule can say "eventually" | |
| **Optional user rules**, such as data integrity | The brief's §7.1 step 3 | not written yet (A5) |

The wrapper already gives the rest: the module, its parameters, clock, reset polarity
and the pin map from fields to pins.

### Derived, not asked

These are facts the package or the rule must carry as data, so the user is not asked
for them:
- **Assume or assert per rule:** which side a rule binds (gap 11). The manager-side
  contract becomes assumptions on the IP's inputs and the subordinate's obligations
  assertions, as `axi4_checker`'s `ASSUME_MGR`/`ASSUME_SUB` do by hand.
- **Event timing:** on pins a request counts at the handshake (`_post`, gap 1).
- **Signal-level rules** from the handshake family (`fw_rv_hold`), plus reset and X
  properties that rules cannot state (gap 8), as family properties.
- **Quantified variables** as free symbolic constants, one per `fw_any`; bounded
  registers sized from their type.
- **Bookkeeping sizes** from the declared capacity. The checker's `MAX_OUT` is a separate
  bookkeeping bound that misreports past it (the `capacity` case in `rules_teeth`).
  Deriving both from one number avoids that.
- **Reset:** one reset at the start, as `axi4_fv` assumes, unless the user asks for more.

### Undecided

- Where capacity is declared: the API's "declared facts" (brief §4), the extern map, or
  the attachment (today). Per ID or total.
- How a bounded-response (liveness) bound is written, and whether it belongs to the rule
  or the harness.
- What the harness does with a free-form rule (`exclusive`): drop it with a warning, or
  require it in restricted form (gap 7).
- Whether `retire()` needs a formal meaning or is ignored (gap 12).
- Whether the user supplies covers, or the harness derives one per rule event.
