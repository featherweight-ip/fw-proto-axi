# Method-level formal verification: options and plan

Status 2026-11-13: proposal. Nothing here is built. It extends plan §9 A4 (formal
generation) and takes in the deadlock analysis held in P9 (§11: to be done statically).

The question: can the rules written against the listener APIs be checked statically, on
RTL and on method-level designs, and can relationships between method-level designs be
checked without going to synthesizable code first?

Short answer: yes to all three. The rule vocabulary was restricted for this; what is
missing is a rule IR, a symbolic-constant primitive, and one new engine adapter.

## 1. What a rule is, formally

A rule that is not free form (`rules.md`, "The vocabulary") is a small automaton over API
events:

| Rule item | Formal meaning |
|---|---|
| listener call (`on_aw`, `on_w`, `on_b`, ...) | one transition, its arguments the transition's inputs |
| `fw_count`, `fw_flag`, `fw_value #(T)` | state: bounded registers |
| pure functions (`fw_proto_axi4_defs_pkg`) | combinational logic, already synthesizable |
| `chk(c, msg)` | the property: `assert` on the side that must keep it, `assume` on the side that is driven |
| `fw_any #(T)` | a free symbolic constant (`$anyconst`): one instance stands for every value |
| `retire()` | nothing (a simulation hint, gap 12) |

`fw_any` is the reason simulation needs `fw_rule_set` (an instance per value seen); in
formal it is the standard one-instance trick. Eight of the nine AXI4 rules are in this
form. `exclusive` is free form and stays opaque to formal until it is restated (gap 7).

What the rules do not carry yet, and formal needs as data, not comments:
- which side a rule binds (gap 11): assume vs assert per attachment;
- which call counts as the event (gap 1): pre on a proxy, post on pins;
- capacity as a declared fact (gap 6).

## 2. Route 1: lower to synthesizable code, Yosys and SymbiYosys

This is A4 as briefed (brief §7.1).

**Rules as a pin monitor.** Events are the handshakes (the rule base's `pins` mode).
State becomes registers, `fw_any` becomes `$anyconst`, `chk` becomes `assert` or
`assume` by side. The monitor attaches through the field table, so it works on any RTL:
the wrapped reference IPs (`axi_ram`, `demofull`, `axi_crossbar`), and the generated
transactor cores.

**A synthesizable method-level design.** Lower the design through fw-hdl's flow first
(native `fw.hdl.lower`, or an engine behind its interface). Its API calls become
ready/valid channels, and the same monitor attaches to them. What is proved is that
engine's schedule, not the source. That is sound for these rules: they constrain event
order, not cycles (fw-hdl `docs/reference/contracts.md`: the source fixes order on each
port, not the cycle), so a rule that holds is a property of every legal schedule only if
it is cycle-independent, which all eight are.

**One lowering, not two.** Rather than a separate rules-to-SVA generator, treat each rule
as a component that receives events, and lower it through the same Zuspec IR path as the
design. The rule and the design then share one front end and one SV back end. New
primitive needed: a symbolic constant in Zuspec IR and its SV emission (`$anyconst`).
This goes through Zuspec IR and an engine-neutral SV back end; it is not routed through
XLS (XLS is one synthesis engine behind the engine interface).

**Deliverable:** brief §7.1 on `axi_ram`: assumptions from the manager-side rules,
assertions from the subordinate's, `rv_hold` and the reset checks from the pin family;
comparison with wb2axip `faxi_slave` (lines written, coverage, run time); one planted bug
whose counterexample is printed as an API event trace.

## 3. Route 2: check at method level, no synthesis

**The model.** Compose, as one transition system over calls rather than clock cycles:
- the design's methods, from Zuspec IR;
- the assume rules, as a nondeterministic environment (they constrain what the
  environment may call);
- the assert rules, as the checker.

One step is one call (or one activation of a proc). Emit the system as BTOR2 (or SMT-LIB)
from Zuspec IR through a new engine adapter, and run BMC and k-induction (pono, or the
solvers yosys-smtbmc drives).

**What it gains.**
- Far fewer steps than cycles: no handshake, backpressure or pipeline state. Deeper
  bounds for the same cost.
- The counterexample is an API event trace directly (brief §7.1 item 5), with no
  waveform-to-event mapping.
- Data abstraction is native: `fw_any` over IDs and indices.

**Concurrency.** At method level, calls on one port are ordered; calls on different ports
are ordered only by data (fw-hdl `docs/methodology/timing.md`). The model chooses
nondeterministically which enabled port operation fires next, so it covers every legal
interleaving, not one schedule. This is the main piece of work in route 2. The D11
two-way API (responses as calls back) is handled the same way: a response call is an
operation on its port, enabled or blocked like any other.

**Deadlock, statically.** With the interleaving model, a deadlock is a reachable state in
which calls are pending and no port operation is enabled. The held P6 follow-up ("a
response call that blocks on a channel the same process must drain", D11 rule 2) is that
query, and the planted `sub_b_inline` bug (the one D11 teeth case simulation misses)
becomes a reachability check in a cyclic topology. The deadlock work is folded in here
instead of being a separate analysis.

**Relationships between designs.** The same engine checks a pair of designs side by side:
- refinement or equivalence of two method-level designs under an fw-hdl contract rule
  (`fw_order_rule`: in order, per key, allowed passes): both designs, a shared
  nondeterministic environment, and the order checker restated in the restricted
  vocabulary;
- round trips, e.g. `axi4_burst_on_xact` ∘ `axi4_xact_on_burst` is the identity on the
  burst API;
- a model against its RTL, statically (today fw-hdl's `canon` compares recorded
  simulation traces).

## 4. Limits

| Limit | Consequence |
|---|---|
| Timing and reset (`rv_hold`, VALID low in reset, no X; gap 8) are not call events | stay at pin level, route 1 only |
| Liveness is not expressible (gap 10) | needs a bounded-response form in the vocabulary, for both routes |
| k-induction on side-by-side designs needs helper invariants | deep BMC is easy; full proofs need strengthening (counter relations, invariants per rule) |
| `src/behav` uses queues, `fork`, mailboxes, `#n` delays | outside fw-hdl's static subset; route 2 needs them restated with bounded arrays and counters. fw-hdl static-subset procs qualify as written |
| fw-hdl's SV-to-Zuspec front end takes procs | a rule is a listener class (one method per event, each a transition); the front end needs that shape. It is simpler than a proc |
| Free-form rules (`exclusive`) | opaque; restate in the vocabulary (gap 7) or leave to simulation |
| Interleaving explosion with many ports | partial-order reduction, or bounding outstanding calls per port (capacity facts, gap 6) |

## 5. Plan

| Phase | What | Exit |
|---|---|---|
| F0 | Rule metadata as data: side (assume/assert), event source (pre/post), capacity as a declared fact. In `fw_proto/src` and `src/rules` | rules carry it; simulation unchanged; `rules_teeth` 17/17 |
| F1 | Rule IR: the eight restricted rules into Zuspec IR (listener-class front end), plus the symbolic-constant primitive | IR for all eight; an IR-level interpreter replays `rules_teeth` event traces with the same verdicts |
| F2 | Route 1: rule components through the engine-neutral SV back end; SBY job per wrapped IP; `axi_ram` first | brief §7.1 on `axi_ram`: wb2axip comparison, planted bug with an API event trace |
| F3 | Route 2 pilot: BTOR2 engine adapter from Zuspec IR; interleaving model; one small static-subset design plus two or three rules | BMC finds a planted ordering bug; trace printed as API events |
| F4 | Deadlock queries in route 2; restate the D11 adapters' core (or a model of it) in the static subset | `sub_b_inline` found in a cyclic topology; clean adapters pass to a stated bound |
| F5 | Relationships: two-design composition with an order checker; `burst_on_xact` ∘ `xact_on_burst` identity | identity proved to a bound; a planted reorder caught |

F0 and F1 are shared by both routes. F2 is the A4 deliverable. F3-F5 are the new
method-level work; F4 replaces the held deadlock analysis.

## 6. Open points

- Which method-level designs pilot route 2: an fw-hdl static-subset proc, or a
  restated slice of `src/behav` (e.g. `axi4_to_mem` with a bounded memory).
- Model checker for route 2: pono (BTOR2, BMC + k-induction + IC3) vs SMT via
  yosys-smtbmc's solver interface; both sit behind one engine adapter.
- Where the rule IR front end lives: fw-hdl (with the proc front end) or `fw_proto`
  (moving to fw-hdl anyway, D2).
- Bounded-response form for liveness (gap 10), needed before F2 can claim liveness.
