# AXI4 rules

The AXI4 contract (brief §5) as rules: listeners on the channel APIs whose bodies say
what must hold (plan P7, design §3.5, `abstractors.md` §4a). This note covers the
vocabulary, the rules, where they are attached, their teeth, and the vocabulary gaps
found (brief Q3).

## The vocabulary (`fw_proto/src`)

A rule extends a protocol's rule base, which extends `fw_rule` and implements the
protocol's listener interfaces. Its body may use only:

| Item | What it is |
|---|---|
| `chk(c, msg)` | the immediate check; `msg` names the API event (method, ID, beat) |
| `fw_count` | a counter: `inc()`, `dec()`, `v` |
| `fw_flag` | a flag: `set()`, `clr()`, `v` |
| `fw_value #(T)` | a bounded register: one value captured from an event, `set(x)`, `v`, `valid` |
| `fw_any #(T)` | a quantified variable: the rule holds for every value; the body only asks `is(x)` |
| pure functions | of the event's arguments and that state (e.g. the burst arithmetic in `fw_proto_axi4_defs_pkg`) |

A rule that needs anything else (queues, plain members) sets `m_free_form`. Free form is
the escape hatch: it runs in simulation, formal treats it as opaque. A free-form rule may
not have quantified variables.

`fw_rv_hold #(T)` is the ready/valid family's signal-level rule for one channel. It is
written in the same vocabulary, as part of a rule.

### How simulation runs a quantified rule

`fw_rule_set` runs one rule, attached in one place. For a rule with `fw_any` variables it
keeps one instance per value seen (`fw_rule_node`):
- An instance with a variable unbound stands for every value not seen yet, so `is(x)`
  is 0 there.
- A twin of it (the probe) takes each event first. When the probe asks `is(x)` for a
  new `x`, the set copies the unbound instance, still in its state before the event,
  binds the copy to `x`, and delivers the same event to it.
- A copy with variables still unbound is a node of its own, so several variables work.
- State is copied through the registered state objects. Each rule also writes a
  one-line `create()`.

`retire()` is a hint for simulation only. It says an instance's key is discharged, for
example a burst that is complete and checked. The instance takes no more events and is
never created again. Retired instances are swept out of the fan-outs from time to time.
In the IP runs each place creates 330 to 480 instances over the whole run, all nine
rules together; most of them are retired once their burst is checked.

## Events: which call counts

The rule base `axi4_rule` maps the listener calls to accepted events:

| Event | From a proxy | From a pin monitor (`pins`) |
|---|---|---|
| `on_aw`, `on_w`, `on_ar` (requests) | `_pre`: the call is made | `_post`: the handshake |
| `on_b`, `on_r` (responses) | `_post` | `_post` |

A response may come inside its request's call (design §3.4). From a proxy a request must
therefore count when the call is made: the B of a zero-delay target arrives before the
last W call returns. On the pins nothing can answer a beat before its handshake, so a
request counts at the handshake. Counting there makes, for example, a B between the last
W's first VALID and its handshake a failure.

## The rules (`src/rules`, `fw_proto_axi4_rules_pkg`)

| Rule | Brief §5 item | Kind | Variables | Binds | `axi4_checker` counterpart |
|---|---|---|---|---|---|
| `resp_match` | R and B only for an outstanding AR/AW, by ID | correspondence | `id` | subordinate | `b_ok`, `r_ok` |
| `r_burst` | R grouping; same-ID read order | grouping, keyed order | `id`, `read` | subordinate | RLAST on beat ARLEN+1 of the oldest read with its ID |
| `w_burst` | W grouping in AW order | grouping, correspondence | `burst` | manager | WLAST on beat AWLEN+1; data ahead of its AW |
| `b_order` | B after the AW and last W; same-ID write order | happens-before, keyed order | `id`, `write` | subordinate | `b_ok` (needs the last W) |
| `burst_legal` | burst legality; exclusive legality | immediate | none | manager | `axi4_burst_legal`, `axi4_excl_legal` |
| `w_lanes` | narrow transfers (brief §4) | immediate, keyed | `burst` | manager | WSTRB lanes |
| `capacity` | outstanding ≤ declared capacity | capacity | none | manager | `MAX_OUT` (a bookkeeping bound there) |
| `exclusive` | EXOKAY pairing | free form (escape hatch) | none | subordinate | EXOKAY only with the lock |
| `rv_hold` | signal level (design §4.1) | per channel, pins only | none | AW/W/AR: manager; B/R: subordinate | A3.2.1 VALID and payload stable |

`axi4_rules #(P)` is the whole set in one place:
- `new(where, pins, max_wr, max_rd)`; `pins` also adds `rv_hold`.
- `req` and `rsp`: the fan-outs to attach.
- `reset()`, `n_fail()`, `n_fail_of(rule)`, `failed()`, `first()`, `set_quiet()`.

A failure prints `[fw_rule] FAIL <time> <where>: <rule>(<key>): <event>`, for example:

```
2435 link: b_order(id=6, write=0): b id=6 (write 0 of this ID): before the last W beat of its write
```

## Where they are attached

The place a rule is attached gives its role: on a proxy or link it is the contract,
on a producer a guarantee, on a consumer a requirement. In simulation the role only
changes the report.

| Test | Where | Events |
|---|---|---|
| `l1`, `l2`, `l2_mem` | the L1 link: `u_link.add_req_listener` / `add_rsp_listener` | the proxies in tlm; segment A's pin monitor in xtor (`at_pins()`) |
| `l2`, `l2_mem` | the direct path: proxies around `isub` (`isub_px`, `mgr_d_px`) | proxies; responses inside the call |
| `axi_ram`, `demofull` | `dut.s_abs`, by path | the abstractor handle's proxies |
| `axi_crossbar` | `dut.s0_abs`, `dut.s1_abs`; `dut.m0_abs`, `dut.m1_abs` with capacity 5/5 | the abstractor handles' proxies |

Attaching by path uses `axi4_observers #(P)`, generated with the abstractors (`abs.py`):
- A test calls `add(path, req, rsp)` before the traffic.
- Each handle registers its proxies under its own path when it is built.
- Whichever comes second joins them, so the order of the time-0 initial blocks does not
  matter.

The first form attached at the handle's `run()`. On `demofull` and the crossbar the
manager's first AW came before that, and the rules then reported its B as having no
write outstanding.

`unused()` names the paths that no handle took, which catches a misspelled path or a
different `P`. `tests/ip/common/ip_axi_rules.svh` wraps this for the IP tests and
reports each place's failures and instance count.

**Capacity** is a declared fact. No test port declares one yet, except the crossbar's
master ports, which carry 5 writes and 5 reads: `M_ISSUE`+1, not `M_ISSUE` (4 by
default). Elsewhere the capacity rule is attached with no limit.

The first declaration was `M_ISSUE`, and it was wrong. Under the D11 mutant
`blk_rd_done_first`, which only makes the test bench keep more reads in flight, the
rule fired on `dut.m1_abs` with a fifth read outstanding. The pins and the crossbar's
own count agree on 5. The cause is in `axi_crossbar_rd.v` (per master port,
`m_ifaces`): `trans_limit` only gates the request to the arbiter, and the arbiter holds
a grant until it is acknowledged. On the edge where one slave port's grant is
acknowledged, the other slave port can be granted while the count is still below
`M_ISSUE`, and that grant then goes ahead whatever the limit says. So with two or more
slave ports reaching a master port the bound is `M_ISSUE`+1; with one it is `M_ISSUE`.
`axi_crossbar_wr.v` has the same shape (the request also waits for the previous W
burst, so it needs WLAST before the AW acknowledge); no write overshoot was seen, but
the bound is the same. The normal crossbar run never saturates a master port, so only
the mutant showed it: a wrongly declared fact caught by the rule it feeds.

## Teeth (`rules_teeth`)

This is the port of the old `chk_teeth` suite (deleted in P8). Each case plants one bug in traffic over the L1 link
(both views). The bug comes from a misbehaving subordinate on `axi4_req_if_base`
(`tsub`) or from a manager calling the link itself. Each case requires three things:
- exactly its rule fires;
- its first report names the API event;
- in the xtor view, the link's `axi4_checker` (segment A) counts failures on the side
  the rule binds, and none on the other.

| Case | Bug | Rule | Checker |
|---|---|---|---|
| `legal` | none: IDs, W ahead of AW, narrow, FIXED, WRAP, exclusive | none | none |
| `b_twice` | two Bs for one write | `resp_match` | subordinate |
| `r_spurious` | an R beat with no read outstanding | `resp_match` | subordinate |
| `rlast_early` | RLAST on beat 2 of 4 | `r_burst` | subordinate |
| `r_order` | two reads of one ID answered in the other order | `r_burst` | subordinate |
| `b_early` | B after the AW, before the data | `b_order` | subordinate |
| `exokay` | EXOKAY for a normal write | `exclusive` | subordinate |
| `wlast_early` | WLAST on beat 2 of 4 | `w_burst` | manager |
| `w_ahead_long` | 3 beats ahead of an AW of 2 | `w_burst` | manager |
| `burst_4k` | INCR across 4KB | `burst_legal` | manager |
| `wrap_len` | WRAP of 3 beats | `burst_legal` | manager |
| `excl_illegal` | exclusive access of 32 beats | `burst_legal` | manager |
| `wstrb_lane` | a strobe outside the beat's lanes | `w_lanes` | manager |
| `capacity` | 33 reads outstanding (capacity 32 = the checker's `MAX_OUT`) | `capacity` | manager (and the subordinate side, see below) |
| `rv_legal`, `rv_drop`, `rv_payload` | pin-monitor events fed directly | none / `rv_hold` / `rv_hold` | not run |

In the `capacity` case the checker also counts on the subordinate side. Its `MAX_OUT`
is a bound on its own bookkeeping: past it, it loses track of the extra read and then
flags that read's R beat. The rule has no such bound.

The transactors always hold VALID, so the signal-level faults cannot come through
the link. They are covered on real pins by the second suite.

## Teeth on pins (`rules_pins`)

This suite takes the old `chk_teeth` suite's 13 scripted pin sequences, each legal but for one fault,
and watches them twice:
- by `axi4_checker`, which must count on the side the fault binds, as in `chk_teeth`;
- by the generated pin monitor (`axi4_mon_xtor`) with the rules on its events, which
  must fire exactly the fault's rule.

| Case | Rule | Checker |
|---|---|---|
| `legal` | none | none |
| `valid_in_reset` | none (no event exists for it: gap 8) | manager |
| `valid_retract` | `rv_hold` (`aw: VALID dropped`) | manager |
| `payload_change` | `rv_hold` (`ar: payload changed`) | manager |
| `burst_4k`, `wrap_len` | `burst_legal` | manager |
| `wlast_early` | `w_burst` | manager |
| `wstrb_lane` | `w_lanes` | manager |
| `b_before_wlast` | `b_order` | subordinate |
| `bid_mismatch`, `r_without_ar` | `resp_match` | subordinate |
| `rlast_early` | `r_burst` | subordinate |
| `exokay_not_exclusive` | `exclusive` | subordinate |

The verdicts agree on every case but `valid_in_reset`. Here `valid_retract` raises VALID
again after the retraction: a retraction becomes an event only when VALID comes back
(gap 9).

## Vocabulary gaps found (brief Q3)

1. **Which call accepts a request differs by source.** It is the pre on a proxy and the
   post on pins. The rule base hides this (`m_pins`), but formal and the other engines
   must be told which one the events come from.
2. **Bounded registers are needed,** not only counters and flags. They hold the length
   or address of the burst a quantified index picks (`fw_value`). `abstractors.md` §4a
   names them; the prototype library had none.
3. **Pure functions of the event are needed:** the burst arithmetic for legality and
   lanes. They come from the synthesizable `defs` package, so formal can use them.
4. **Several variables per rule:** an ID plus an index within that ID (`r_burst`,
   `b_order`).
5. **Same-ID order is visible only through lengths and data.** Two reads of one ID with
   equal lengths, answered in the wrong order, look legal at the protocol level. Two
   writes of one ID are told apart only by the ordering of their B against their data.
   The data-integrity rule (A5) is what catches the rest.
6. **Capacity needs a declared fact,** and nothing declares one yet. Today it is a
   constructor argument at the attachment. The brief §4 "API's declared facts" are
   still to be designed.
7. **The exclusive rule could be restricted.** It is free form here, as the escape-hatch
   demonstration: per-ID queues of AxLOCK. It could be written like `b_order` (ID,
   index, a captured lock bit). The pairing of an exclusive write with an earlier
   exclusive read (A7.2.2) is not checked.
8. **Reset and X are not events.** VALID low during reset (A3.1.2) and no X on controls
   cannot be stated over pre/post. They stay with the pin checker, or with the rv
   family as properties on the struct port.
9. **A VALID retraction must be reported as an event.** fw-hdl's rv monitor used to keep
   a transfer pending through a drop of VALID, so a retraction with the payload
   unchanged produced no event. It now clears the pending mark (plan §8), and the next
   VALID is a new first: two pres without a post, which `rv_hold` reports. A
   retraction that VALID never comes back from still produces no event: nothing marks
   the drop itself.
10. **Liveness is not expressible:** every request answered, every W burst eventually
    complete. In simulation the envs' watchdogs and idle checks cover it. Formal would
    need a bounded-response form.
11. **Which side a rule binds** (for assume/assert) is recorded only in its comment and
    the table above. A formal harness needs it as data on the rule.
12. **`retire()` is a simulation hint** with no formal meaning. It has to be safe: it may
    drop only checks that can no longer fire.

## Candidates for generation

These are mechanical from the bundle, but hand-written for now:
- `axi4_rule`: fwd channels are requests and rev channels responses, mapped to pre or
  post.
- `axi4_rule_node`: the fan-outs of the channel listeners.
- `axi4_rules`'s attach plumbing.

`axi4_observers` is already generated.
