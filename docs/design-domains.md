# Domains in fw-hdl: reset as a domain kind, derived resets, crossing analysis

Status: **design, 2026-11-13; being implemented** (P11, [plan-new-style.md](plan-new-style.md)
§13, which tracks the steps of §10). Revised the same day for U7 (behavior follows the reset
domain, §4.5); where the implementation differs from the first draft, the text says so
("As built").

## 1. Decisions

User decisions (2026-11-13):

| # | Decision |
|---|---|
| U1 | Clock and reset are tracked as domains. At the signal level, transactors bridge pins to and from a domain. |
| U2 | Every interface (port, export, socket) is associated with a domain. By default an interface, and a sub-component, takes its parent's clock and reset domain. |
| U3 | Domains have kinds: clock, reset, later power. Reset is added now, with the same shape as clock. Power is designed for, not built. |
| U4 | A crossing is logic that works with two different domains: a binding whose two ends are in different domains, or a component whose interfaces are in different domains. |
| U5 | Special reset domains are needed: controlled by a register bit, combined, synchronized. |
| U6 | API classes carry no clock or reset (P12, plan §14). Generated transactors take `clock` and an active-high `reset` from their domain. A device's own pin names and polarity go in its pin map. |
| U7 | (2026-11-13, later) Behavior is tied to the reset domain. By default a component's `run()` starts when its reset deasserts; on assertion `run()` and every process it forked are cancelled, and it starts again at the next deassertion. Synchronous-level code (`step()`) is not gated: it uses `in_reset()`, as an always block uses its reset branch. Overrides Q2's first answer. |

Design decisions taken here (each argued where it is made):

| # | Decision | § |
|---|---|---|
| D1 | One base API `fw_domain_if`; `fw_clock_domain_if` and the new `fw_reset_domain_if` extend it | 3 |
| D2 | `clock` and `reset` are `fw_domain_port`s on every component. `reset` is inherited only when the parent's is bound (the `dbg` rule), so trees whose root seats no reset keep working | 3, 4 |
| D3 | The root reset domain keeps today's `fw_root` semantics: reset tears the tree down, so live class code never sees the root domain asserted | 4 |
| D4 | (revised for U7) Every reset domain drives the run lifecycle of the components in it: `run()` starts on deassertion and is killed, with its descendants, on assertion; `reset_state()` (default: nothing) restores state. `step()` is not gated. The root domain keeps D3's teardown, which is the same lifecycle plus fresh state | 4.5, 5 |
| D5 | First implementation: register-bit and combined reset domains. Synchronized reset domain: API designed, implementation deferred | 5 |
| D6 | Crossings are found by one walk over the bound endpoints after connect, in simulation. Python flows reject what they cannot lower | 7 |
| D7 | Crossing elements declare themselves (`is_crossing(kind)`) and put their endpoints in different domains with `set_domain()`. Other crossings are reported unless waived with a reason | 6, 7 |
| D8 | The emitted sim top (fw_proto emitter) has nets for the root domains only; any other domain on an RTL boundary is an error for now | 9 |

## 2. Today's clock-domain model

- `fw_clock_domain_if` (`src/fw_clock_domain_if.svh`): `tick(n)` and `root_ticks(n)`.
  Latency-insensitive: in untimed code `tick(n)` is a lower bound.
- Every `fw_component` has `fw_port #(fw_clock_domain_if) clock`, made in the constructor.
  `do_connect()` runs the parent's `connect()` first, then binds every child whose `clock` is
  unbound to the parent's `clock`, then recurses. A parent overrides a child's domain in
  `connect()`.
- Root: `fw_root` instantiates `fw_clock_xtor_if u_clk(.clock, .reset)`. On each reset
  release it makes a new tree, makes an `fw_clock_xtor_bridge` over `u_clk` and binds
  `root.clock` to it. On reset it kills the tree (`root_restart` test). The period variant is
  `fw_clock_period_xtor_bridge` (a `#` delay, no clock pin).
- Derived: `fw_clock_domain` (an export that is its own imp, with an inner parentless port
  `src`) divides its source by `div`. `div = 1` is a named pass-through.
- A second, unrelated clock is possible today: `` `fw_root_bind_port(child.clock, u_clk2,
  fw_clock_xtor_bridge) `` binds a subtree to another clock pin. Nothing reports it.
- Reset has no domain. Components never see reset: the tree does not exist while `fw_root`'s
  reset is high. Transactor cores (`fw_rv_*_xtor_core`) take a `reset` pin (active high)
  and hold valid low in reset.
- Python front end: `fe/elab/entry.py` (native lowering) and `fe/elab/hier.py` (Partition's
  tree) repeat `fw_root`'s seating of `root.clock` through the interpreter.
  `fe/elab/structure.py` maps `fw_root`'s `clock`/`reset` connections to the design's single
  clock and reset (a non-signal reset expression such as `!rst_n` becomes a `_reset` net) and
  checks every RTL block uses them. All lowering is single-clock, single-reset. A divided
  domain lowers to more cycles on the same clock, which is correct because untimed ticks are
  lower bounds.
- Already present elsewhere: Integrate's island checks (`islands.md` §The checks) are
  netlist checks on registered boundaries, and the island exception kinds already include
  `cdc`. The bind map (`fw_component::bind_map_rows`) walks every component's
  `fw_dbg_bindable`s, but sees endpoints only as names (provider is a string), and sockets
  hide their inner port and export. Nothing in fw-hdl checks crossings today.

## 3. The common domain shape

Every kind has the same five parts:

| Part | Clock (today, adapted) | Reset (new) | Power (later) |
|---|---|---|---|
| API (extends `fw_domain_if`) | `fw_clock_domain_if`: `tick`, `root_ticks` | `fw_reset_domain_if`: `in_reset`, `wait_assert`, `wait_deassert`, `is_async`, `sync_clock` | `fw_power_domain_if`: `is_on`, `wait_on`, `wait_off` |
| Component port, inherited | `fw_clock_port clock` | `fw_reset_port reset` | `fw_power_port power` |
| Root bridge (pins → domain) | `fw_clock_xtor_bridge` over `fw_clock_xtor_if` | `fw_reset_xtor_bridge` over `fw_reset_xtor_if` | from a power-control pin |
| Derived domains | `fw_clock_domain` (divider) | `fw_reg_reset_domain`, `fw_reset_combine`, (`fw_reset_sync_domain`, deferred) | switched domain |
| Crossing elements | synchronizer, async FIFO (deferred) | reset synchronizer = `fw_reset_sync_domain` (deferred) | isolation, level shifter, retention |

### 3.1 `fw_domain_if` (new, `src/fw_domain_if.svh`)

```systemverilog
typedef enum { FW_DOMAIN_CLOCK, FW_DOMAIN_RESET } fw_domain_kind_e;   // FW_DOMAIN_POWER later
typedef enum { FW_DOMAIN_SAME, FW_DOMAIN_RELATED, FW_DOMAIN_UNRELATED } fw_domain_rel_e;

interface class fw_domain_if;
    pure virtual function fw_domain_kind_e domain_kind();
    pure virtual function string           domain_name();    // full path of the domain object
    pure virtual function int              domain_nsrc();    // 0 for a root domain
    pure virtual function fw_domain_if     domain_src(int i);
    // The domain this one behaves as: itself, or for a pass-through (a divide-by-1
    // clock domain, a one-source combine) its source's domain_equiv().
    pure virtual function fw_domain_if     domain_equiv();
endclass
```

`fw_clock_domain_if` becomes `interface class fw_clock_domain_if extends fw_domain_if`.
Implementers add the five methods: `fw_clock_domain` (one source, `src`; equiv is the
source's when `div == 1`), `fw_clock_xtor_bridge` and `fw_clock_period_xtor_bridge`
(roots). The three `fake_clock` classes in `tests/dbg_{reg,struct,sched}` gain them too.

Relation of two domains of one kind (`fw_domains::relate(a, b)`, a static function in
`src/fw_domains.svh`):
- SAME: `a.domain_equiv() == b.domain_equiv()`;
- RELATED: their root sets (sources followed to `domain_nsrc() == 0`) intersect;
- UNRELATED: otherwise.

For clocks, RELATED means rational: both divide one root clock, so they share edges. For
resets, RELATED means one is built from the other (or both from a common one).

### 3.2 The domain port (new, `src/fw_domain_port.svh`)

```systemverilog
interface class fw_domain_ref;                    // the kind-free face of a domain port
    pure virtual function fw_domain_kind_e ref_kind();
    pure virtual function fw_domain_if     ref_domain();   // null while unbound
endclass

class fw_domain_port #(type T = fw_domain_if, fw_domain_kind_e K = FW_DOMAIN_CLOCK)
        extends fw_port #(T) implements fw_domain_ref;
    function new(string name = "", fw_component parent = null);
    virtual function fw_domain_kind_e ref_kind();   return K;  endfunction
    virtual function fw_domain_if     ref_domain(); return is_connected() ? get_if() : null; endfunction
endclass

typedef fw_domain_port #(fw_clock_domain_if, FW_DOMAIN_CLOCK) fw_clock_port;
typedef fw_domain_port #(fw_reset_domain_if, FW_DOMAIN_RESET) fw_reset_port;
```

`fw_component::clock` is retyped `fw_clock_port`. Being a subclass of
`fw_port #(fw_clock_domain_if)`, every existing use (`clock.connect`, `clock.t.tick`,
`is_connected`) still compiles. The domain ports are marked ambient (§3.3), as `dbg` is,
so neither the bind-map consumers nor the crossing walk treat them as data bindings.

`fw_component` gains:

```systemverilog
function fw_domain_ref domain(fw_domain_kind_e k);   // this component's port of kind k
virtual function bit   is_crossing(fw_domain_kind_e k); return 0; endfunction   // §6
function void          waive_crossing(string ep, fw_domain_kind_e k, string reason); // §7
```

### 3.3 Endpoint ends (extend `src/fw_endpoint.svh`)

The crossing walk needs, for each endpoint, its owning component and what it is bound to,
as objects rather than names. `fw_endpoint` is already the untyped base class of every
port and export, so the walk uses it and needs no `$cast` (Verilator cannot downcast an
interface-class handle; see the note in `fw_component.svh` on `dbg.t`).

| Added to `fw_endpoint` | Port | Export |
|---|---|---|
| `virtual function fw_component ep_owner()` | `m_parent` | `m_parent` |
| `virtual function fw_endpoint ep_next()` | `m_provider` (upcast) | `m_fwd`, or null when it holds an imp |
| `virtual function bit ep_is_port()` | 1 | 0 |
| `bit m_ambient` + `set_ambient()` | set for `clock`, `reset`, `dbg` | set on domain exports |
| `fw_domain_ref m_dom[fw_domain_kind_e]` + `set_domain(fw_domain_ref d)` | explicit association (§6) | same |
| `function fw_domain_ref ep_domain(fw_domain_kind_e k)` | `m_dom[k]` if set, else `ep_owner().domain(k)` | same |

`fw_port`/`fw_export` constructors also call `parent.add_endpoint(this)` (new
`fw_component::m_eps[$]`). Sockets do not remove these entries (they only edit `m_bind`),
so the walk sees a socket's inner port and export. `fw_socket`/`fw_mirror` get a
`set_domain(d)` that sets both.

## 4. The reset domain

### 4.1 API (new, `src/fw_reset_domain_if.svh`)

```systemverilog
(* fw_latency_insensitive *)
interface class fw_reset_domain_if extends fw_domain_if;
    pure virtual function bit  in_reset();       // level, readable at any time
    pure virtual task          wait_assert();    // returns at once if in reset
    pure virtual task          wait_deassert();  // returns at once if not in reset
    pure virtual function bit  is_async();       // assertion is asynchronous to sync_clock()
    pure virtual function fw_clock_domain_if sync_clock();  // deassertion is aligned to it; null: none
endclass
```

Semantics:
- `in_reset()` is a pure read (of a pin, a register bit, or other domains). It lowers to
  logic (§8).
- The waits return at the first tick of `sync_clock()` at which the condition holds (a
  tick loop: `while (in_reset()) sync_clock().tick(1);`), or at once if it already holds.
  As with `tick()`, exact in timed code and a lower bound in untimed code. A domain with no
  `sync_clock()` waits on its sources' events (root bridge: the vif).
- Sync vs async: every reset in fw-hdl deasserts synchronously to its `sync_clock()`.
  `is_async()` says whether assertion may happen between edges (the root reset: yes,
  `fw_root` is `posedge clock or posedge reset`). A component cannot observe the difference
  in the class model, which samples at ticks. It matters to RTL lowering and to the
  crossing check (§7.4).

### 4.2 The `reset` port and inheritance

`fw_component::new` makes `reset = new("reset", this); reset.set_ambient();` next to
`clock`. In `do_connect()`, step 2 becomes:

```systemverilog
if ($cast(c, m_elab[i])) begin
    if (!c.clock.is_connected()) c.clock.connect(this.clock);
    if (!c.reset.is_connected() && this.reset.is_connected()) c.reset.connect(this.reset);
end
```

Unlike `clock`, an unbound reset is legal: it means "never in reset". This is the `dbg`
rule, and it is what keeps every root that seats only a clock working (`xls_harness.py`,
the `dbg_*` benches, `comp_api.py` harnesses, user code). Helpers on `fw_component`:

```systemverilog
function bit in_reset();  return reset.is_connected() ? reset.t.in_reset() : 0; endfunction
task wait_reset_deassert(); if (reset.is_connected()) reset.t.wait_deassert(); endtask
task wait_reset_assert();   if (reset.is_connected()) reset.t.wait_assert(); else @(m_never); endtask
```

A parent overrides a child's reset in `connect()` (`child.reset.connect(dom)`), exactly as
for clock.

### 4.3 Root bridge

- `src/fw_reset_xtor_if.sv`: `interface fw_reset_xtor_if(input clock, input reset)`,
  `reset` active high; `function bit in_reset()`, `task wait_assert()` (`@(posedge reset)`
  unless already high), `task wait_deassert()` (`@(posedge clock)` until low). No
  parameters, so `virtual fw_reset_xtor_if` stays one type (the reason
  `fw_clock_period_xtor` puts its parameter in a wrapper module).
- `src/fw_reset_xtor_bridge.svh`: `class fw_reset_xtor_bridge extends fw_export
  #(fw_reset_domain_if) implements fw_reset_domain_if`; `new(name, parent, vif)`; an inner
  parentless `fw_port #(fw_clock_domain_if) clk` that `sync_clock()` returns;
  `is_async() = 1`; a root (`domain_nsrc() = 0`).
- `fw_root`: adds `fw_reset_xtor_if u_rst(.clock(clock), .reset(reset));` and, next to the
  clock seating: `rst_dom = new("reset", root, u_rst); rst_dom.clk.connect(clk_dom);
  root.reset.connect(rst_dom);`.
- Polarity: `fw_root`'s `reset` is active high, and stays so. An active-low pin is
  inverted where it enters the root: `` `fw_root_begin(top, u_root, aclk, !aresetn) ``.
  `structure.py` already turns such an expression into the design reset. A second root
  reset over other pins is `fw_reset_xtor_if u(.clock(c2), .reset(!rst2_n))` plus a bridge,
  bound like a second clock. So polarity is resolved once, at the edge, and nothing inside
  the tree has a polarity.

### 4.4 Relation to the clock domain, and what the root domain means

Because reset tears the tree down (D3), live class code never sees the root reset domain
asserted: its `in_reset()` is 0 whenever anything runs, and `wait_assert()` never returns
before the tree is killed. This matches the RTL, where logic held in reset does not run.
The root domain still matters:
- it is the source of derived domains (§5), so `soft = root OR bit` is expressible;
- its `sync_clock()` (the root clock) is what the crossing check compares a component's
  clock against (§7.4);
- it names the reset net that transactors and RTL blocks get (§9);
- it is the reset formal assumes in cycle 0 (§8).

A "warm" mode, where the tree persists through root reset and components observe it, was
open question Q1; it is not built (§11).

### 4.5 Behavior follows the reset domain (U7)

The run lifecycle of a component is driven by its reset domain:

1. wait until the domain is out of reset (`wait_reset_deassert()`);
2. fork every registered `run()`;
3. wait until the domain asserts (`wait_reset_assert()`);
4. kill each `run()` process and everything it forked;
5. call `reset_state()`; go to 1.

`step()` is not part of this. The step driver keeps calling `step()` on every edge, in reset
or not, and a step body reads `in_reset()` itself, as an always block has a reset branch.
This is the synchronous-level style: state that `step()` owns is reset by `step()`.

**Mechanism.** `fw_component::do_run()` forks one supervisor process per component that has
runnables and whose reset domain asserts while the tree lives (below). The supervisor forks
the `run()`s itself and, on assertion, ends them with `disable fork`, which ends every process
the supervisor forked, at any depth (IEEE 1800 §9.6.3). As built, this replaces the first
idea of a `process` handle per `run()` killed with `kill()`: both work (checked on Verilator
5.055 from `packages/verilator` and on xezim, with a two-level probe: a killed process's
forked children stop), but a handle is only known once the forked process has run, so an
assertion in the same time step as the deassertion could miss one; `disable fork` has no such
race and is what `fw_component_root` already uses for teardown. The `reset_domain` test
checks that a grandchild process stops too.

**Which components are supervised.** A component whose reset domain is SAME as its tree
root's (`relate(reset, root.reset) == SAME`), or that has no reset, is not supervised: its
`run()` is forked directly, as before. The root domain's assertion is the environment's
business, and `fw_root` handles it by teardown (D3). Every other bound reset domain, a
derived one or a second root, is supervised. Consequences:
- nothing changes for a tree with only the root reset domain: no extra process, and the
  Python front end (which elaborates `do_run()` through the interpreter) sees the same code;
- a component in a derived domain gets the lifecycle with no code of its own.

**State: `reset_state()`.** Class property initializers do not run again when `run()`
restarts, so a component that keeps state across `run()` restores it in
`virtual function void reset_state()` (default: nothing), which the supervisor calls once per
assertion, after the kill and before the next deassertion. The meaning is the synthesis
one: in the lowered design a process's state and the fields it writes take their reset
values (their elaborated values) while the process's reset is asserted, so `reset_state()`
should put back exactly the initial values of the fields `run()` writes. A component in a
derived domain that does not do so will differ from its RTL after a soft reset. (Lowering
a supervised `run()` is not built yet; §8.)

**The root domain.** Keeping D3's teardown rather than making the root domain one more
supervised domain (considered for U7): teardown gives every field of every component its
initial value with no `reset_state()` at all, which is exactly what the design reset does to
every flop; `root_restart` tests it; and the front ends' contract (`entry.py`, `hier.py`:
build at reset release) is unchanged. From a component's point of view the root domain
behaves as the lifecycle does (`run()` stops on assertion and starts after deassertion), with
fresh state as a bonus. A warm root (Q1) would need every component to implement
`reset_state()`, so it stays out.

**Calls in flight.** A blocking call runs in the caller's process (TLM), so killing the
caller ends the call where it is, inside the callee's code:
- caller and callee in the SAME reset domain: the callee is reset too (its `run()` killed,
  its `reset_state()` called), so whatever the call left half done is cleared;
- across a reset crossing (§7): the callee is not reset. It sees a call that began and never
  ended: a request taken and never answered, a handshake left mid-way, a lock held. This is
  why reset crossings are reported (§7.4), and why the report says so;
- the reverse, a callee reset while a caller from another domain is blocked in it: the
  caller is not killed (its process belongs to its own domain). It stays blocked until the
  callee's code releases it; a callee meant to be reset alone must release its waiters in
  `reset_state()` (fail or drop them) or be reached through a crossing element.

## 5. Derived reset domains

All derived domains are, like `fw_clock_domain`, an export that is its own imp, with
parentless source ports wired in the owner's `connect()`. Source ports are typed
`fw_port #(fw_reset_domain_if)`, so a derived domain is a source for another.

A component in a derived domain is supervised (§4.5): its `run()` starts and stops with the
domain. This is the behavior, not an option.

### 5.1 Register-bit controlled: `fw_reg_reset_domain #(int W = 32)` (first implementation)

`src/fw_reg_reset_domain.svh`:

```systemverilog
class fw_reg_reset_domain #(int W = 32) extends fw_export #(fw_reset_domain_if)
        implements fw_reset_domain_if;
    fw_port #(fw_reset_domain_if) src;     // the reset it extends; normally the owner's
    function new(string name, fw_component parent, fw_reg_base #(W) r, int unsigned bit_idx,
                 bit active_low = 0);
    // in_reset   = src.in_reset() || (r.read_val()[bit_idx] ^ active_low)
    // sync_clock = src.sync_clock();  is_async = src.is_async();  sources: {src}
endclass
```

- It always includes its source: a soft reset is also asserted by the hard reset. That is
  why "combined" is in the first implementation too: this is a combination.
- `active_low = 1` gives an enable bit: the domain is in reset while the bit is 0.
- `in_reset()` reads `read_val()`, the canonical value (a read provider wins), so hardware
  and software agree on it.
- Assumption, documented on the class: the register is written in the clock domain that
  `src` is synchronous to. Software writes arrive as `write_val()` in the bus adapter's
  thread, at a tick of that clock. A register written from another clock needs a
  synchronized domain (§5.3).

Example (a DMA whose channel engine has a soft-reset bit in `ctrl`):

```systemverilog
class dma extends fw_component;
    dma_regs                 regs;
    fw_reg_reset_domain #(32) ch_rst;
    dma_ch                   ch;
    function void build();
        regs   = new("regs", this);
        ch_rst = new("ch_rst", this, regs.ctrl, 3);   // ctrl[3] = 1: channel in reset
        ch     = new("ch", this);
    endfunction
    function void connect();
        ch_rst.src.connect(this.reset);   // root reset OR ctrl[3]
        ch.reset.connect(ch_rst);         // ch's subtree inherits it
    endfunction
endclass

// dma_ch: run() is started when ch_rst deasserts and killed when it asserts (§4.5);
// state run() keeps across a restart is put back in reset_state().
task run();
    forever begin ... end                 // no reset handling of its own
endtask
function void reset_state();
    n_done = 0; q.delete();
endfunction
```

Setting `ctrl[3]` kills `ch`'s `run()` (and whatever it forked) at the next tick of the
domain's clock; clearing it starts `run()` again. `ch`'s `step()`, if it has one, keeps being
called and reads `in_reset()`.

The bindings between `dma` and `ch` are reset crossings (RELATED); §7 reports them unless
waived or routed through a crossing element.

### 5.2 Combined: `fw_reset_combine` (first implementation)

`src/fw_reset_combine.svh`: `new(name, parent, int n)`; `fw_port #(fw_reset_domain_if)
src[]` of size `n`.
- `in_reset` is the OR of the sources. `is_async` is the OR.
- `sync_clock`: the sources' common clock if all are SAME, else null.
- A combine whose sources have unrelated clocks is reported where it is used (§7.4): its
  deassertion is synchronized to nothing. Put a synchronized domain after it.
- `n = 1` is a named pass-through (`domain_equiv()` is the source's), the analogue of a
  divide-by-1 clock domain.

```systemverilog
any = new("any", this, 2);
any.src[0].connect(this.reset);
any.src[1].connect(wdog.rst_out);   // an export of fw_reset_domain_if provided by the watchdog
ip.reset.connect(any);
```

### 5.3 Synchronized deassertion: `fw_reset_sync_domain` (designed, deferred)

```systemverilog
class fw_reset_sync_domain extends fw_export #(fw_reset_domain_if) implements fw_reset_domain_if;
    fw_port #(fw_reset_domain_if) src;
    fw_port #(fw_clock_domain_if) clk;     // the clock deassertion is synchronized to
    function new(string name, fw_component parent, int stages = 2);
    // asserts when src does (is_async = 1); deasserts `stages` ticks of clk after src does;
    // sync_clock = clk; is_crossing(FW_DOMAIN_RESET) = 1 in effect (it is the reset synchronizer)
endclass
```

Deferred because:
- it is only needed where a reset crosses into an unrelated clock, and no design here has a
  second root clock;
- in the class model, without that, its only effect is a delay;
- its RTL is a synchronizer on a second clock, and the Python lowering is single-clock.

The crossing check (§7.4) already reports the case it would fix, so adding it later
changes no rule.

## 6. Associating interfaces with domains

- **Default:** an endpoint is in its owner component's domains (`ep_domain(k)` falls back to
  `ep_owner().domain(k)`), and a component is in its parent's unless overridden. Almost
  every component and interface needs nothing.
- **Override a subtree:** `child.clock.connect(dom)` / `child.reset.connect(dom)` in the
  parent's `connect()`.
- **Explicit association, for a component on a boundary:** the component declares a domain
  port per side and associates each endpoint:

```systemverilog
class my_cdc_fifo #(type T = int) extends fw_component;
    fw_export #(fw_put_if #(T)) put_ex;      // writer side
    fw_export #(fw_get_if #(T)) get_ex;      // reader side
    fw_clock_port wclock, rclock;            // its own domain ports, bound by the parent
    fw_reset_port wreset, rreset;
    function new(string name, fw_component parent);
        super.new(name, parent);
        wclock = new("wclock", this); rclock = new("rclock", this);
        wreset = new("wreset", this); rreset = new("rreset", this);
        put_ex = new("put_ex", this, ...);  get_ex = new("get_ex", this, ...);
        put_ex.set_domain(wclock); put_ex.set_domain(wreset);
        get_ex.set_domain(rclock); get_ex.set_domain(rreset);
    endfunction
    virtual function bit is_crossing(fw_domain_kind_e k); return 1; endfunction
endclass
```

  An extra domain port that the parent leaves unbound inherits nothing (inheritance only
  fills `clock` and `reset`). The check reports an endpoint associated with an unbound
  domain port as an error, unlike an unbound component `reset`, which means "never in
  reset".
- **Root bridges** (pin transactors bound by `` `fw_root_bind_* ``) are owned by the root
  binding component, so they are in the root domains. A bridge to pins clocked by a second
  clock is associated explicitly: `__fw_bridge.set_domain(...)`; a macro variant
  `` `fw_root_bind_port_in(port_ep, if_path, bridge_t, clk_dom, rst_dom) `` does it.
- **Abstractor handles** (this repo's `<proto>_<role>_abs_h`) are ordinary components:
  they inherit the domains of the wrapper they sit in.

## 7. Crossing analysis

### 7.1 What counts as a crossing

For each kind `k` separately:

| Via | Condition |
|---|---|
| binding | a caller-end port and the export it resolves to have `ep_domain(k)` not SAME |
| component | a component with `is_crossing(k) == 0` has data endpoints whose `ep_domain(k)` differ (only possible through `set_domain`) |
| reset sync | a component's reset domain has a `sync_clock()` UNRELATED to the component's clock, or none while `is_async()` (§7.4) |

Not crossings: ambient endpoints (`clock`, `reset`, `dbg`, domain ports and the domain
plumbing between derived domains), an unbound component `reset` (never in reset), and
anything at all inside a declared crossing element.

### 7.2 How it is found: one walk after connect

`src/fw_crossing_check.svh`, `class fw_crossing_check` with
`static function int run(fw_component root, ref fw_crossing found[$])` (returns the error
count), and `src/fw_crossing.svh`, the record (`kind`, `rel`, `sev`, `via`, `from`,
`from_dom`, `to`, `to_dom`, `waiver`).

1. Collect all non-ambient endpoints by walking `m_eps` down the component tree.
2. Forwarders: every endpoint that is some port's `ep_next()`. A forwarding port (a
   structural parent's outer port that a child port binds to) is not a caller end, so a
   child whose domain is overridden does not make its parent's forwarding port look like a
   crossing.
3. For each port that is not a forwarder: follow `ep_next()` to the terminal export (the one
   holding the imp). Skip if unresolved (the bind map reports that). For each kind,
   `relate(ep_domain(k) of the port, ep_domain(k) of the terminal)`. Not SAME and not
   waived: a binding crossing, `from` = the port, `to` = the terminal.
4. For each component, for each kind with `is_crossing(k) == 0`: compare every data
   endpoint's domain with the component's own. A difference is a component crossing.
5. For each component with a bound reset: the reset-sync rule (§7.4).

A socket's two directions are covered by step 3 seeing both its port and its mirror's
port. Each crossing is reported once per (port, terminal, kind).

### 7.3 What permits a crossing

- A **crossing element**: a component that overrides `is_crossing(k)` and associates its
  endpoints with the domains on each side (§6). Its outer bindings are then SAME on both
  sides, so nothing is reported. The library has none in the first implementation (an
  async FIFO `fw_async_channel` and `fw_reset_sync_domain` are deferred with multi-clock
  lowering). Tests use a local element.
- A **waiver**: `waive_crossing("out", FW_DOMAIN_RESET, "ch drains before ctrl[3] is set")`
  in the port owner's `connect()`. The reason is required, as for island exceptions. A
  waived crossing is reported at info with its reason.

### 7.4 Clock vs reset crossings, and severity

| Kind | Relation | Default severity | Why |
|---|---|---|---|
| clock | RELATED (divided from one root) | info | same physical clock; untimed ticks are lower bounds, and lowering puts both on one clock |
| clock | UNRELATED | error | real CDC: needs a synchronizer or async FIFO |
| reset | RELATED (one built from the other) | warn | a common, often intended pattern (soft reset of a sub-block), but when one side resets alone its `run()` is killed mid-call: the other side sees a call begun and never ended, or is left blocked in it (§4.5) |
| reset | UNRELATED | error | two independent resets meeting with nothing between them |
| reset sync | sync clock UNRELATED to the component's clock, or async with none | error | deassertion not synchronized to the clock that uses it (RDC) |
| any | waived | info | |

`+fw_crossings_sev=<kind>:<rel>:<sev>` overrides one row (e.g. `reset:related:error`).

### 7.5 Where it runs, and the report

- **Simulation:** `fw_component_root::start()` and `fw_component_root_param::start()` call
  `fw_crossing_check::run(this, found)` after `do_connect()` and before `emit_bind_map()`,
  and print each crossing of severity warn and above. If there is an error, `$fatal` after
  printing all of them. Plusargs, in the bind map's style:
  - `+fw_crossings_off`: skip the check;
  - `+fw_crossings_show`: also print info rows;
  - `+fw_crossings` / `+fw_crossings=<path>`: write JSON (default `fw_crossings.json`);
  - `+fw_crossings_nofatal`: errors do not stop the run.

  Each crossing is also an `fw_error`/`fw_warn` event on the port owner's `dbg` context.
- **Text line:**

```
fw-hdl crossing [error] clock unrelated binding: top.a.out (top.clk_b2) -> top.b.in_ex (top.clock)
fw-hdl crossing [warn ] reset related binding: top.dma.ch.req (top.dma.ch_rst) -> top.dma.req_ex (top.reset): a reset on one side kills calls in flight across it
fw-hdl crossing [info ] reset related binding: ... waived: ch drains before ctrl[3] is set
```

- **JSON:** `{"crossings": {"root": "top", "items": [{"kind": "reset", "relation":
  "related", "severity": "warn", "via": "binding", "from": "top.dma.ch.req", "from_domain":
  "top.dma.ch_rst", "to": "top.dma.req_ex", "to_domain": "top.reset", "waiver": ""}]}}`.
- **Python flows (first implementation):** no second checker. `hier.py` records each node's
  clock and reset domain (the path of the domain object, and whether it is the root's), read
  from the interpreted objects. Partition rejects, at the SV line that bound it, a node whose
  clock domain is UNRELATED to the root's or whose reset domain is not the root's ("derived
  reset domains are not lowered by Partition yet"). Running the SV check itself through the
  interpreter is open question Q4.
- Relation to Integrate's island checks: those read netlists for registered boundaries.
  This check reads the class model for domains. A later step can turn a declared crossing
  element into an island `cdc` exception automatically; not now.

## 8. Synthesis and formal

| Construct | Lowers to |
|---|---|
| root clock / reset domain | the design's clock / reset input (unchanged; `structure.py` binds them from `fw_root`) |
| `in_reset()` on the root domain | a read of the design reset (through `fw_reset_xtor_if`) |
| divided clock domain | more cycles on the one clock (unchanged) |
| `fw_reg_reset_domain::in_reset()` | logic: `reset \| (reg_q[bit] ^ active_low)`, the register's flop output |
| `fw_reset_combine::in_reset()` | logic: OR of its sources |
| `wait_deassert()` / `wait_assert()` | a tick loop on a condition (`while (c) tick(1)`), as written |
| `step()` in a derived reset domain | as written: it reads `in_reset()` itself (logic above) |
| `run()` in a derived reset domain (supervised, §4.5) | not lowered yet: rejected with a message naming the component and the domain. The intended lowering: the process's state register and the fields it writes take their reset values while `in_reset()` holds, i.e. the process's reset is `design reset \| in_reset()`; `reset_state()` is the class-model side of the same thing |
| a second root clock, `fw_reset_sync_domain`, async FIFO | rejected (single-clock lowering) |

A derived reset domain does not change which flops have a reset in the first
implementation: state is reset by the design reset only, and a synchronous-level component
(`step()`) in a soft-reset domain re-initializes its own state in its code, so the RTL does
exactly what the class model does. A supervised `run()` (§4.5) needs the process-reset
lowering of the table above, which is not built; until it is, the front ends reject it.

Python front-end changes to keep everything working with the new `reset` port:
- `fe/parser.py`: add `fw_reset_xtor_if.sv` to the library file list.
- `fe/elab/entry.py`: seat `root.reset` on an `fw_reset_xtor_bridge` over `u_rst` when
  `fw_root` has one. Also resolve `connect` with `_find_up`, not `clock_port.cls.find`: the
  port's class is now `fw_domain_port`, which inherits `connect`.
- `fe/elab/hier.py`: seat `reset` on a placeholder bridge as it does `clock`. `_holders()`
  already skips `fw_component`'s own properties, so `reset` is not taken for a design port
  (test it).
- `comp_api.py`: the generated harness adds `u_rst` and seats it.
- `wrap.py`: add `reset` to `_RESERVED`.
- The XLS codegen knobs `reset`/`reset_active_low` are block-pin settings of the XLS engine
  adapter, and stay there. Integration ties every block's reset pin to the domain's net. No
  domain code emits or reads XLS anything.

Formal:
- The root reset domain is the reset formal assumes asserted in cycle 0 and deasserted
  after, as `tests/formal/axi4_fv.sv` does by hand today. A method-level harness
  ([formal-method-level.md](formal-method-level.md)) takes that assumption from the root
  domain instead of a protocol pin.
- A register-bit reset is ordinary logic, so formal explores soft resets at every cycle.
  A property that does not hold across a soft reset needs an explicit assumption (e.g. the
  bit is not set while a transfer is outstanding), and having to write it is the point.
- Rules gap 8 (VALID low during reset, [rules.md](rules.md)): the domain does not make it a
  call event, because the class model does not exist during root reset. It makes the reset
  nameable: the monitor transactor's `reset` comes from its component's domain, so a pin
  rule can be stated against "the domain's reset" for any domain, not against a bundle pin.
  The concrete follow-up (§10, H5) is a monitor event `<ch>_valid_in_reset()` raised by the
  monitor core when `valid && reset`, and an immediate rule `valid_in_reset` on it.

## 9. Effects on this repo

Following U6 (API classes carry no clock or reset) and plan §14:

| Where | Today | After |
|---|---|---|
| `axi4_bundle.svh`, `tests/weave/synth/*bundle*` | `fw_clock = "aclk", fw_reset_n = "aresetn"` | attributes removed (the bundle goes in P12 anyway) |
| `bundle.py` | `clock`, `reset`, `reset_n` fields from `fw_clock`/`fw_reset`/`fw_reset_n` | fields removed; the attributes are an error naming this doc |
| `xtors.py` | `_clock_reset(b)`; pins named from the bundle; `!aresetn` inside the core connections | removed; every generated core, module and interface has `input logic clock, input logic reset` (active high) |
| `abs.py`, `abs/abs.sv.j2` | `clk_rst = ".aclk(clock), .aresetn(!reset)"`, `xtor_clk_rst()` override | removed |
| `fw_proto/src/fw_boundary.svh` | `xtor_clk_rst()` returns `.clock(clock), .reset(reset)` | removed; the emitter asks the boundary's domains |
| `fw_proto/src/fw_emitter.svh`, `fw_rtl_structural.svh`, `fw_extern_component.svh` | hard-coded `clock`/`reset` nets | `clk_rst_nets(fw_component c)`: `clock`/`reset` when `c`'s domains are SAME as the root's, else an error naming `c` and its domain (D8). Extern pin names and polarity still come from `extern_map()` |
| pin maps (`tests/ip/*_rtl.svh`, presets) | `x.clock("ACLK"); x.reset("ARESETN", .active_low(1))` | unchanged: this is where a device's polarity lives |
| hand RTL with AXI pins (`axi4_checker`, `axi4_slice`, `axi4_stream_chk`) | `aclk`, `aresetn` | unchanged (device pins, not transactors) |
| benches instantiating generated transactors: `tests/lint/axi4_lint_xtor.sv`, `axi4_lint_xtor_b2b.sv`, `axi4_lint_rtl.sv`, `tests/env/axi4_xtor_b2b.sv`, `tests/env/xtor/axi4_l1_link.sv`, `tests/formal/axi4_fv.sv`, `tests/unit/rules_pins_unit_test.sv` | `.*` or `.aclk, .aresetn` | `.clock(aclk), .reset(!aresetn)` |
| goldens (`fw_proto/python/tests/golden/axi4_*xtor*.sv`, woven xtor package) | | regenerated; the diff is pin names and the reset inversion only |
| docs: `writing-a-protocol-package.md`, `core-spec.md`, `derived-classes.md`, `p6-abstractors.md` (transactor clock/reset row), `reference-ips.md`, `fw_proto/README.md`, comment in `fw_proto_axi4_core_pkg.sv` | describe `fw_clock`/`fw_reset_n` | describe domains and pin maps |

Transactor bridges (`<proto>_<role>_xtor_bridge`) are endpoints owned by the abstractor
handle, so the crossing check sees them in the wrapper's domains. Their vif's clock pin is
connected by the emitter from the same domain, which is what keeps the two consistent.

## 10. Implementation plan

Order: fw-hdl first (F1-F5), then this repo (H1-H4). Each step ends with the named suites
passing; logs under `rundir/`. No commits or pushes without the user's instruction.
fw-hdl suites: `dfm run tests` in `packages/fw-hdl` (the per-directory sim tests,
`tests/stdlib` SVUnit, formal SVUnit) and `pytest tests/python` (compare against the
2026-11-11 baseline, plan §1). This repo: `pytest fw_proto/python/tests`, `dfm run tests`,
`dfm run ip`, `dfm run lint-rtl`, `fv-cover`/`fv-prove`/`fv-teeth`, and `dfm run fv` once at
the end. Verilator 5.055 from `packages/`.

| Step | Files | Tests | Exit |
|---|---|---|---|
| **F1 Domain shape** | new `fw_domain_if.svh`, `fw_domains.svh`, `fw_domain_port.svh`; `fw_clock_domain_if.svh` (extends), `fw_clock_domain.svh`, `fw_clock_xtor_bridge.svh`, `fw_clock_period_xtor_bridge.svh` (5 methods); `fw_endpoint.svh`, `fw_port.svh`, `fw_export.svh`, `fw_socket.svh` (ends, `set_domain`, `add_endpoint`); `fw_component.svh` (`clock` retyped, `m_eps`, `domain()`, `is_crossing`, ambient marks); `fw_hdl_pkg.sv` include order; `fake_clock` in 3 dbg tests; `entry.py` `_find_up` | existing: `clock_domain`, `dbg_*`, `root_restart`, all `dfm run tests`; pytest (the interpreter must accept `interface class ... extends` and the retyped `clock`); new `tests/clock_domain` checks of `relate()` (root vs /2: RELATED; /1 vs root: SAME; second root: UNRELATED) | no regressions; relations correct |
| **F2 Reset kind** | new `fw_reset_domain_if.svh`, `fw_reset_xtor_if.sv`, `fw_reset_xtor_bridge.svh`; `fw_component.svh` (`reset`, conditional inherit, helpers); `fw_root.sv`; `fe/parser.py`, `fe/elab/entry.py`, `fe/elab/hier.py`, `comp_api.py`, `wrap.py` | new `tests/reset_domain` (sim): inherit, override, unbound = never in reset, root `in_reset()` 0 while live, `sync_clock()` is the root clock; `root_restart` unchanged; pytest: native lowering of a model calling `in_reset()`/`wait_reset_deassert()` reads the design reset; `hier` does not list `reset` as a port | as F1, plus the new tests |
| **F2b Run lifecycle (U7)** | `fw_component.svh` (`do_run()` supervisor, `reset_state()`, which components are supervised); front end: a supervised `run()` is rejected by name | `tests/reset_domain`: a component in a signal reset domain starts `run()` on deassertion; assertion kills `run()` and a grandchild it forked; `reset_state()` called once per assertion; `run()` restarts on the next deassertion; `step()` keeps running in reset; root-domain components are not supervised (`root_restart`, every existing test unchanged) | as F2, plus the new checks |
| **F3 Derived resets** | new `fw_reg_reset_domain.svh`, `fw_reset_combine.svh` | `tests/reset_domain`: a bench-local root reset domain over a signal (the `fake_clock` pattern) so source assertion is observable; reg bit set/clear asserts/deasserts; waits return at the first tick; `active_low`; combine OR; `n = 1` equiv; chain reg-bit over combine. pytest `test_elab_reset_domain.py`: a reg-bit reset lowers to `reset \| reg_q[b]` | new tests pass; if the front end cannot read the register through `read_val()`, it rejects with a message and the gap is recorded here |
| **F4 Crossing analysis** | new `fw_crossing.svh`, `fw_crossing_check.svh`; `fw_component.svh` (`waive_crossing`); `fw_component_root.svh`, `fw_component_root_param.svh` (call, plusargs); `fe/elab/hier.py` (node domains), Partition rejection | new `tests/crossing` calling `fw_crossing_check::run` on built trees (no `$fatal`): one domain: none; /2 child: info; second root clock across a binding: error; reg-bit child bound to parent: warn, then waived: info with reason; local crossing element with `set_domain`: none, and the same without `is_crossing`: component crossing; socket: both directions; structural parent forwarding to an overridden child: no false crossing; combine of unrelated clocks: reset-sync error. One run through `start()` with an error checks `$fatal` and the JSON file. pytest: Partition rejects a second clock root and a derived reset, at the SV line | all prior suites unchanged (no existing tree has a crossing above info) |
| **F5 fw-hdl docs** | `docs/reference/clocking.md` → domains reference (adds the reset and crossing classes); `docs/methodology/components.md` §Clock domains → §Domains; `islands.md` (pointer, `cdc`); `synthesis.md` (table of §8); fw-hdl skill reference if it describes `clock` | docs build | |
| **H1 Weaver** | `bundle.py`, `xtors.py`, `abs.py`, `templates/xtors/*`, `templates/abs/abs.sv.j2`; `axi4_bundle.svh`, synth test bundles, core pkg comment | `pytest fw_proto/python/tests` with regenerated goldens, the diff reviewed as pin renames only | 17/17 |
| **H2 Emitter** | `fw_boundary.svh`, `fw_emitter.svh`, `fw_rtl_structural.svh`, `fw_extern_component.svh` | `dfm run ip` (three IPs, presets); a negative case: a boundary whose parent is on a reg-bit reset domain is rejected by name | ip passes |
| **H3 Benches** | the seven files in §9 | `dfm run tests`, `dfm run lint-rtl`, `fv-cover`, `fv-prove`, `fv-teeth`, then `dfm run fv` | all as at P10 |
| **H4 Docs** | the docs in §9; `rules.md` gap 8 note pointing at H5 | | plan §13 step 3 done |
| H5 (optional, later) | monitor core and bridge: `<ch>_valid_in_reset`; rule `valid_in_reset`; teeth case flips from "none" to the rule | `rules_teeth`, `fv-teeth` | gap 8 closed for the monitor |

Out of scope: power domains (only the enum slot and the shape of §3 are reserved);
`fw_reset_sync_domain`, an async FIFO and any multi-clock or multi-reset lowering;
emitting nets for non-root domains; a domain → pin reset driver for RTL in a derived reset
domain (`fw_reset_drive_xtor`, needed together with multi-reset emission); lowering a
supervised `run()` (§4.5, §8); running the crossing check in the Python flows (Q4).

Risks:
- The Python interpreter and pyslang must handle `interface class` inheritance and the
  parameterized `fw_domain_port #(T, K)` with an enum parameter. F1 finds out first; the
  fallback is to keep `fw_clock_domain_if` standalone and add the five methods to it
  directly.
- A user component with its own member named `reset` stops compiling. None in fw-hdl or this
  repo (the `reset()` methods found are on non-components: `fw_reg_base`,
  `fw_extern_map`, `fw_rule_set`, `axi4_rules`). Other repos using fw-hdl may have one.
- `$fatal` on crossing errors could stop a downstream bench that binds a second clock root
  today. `+fw_crossings_nofatal` is the escape; the fw-hdl suites have no such bench.
- Polling waits (`tick` loops) cost one wakeup per cycle per waiting process. Only
  processes waiting on a derived reset pay it.

## 11. Open questions

| # | Question | Recommendation |
|---|---|---|
Answered 2026-11-13: the user accepted the recommendations, then decided U7, which replaces
the answer to Q2.

| # | Question | Answer |
|---|---|---|
| Q1 | Keep `fw_root` tearing the tree down on reset (the root domain is never seen asserted), or add a warm mode where the tree survives and observes root reset? | Keep teardown (no warm mode). It is tested (`root_restart`), matches RTL (logic in reset does not run), and gives fresh state for free. With U7 it is the root's form of the run lifecycle (§4.5). |
| Q2 | Should asserting a derived reset domain restart its subtree (kill its `run()` processes, call a `reset_state()` hook, re-fork on deassert)? | First answer: no, observe only. **Replaced by U7: yes, by default, for every reset domain other than the root's** (§4.5). `step()` is not gated. State is restored by `reset_state()`. |
| Q3 | Should a RELATED reset crossing (soft-reset child bound to its parent) be an error by default? | Warn. It is the normal shape of a soft reset, and an error would force a waiver on every one. `+fw_crossings_sev=reset:related:error` makes it strict for a project that wants that. |
| Q4 | Run the same SV crossing check in the Python flows, through the interpreter, instead of Partition's narrower rejection? | Later. Partition rejects only what it cannot lower. |
| Q5 | Name of the component member: `reset` (parallel to `clock`, as decided) or something less likely to collide (`rst_dom`)? | `reset`. |

## 12. As built (2026-11-13)

Built in the order of §10, with F2b (§4.5) added for U7. Uncommitted; one patch per step
in `rundir/p11/`. Where the build differs from the sections above:

| § | Difference | Why |
|---|---|---|
| 3.2 | `fw_domain_ref` is declared in `fw_domain_if.svh`, and has `ref_name()` too. `fw_domain_port` adds `as_ref()` (used by `fw_component::domain()`) and `set_optional()` | `fw_endpoint` needs `fw_domain_ref` before the ports exist. Verilator 5.055 emits uncompilable C++ when `clock` and `reset` (two specializations) are both returned through the interface type in one `case`; `as_ref()` does the upcast inside the specialization. `set_optional()` keeps an unbound `reset` out of the bind map's "unconnected" list |
| 3.3 | `fw_endpoint` also has `ep_is_terminal()` (an export holding the imp) and `ep_full_name()`; `fw_component` has `num_endpoints()`, `get_endpoint()`, `get_children()`, `crossing_waiver()`, `reset_domain_name()`, `reset_supervised()` | what the crossing walk and the front ends need |
| 4.2 | `in_reset()` and the waits go through `reset.get_if()`, as `tick()` does | same resolution as the clock helpers |
| 4.3 | `fw_reset_xtor_if` is declared in `src/fw_clock_xtor_if.sv`, not a new file; `fe/parser.py`'s list is unchanged. `fe/elab/structure.py` skips an `fw_root` interface no code reads (`u_rst`) | the package's bridge holds a virtual of it, so every file list that compiles `fw_hdl_pkg` (fw-hdl's, this repo's, downstream ones) would otherwise need the new file |
| 4.5 | `disable fork` in a per-component supervisor, not a `process` handle per `run()` (both checked on Verilator 5.055 and xezim) | no registration race; what `fw_component_root` already uses |
| 4.5, 8 | The native front end rejects a supervised `run()` when the interpreter reaches `fw_component::run_supervised` (`interp.py`), naming the component and the domain | the restart lowering is not built |
| 5.1 | With `src` unbound, `fw_reg_reset_domain::sync_clock()` is the owner's clock | a register bit is written on its owner's clock; the waits need a clock |
| 5.2 | `fw_reset_combine::src` is a queue (`src[$]`), not a dynamic array | the elaboration interpreter has no `new[n]` |
| 7 | The reset-sync rule: reported once where a (clock, reset) pair first appears in the tree; a reset with no `sync_clock()` is an error whether or not it is async; a RELATED sync clock is not reported. Each record also carries a `note` (what it means; reset crossings say that a reset on one side kills `run()` processes and their calls in flight). The severity key for reset-sync is `reset:sync`. `fw_crossing_check::check_root()` is what `start()` calls; the interpreter skips `fw_crossing_check` calls | one report per cause; Q4 |
| 7.5 | Partition (`hier.py`, `_Domains`) also lets a structural component hold domain objects (an export implementing a domain API) as properties | otherwise a derived domain in a structural component was rejected as a "data property" before the domain rule could say why |
| 9 | `tests/lint/axi4_lint_rtl.sv` needed no change (it instantiates no generated transactor). The emitter checks domains with `fw_emitter::domain_error()` before writing anything; `clk_rst_nets()` / `clk_rst_conns()` give the connections. The negative case is `ip.axi-ram-gen-neg` (`+emit_neg_soft_reset` on the axi_ram generate pass) | |
| 10 | H5 not done (out of scope); `rules.md` gap 8 points at it | |
