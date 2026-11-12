# Architecture

This page explains how the kit fits together. The design and its reasons are
in [design-new-style.md](design-new-style.md). Spec references are to the
AMBA AXI Protocol Specification, IHI0022H.

## A core, and what is derived from it

Only the core specification (`src/core`) is written by hand for the protocol
layer. It is two packages:
- `fw_proto_axi4_defs_pkg`, synthesizable and class-free: `axi4_param_t` (address,
  data, ID and USER widths, `HAS_QOS`/`HAS_REGION`; a width of 0 means the
  signal is absent), the BURST/SIZE/RESP encodings, the stream widths
  `axi4_{ax,wd,b,r}_bits`, and the burst arithmetic of A3.4 and A7.2.4 (beat
  addresses, byte lanes, wrap boundaries, 4 KB crossing, burst and exclusive
  legality). The RTL (checker, slice, generated transactor cores) uses it.
- `fw_proto_axi4_core_pkg`: the channel payloads, the port bundle
  `axi4_bundle` (AW, W, AR forward; B, R back, each a `fw_rv_ch`), and the
  transaction-level APIs: the burst API (`axi4_burst_req_if` with
  `write_burst`/`read_burst`, `axi4_burst_rsp_if` with
  `write_resp`/`read_resp`) and the convenience `axi4_xact_if`.

The declarations carry `(* fw_* *)` attributes. `dfm run woven` (sv-weave with
the `fw_proto` weavers, `src/weave/sv-weave.yaml`) derives
`fw_proto_axi4_core_pkg_woven`:
- for each API, and for the channel APIs `axi4_req_if` (AW, W, AR) and
  `axi4_rsp_if` (B, R) taken from the bundle: `_base`, `_listener`
  (`<m>_pre`/`<m>_post`), `_listener_base`, `_listener_fanout`, `_proxy` and
  `_imp`;
- from the bundle: the per-channel inboxes, the field table `axi4_sp`, the
  typed role ports `axi4_mgr_sp`/`axi4_sub_sp`, and `axi4_payloads`
  (`<ch>_sprint`, `<ch>_compare`, `<ch>_mask`).

`dfm run woven-xtor` (`src/weave/sv-weave-xtor.yaml`) also derives the
signal-level transactors `axi4_{mgr,sub,mon}_xtor` with their interfaces,
built on fw-hdl's ready/valid kit, and the bridges between them and the
channel APIs. An image uses `woven` or `woven-xtor`, not both; this is why
`behav` and `rules` also come in `-xtor` forms (`src/flow.yaml`).

The protocol-agnostic part (the SV runtime `fw_proto_pkg`, the rule library,
the extern-component and abstractor support, the weavers) is in `fw_proto/`.
Nothing there names AXI; it is meant to move to fw-hdl.

## The layers

```
  test code
     |  fw_mem_if          axi4_xact_if             axi4_burst_{req,rsp}_if
  axi4_to_mem --> axi4_xact_on_burst --> axi4_burst_blocking --> axi4_mgr_adapter
                                                                    | axi4_req_if / axi4_rsp_if
                                                         L1 link (tlm or xtor view)
                                                                    |
                         axi4_mem_model  <-- burst API --  axi4_sub_adapter
```

**L1, channels.** The manager calls `axi4_req_if` (`aw`, `w`, `ar`) and the
subordinate calls `axi4_rsp_if` (`b`, `r`), one beat per call, in the channel
payload types. Listeners on the proxies see `<ch>_pre` and `<ch>_post` for
each beat.

**Bursts.** `axi4_mgr_adapter` turns burst requests into channel beats and
B/R beats back into burst responses. `axi4_sub_adapter` does the reverse at
the subordinate: it joins each AW with its W beats (W may lead AW, A3.3.1).
The burst API is two-way: a request returns once its beats are accepted, and
responses come back as calls, in order per ID (A5, A6). Only the blocking
shims wait per transaction. The adapters pass payloads through unchanged,
apart from zeroing fields the parameter set leaves off the pins, so a link
with pins and one without deliver the same beats.

**Memory.** `axi4_mem_model` sits behind the burst API as a sparse byte
memory: strobes, narrow and unaligned beats on their byte lanes (A3.4.4), an
exclusive monitor (A7.2), and error ranges answered with SLVERR or DECERR.
`axi4_to_mem` puts fw-hdl's `fw_mem_if` on top of an `axi4_xact_if`.

## Views: tlm and xtor

The L1, L2 and rules suites run in two views; the image picks the view's
`axi4_l1_link` (`tests/env/tlm/`, `tests/env/xtor/`):
- **tlm.** The manager's `axi4_req_if` is a proxy onto the subordinate's
  inbox, and the reverse. Zero time, no pins.
- **xtor.** `axi4_mgr_xtor_bridge` drives the generated manager transactor;
  its pins go through one `axi4_slice` per channel each way to a second pin
  segment and the subordinate transactor. Each pin segment has an
  `axi4_checker` (COUNT_ONLY), and `axi4_mon_xtor` observes the first.
  Transactor knobs (for example random VALID/READY gaps) are set by path:
  `mgr.<ch>.<knob>`, `sub.<ch>.<knob>`.

## Rules and the checker

The AXI4 rules (`src/rules`, on `fw_proto`'s rule library) listen to channel
events, so they attach to any link, transactor monitor or IP abstractor and
report the API event they saw broken. They are attached in every L1/L2 and IP
test. See [rules.md](rules.md).

`axi4_checker #(P, MAX_OUT, ASSUME_MGR, ASSUME_SUB, COUNT_ONLY)` is a passive,
synthesizable pin checker on the defs package, kept as the reference until
formal properties are generated (plan A4). Its rules are immediate assertions
on registered history, so the same file runs in Verilator and, through sv2v,
in SymbiYosys. `ASSUME_MGR`/`ASSUME_SUB` turn one side's rules into
assumptions; `COUNT_ONLY` (simulation) counts failures in `n_err_m`/`n_err_s`.

| Rule | Ref |
|---|---|
| VALIDs LOW in reset and in the first cycle after it | A3.1.2 |
| VALID, once HIGH, stays HIGH with a stable payload until READY | A3.2.1 |
| Burst legality: WRAP length 2/4/8/16, FIXED/WRAP at most 16 beats, size no wider than the bus, no 4 KB crossing | A3.4.1 |
| Exclusive access: size, length and alignment | A7.2.4 |
| WLAST on, and only on, beat AWLEN+1 of each burst, in AW order (W may lead AW) | A3.4.1, A2.3 |
| WSTRB HIGH only on the active byte lanes of the beat | A3.4.4 |
| B only for a write whose AW and last W beat are done, with a matching BID | A3.3.1, A5 |
| R only for an outstanding read with that RID; RLAST on beat ARLEN+1 for each ID | A5, A3.4.1 |
| EXOKAY only for an exclusive access | A7.2 |
| No X on VALIDs, or on the payload while VALID (simulation only) | A3.2 |

At most MAX_OUT write, read and early write-data bursts are tracked; going
past that is a capacity failure, charged to the manager.

## RTL

`axi4_slice #(W)` is a 2-entry skid buffer with full throughput, registered
VALID and payload, and READY low in reset. The generated transactors' cores
(`axi4_{mgr,sub}_xtor_core`, on fw-hdl's rv cores) are what formal checks back
to back.

## Formal (`tests/formal/flow.yaml`)

| Verb | What |
|---|---|
| `fv-cover` | `axi4_checker_fv.sv`: legal behaviour is reachable with all checker rules assumed (bursts, 2-lane strobes, EXOKAY on B and R), so the rules are not vacuous; and `axi4_fv.sv` with `FV_COVER`, back-to-back reachability |
| `fv` | BMC, depth 16, of `axi4_fv.sv`: the generated manager core through pins to the generated subordinate core, checkers on both user sides and the pins (`fv_b2b.sh`) |
| `fv-prove` | `axi4_slice_fv.sv`: abc pdr proof of the slice (reset, stability, no loss, duplication or reordering, occupancy) |
| `fv-teeth` | `teeth.sh` (mutants of the slice and the checker) and `fv_b2b.sh teeth` (mutants of the generated cores and fw-hdl's rv core): each must fail its formal run |

`tests/formal/run_sby.sh` runs sby directly, for debugging.

## Tests

SVUnit suites (`tests/flow.yaml`), run with `dfm run tests` (all) or
`dfm run tests --tests <suite>`; `smoke` is `types`, `l1`, `rules_pins`. Most
run each case for `P_MIN`, `P_DEF` and `P_WIDE`.

| Suite | Views | Covers |
|---|---|---|
| `types` | — | burst helpers against worked examples of A3.4.1, A3.4.2, A7.2.4 |
| `weave` | — | the derived classes: widths, proxy/listener order, fan-out, imps, channel APIs |
| `bundle` | — | field tables against the AMBA pin lists, role ports, inboxes, sprint/compare |
| `rv_pilot` | — | fw-hdl's ready/valid example with its imp replaced by a generated one |
| `xtor` | — | the generated transactors and bridges back to back, checker at zero |
| `l1` | tlm, xtor | each channel, all channels at once, stalls, every encoding |
| `l2` | tlm, xtor | bursts through the adapters: random, backpressure, concurrent IDs, errors |
| `l2_mem` | tlm, xtor | `fw_mem_if`, strobes, narrow/unaligned, WRAP, FIXED, exclusive, error ranges |
| `rules_teeth` | tlm, xtor | one planted bug per rule; with pins, the checker must agree |
| `rules_pins` | — | scripted pin sequences watched by the checker and by the monitor with the rules |

Also: `dfm run ip` (reference IPs wrapped as extern components,
[reference-ips.md](reference-ips.md)), `dfm run lint-rtl` (Verilator, zero
findings: `axi4_lint_rtl` for the checker and slice, `lint-xtor` for the
generated transactors, behaviour and rules), `pytest fw_proto/python/tests`
(weaver goldens), and `tests/teeth/behav_teeth.py` (mutants of `src/behav`).
`tests` and `smoke` exit nonzero when any test fails.
