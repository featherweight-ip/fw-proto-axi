# Architecture

This page explains how the kit fits together. Spec references are to the AMBA
AXI Protocol Specification, IHI0022H.

## The layers

```
  test code
     |  read/write (fw_mem_if)            xact(axi4_xact)
  axi4_to_mem  ------------------>  axi4_mgr_adapter               L2: one burst per call
                                         | socket (axi4_req_if out, axi4_rsp_if in)
                                    L1 link: one beat per call      L1
                                         | mirror
                                    axi4_sub_adapter --xact--> axi4_mem_model / any axi4_xact_if
```

All the arrows are fw-hdl binds. User code holds API handles only.

**Types.** `axi4_types_pkg` holds `axi4_param_t` (ADDR_W, DATA_W, ID_W, the
five USER widths; a width of 0 means the signal is absent), the BURST, SIZE
and RESP enums, one beat struct per channel (`axi4_addr_beat_t` serves both
AW and AR), and the burst arithmetic of A3.4: `axi4_beat_addr`,
`axi4_beat_lower_lane`/`upper_lane`, `axi4_wrap_boundary`, `axi4_crosses_4k`,
`axi4_burst_legal`, `axi4_excl_legal`.

**L1, beats.** `axi4_req_if` (tasks `aw`, `w`, `ar`, from manager to
subordinate) and `axi4_rsp_if` (`b`, `r`). The manager holds
`axi4_mgr_socket_t = fw_socket #(axi4_req_if, axi4_rsp_if)`, and the
subordinate holds the matching `axi4_sub_mirror_t`. A single `connect()` wires
both directions. A socket accepts only a mirror of the same pair, so a wrong
bind is a compile error. `axi4_cfg` carries the parameters and masks beats
to the configured widths. In pin views, an L1 receiver gets the masked beat.
`axi4_l1_mgr_ep`/`axi4_l1_sub_ep` queue what they receive in per-channel
inboxes.

**L2, bursts.** `axi4_xact` holds one transaction: the request fields, the
data, strobes and WUSER for each beat, and the response (B, or RRESP/RUSER for
each beat, plus the worst response). `axi4_xact_if::xact()` blocks until the
response is filled in.
- `axi4_mgr_adapter` exports `xact` over a socket and accepts concurrent
  callers. It sends each write's AW and W beats together, and routes B and R
  by ID in FIFO order: same ID in order, different IDs may reorder (A5, A6).
- `axi4_sub_adapter` sits on a mirror and joins each AW with its W beats (W
  may lead AW, A3.3.1). It calls its `tgt` port and returns the B or R beats.
  Its `max_delay` knob randomizes completion order across IDs and delays
  between beats.

**Memory.** `axi4_mem_model` implements `axi4_xact_if` as a sparse byte
memory. It supports:
- strobes, and narrow and unaligned beats on their byte lanes (A3.4.4);
- an exclusive monitor (A7.2): a reservation per ID, EXOKAY on an exclusive
  read, and on an exclusive write that succeeds. A failed exclusive write
  gets OKAY and writes nothing;
- error ranges answered with SLVERR or DECERR.

`axi4_to_mem #(ADDR, DATA, STRB)` puts fw-hdl's `fw_mem_if` on top of an
`xact` port.

**Monitor.** `axi4_mon_msg` holds one record per handshake per channel.
`axi4_mon_fanout` sends each record to subscribers such as
`axi4_mon_recorder`, which counts and selects records.

## Views: tlm and xtor

Every suite runs in two views, selected by the harness module it is built
with (`tests/env/tlm/`, `tests/env/xtor/`):

- **tlm.** The manager socket binds straight to the subordinate mirror,
  with no pins.
- **xtor.** Each endpoint binds to a bridge (`fw_proto_axi4_xtor_pkg`),
  which drives a signal-level transactor:
  - `axi4_mgr_xtor` and `axi4_sub_xtor` each contain an `axi4_xtor_if` and a
    channel core, joined on real pins;
  - an `axi4_checker` (asserting) and an `axi4_mon_xtor` sit on those pins.

  The bridges pack beats into the cores' streams with `axi4_wire`.
  `axi4_xtor_if.max_gap[ch]` adds random VALID/READY stalls, set from tests
  with `env.set_backpressure(n)`, which does nothing in tlm. The `l1_basic`
  xtor harness leaves out the checker, because its random beat streams are
  not protocol-consistent.

## Synthesizable cores

`axi4_slice #(W)` is a 2-entry skid buffer with full throughput, registered
VALID and payload, and READY low in reset. `axi4_mgr_core` and
`axi4_sub_core` put one slice on each channel. They connect AXI pins to
packed user streams, with fields MSB first in the checker's pin order:
- AW/AR {id, addr, len, size, burst, lock, cache, prot, qos, region, user}
- W {data, strb, last, user}
- B {id, resp, user}
- R {id, data, resp, last, user}

Stream widths come from `axi4_ax_bits`, `axi4_wd_bits`, `axi4_b_bits` and
`axi4_r_bits`. The cores do not reorder anything: protocol on the user side is
the user's job.

## The pin checker

`axi4_checker #(P, MAX_OUT, ASSUME_MGR, ASSUME_SUB, COUNT_ONLY)` is passive.
Its ports use the lowercase pin names, so `.*` connects it. The rules are
immediate assertions on registered history, so the same file runs in
Verilator and in SymbiYosys (through sv2v). `ASSUME_MGR`/`ASSUME_SUB` turn
one side's rules into assumptions for a formal harness. `COUNT_ONLY`
(simulation only) counts failures in `n_err_m`/`n_err_s` instead of
asserting.

| Rule | Ref |
|---|---|
| VALIDs LOW in reset and in the first cycle after it | A3.1.2 |
| VALID, once HIGH, stays HIGH with a stable payload until READY | A3.2.1 |
| Burst legality: WRAP length 2/4/8/16, FIXED/WRAP at most 16 beats, size no wider than the bus, no 4 KB crossing | A3.4.1 |
| Exclusive access: size, length and alignment | A7.2.4 |
| WLAST on, and only on, beat AWLEN+1 of each burst, in AW order (W may lead AW) | A3.4.1, A2.3 |
| WSTRB HIGH only on the active byte lanes of the beat (checked once the burst's AW is known) | A3.4.4 |
| B only for a write whose AW and last W beat are done, with a matching BID | A3.3.1, A5 |
| R only for an outstanding read with that RID; RLAST on beat ARLEN+1 for each ID | A5, A3.4.1 |
| EXOKAY only for an exclusive access | A7.2 |
| No X on VALIDs, or on the payload while VALID (simulation only) | A3.2 |

Bookkeeping is bounded. At most MAX_OUT write bursts, MAX_OUT read bursts,
and MAX_OUT write-data bursts ahead of their AW are tracked. Going past that
is a capacity failure, charged to the manager.

## Formal (`tests/formal/flow.yaml`)

Sources go through `sv2v --exclude=Assert -DFORMAL`, then into sby/yosys.

| Verb | What |
|---|---|
| `fv-cover` | `axi4_checker_fv.sv`: legal behaviour is reachable with all checker rules assumed, so the rules are not vacuous. Covers include bursts, 2-lane strobes, and EXOKAY on B and R. `axi4_fv.sv` with `FV_COVER`: back-to-back reachability (bursts, reorder across IDs, full slices) |
| `fv` | BMC, depth 16, of `axi4_fv.sv`. The manager core connects through pins to the subordinate core. Checkers assume protocol on both user sides and assert it on the pins and on the subordinate's user side |
| `fv-prove` | `axi4_slice_fv.sv`: abc pdr proof of the slice (reset, stability, no loss, duplication or reordering, occupancy). The back-to-back properties are BMC-only, because pdr did not converge |
| `fv-teeth` | `teeth.sh`: mutants of the slice, the cores and the checker, each of which must make its formal run fail |

`tests/formal/run_sby.sh` runs sby directly, for debugging (usage is in its
header).

## Test suites (`tests/flow.yaml`)

| Suite | Views | Covers |
|---|---|---|
| `types` | — | burst arithmetic and legality helpers |
| `chk_teeth` | — | a standalone checker (`COUNT_ONLY`) driven on its pins: one legal case and 12 planted faults, each of which must be flagged |
| `l1_basic` | tlm, xtor | each channel in order, all channels at once, one channel stalled while the others flow, every encoding, masking, wire round trip |
| `l2_basic` | tlm, xtor | single and random bursts, backpressure, concurrent IDs with out-of-order completion, error responses, monitor counts |
| `l2_mem` | tlm, xtor | `fw_mem_if` access, strobes, narrow/unaligned INCR, WRAP, FIXED, random readback, exclusive access, error ranges, concurrent `fw_mem_if` users |

Run a single suite with `dfm run tests --tests <suite>`. `tests` and `smoke`
exit nonzero when any test fails. `dfm run suites.<suite>` on its own does not
gate on the result.
