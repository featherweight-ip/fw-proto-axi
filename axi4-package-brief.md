# AXI4 protocol package: brief for the package agent

Written 2026-11-10 in the fw-hdl-sv-weave packet. This brief is self-contained: it
states what was decided, what was prototyped, and what the AXI4 package must deliver.
For background:
- `abstractors.md` holds the decisions and their reasoning; its figures are in
  `abstractors-figs/`.
- `tests/abstractor_proto/` is a working prototype of the mechanisms below, for
  ready/valid.
- `protocol-ports.md` and `docs/methodology/levels.md` give earlier context.

Note: ../../featherweight-hdl/fw-hdl-sv-weave/

## 1. Goal

Build the **AXI4 protocol package**: the first full protocol in the new style. Use it to
wrap existing open-source AXI4 IP, unchanged, as fw-hdl components (abstraction level
L0). The package and the wrapped IPs serve as the test of two things at once:

1. **The protocol package design:** struct ports, method APIs, abstractors, ordering
   rules, transactors, formal.
2. **The IP-wrapping approach:** pin maps, extern components, assembly at class level,
   emission of a netlist identical to a hand-written one.

The two demonstrations it should enable (§7):
- **Easier formal authoring:** a wrapped AXI4 slave verified with SymbiYosys from the
  package's declared rules, in place of hundreds of lines of hand-written SVA.
- **API-level Python tests (later):** a Python test calling the AXI4 API through
  pyhdl-if, unchanged when the IP is swapped for a model.

## 2. The model, in brief

These are decisions; `abstractors.md` §4 has the reasoning.

- **A component's implementation is in exactly one place,** the module tree or the
  class tree. The class tree a designer writes is a *description*. An emitter splits it
  into:
  - **the netlist:** one module per RTL structural class. Its struct ports are its
    pins. It must equal a hand-written netlist.
  - **a generated simulation wrapper** (an implementation artifact): the netlist, one
    transactor module per abstractor or monitor, and the run-time class tree.
- **Struct ports.** A struct port's type declares its *fields*: name, width, direction
  (fwd = driven by the sender, rev = driven back). Nets, module ports and pin maps are
  built from the field table. Nothing outside the type assumes a protocol.
- **Extern components** wrap an existing module.
  - **The class names only its root module.** Which file defines it is the build's
    concern (dfm filesets).
  - **The pin map is a string map** `<module>.<pin>` ↔ `<struct port>.<field>`:
    - `x.pin("p", port, "field"[, msb, lsb])`;
    - rules as data, e.g. `x.prefix(port, "s_axi_").rename(...)`;
    - entries resolve in order: an explicit pin before a rule is a pre-override; one
      after a rule replaces it.
  - **Every field bit maps to exactly one pin.**
- **Abstractors** convert between a method API and a struct port.
  - **Auto-insertion is the default.** Connecting a method port to a struct port
    (`core.in.connect(in)`) makes the struct port's protocol class insert one, named
    `<port>_abs`. `link()` connects like to like.
  - **Configured from outside, by path:** the description stays clean, and tests
    configure `dut.in_abs` (stalls, queue depth, error injection) or override its class.
  - **Explicit instancing** is the exception, for an abstractor the inserter cannot
    derive.
  - **Wire parameters** (id width, data width) come from the struct port, never from
    the abstractor.
- **Shells.** At run time a class that wraps RTL behind abstractors is replaced, via
  the factory, by an **API shell**: a subclass that builds only its ports and binds them
  to transactor handles in `connect()`. RTL appears in the class tree only as a
  **monitor shell**, and only when a monitor asks for visibility.
- **Equivalence across levels is keyed on the API, not the wire protocol:** "an
  endpoint of API A, in role R, with payload T". The interface classes are used for
  static typing only, never as the target of a `$cast` (§8).
- **Ordering rules are annotated, not implemented** (proposal, `abstractors.md` §4a).
  - **The form:** a rule is a listener on the API's listener interface; its body asserts
    what must hold. It is built from a restricted vocabulary:
    - immediate assertions;
    - library auxiliary state (counters, flags);
    - quantified variables (`fw_any #(T)`), which simulation evaluates for every value
      seen and formal leaves symbolic.
  - **Where a rule is attached gives its role:** on the API, the contract; on a
    producer, its guarantee; on a consumer, its requirement.
  - **One rule serves:**
    - simulation checks;
    - formal on RTL (SVA via the abstractor's field mapping);
    - event-level formal on descriptions above RTL (an SPL process's use of the API);
    - later, the synthesis search.

## 3. What the package contains

| Part | Notes |
|---|---|
| Struct-port types | Per channel (AW, W, B, AR, R), and a **bundle** type for a whole AXI4 port, per role (manager, subordinate). Field tables follow the AMBA names (`awvalid`, `awaddr`, `awid`, …). The parameters (ID, ADDR, DATA, USER widths) are one parameter class, so a bundle and its channels agree. Optional signals (`awregion`, `awqos`, `*user`, …) are fields that can be absent. |
| Method APIs | Channel-level APIs per role (send/recv per channel, as fw-proto-kit already structures AXI), plus transaction-level APIs (`write(addr, data[], …)`, `read(addr, len, …)`) composed over the channels. |
| Listener interfaces | One typed callback per API call (per channel beat, and per transaction where useful). These are the events the rules annotate. |
| Rules | The AXI4 contract as listener annotations (§5). |
| Signal-level rules | Valid held until ready, payload stable while stalled, no X on valid. One per channel; these belong to the struct-port family. |
| Transactors | Initiator, target and monitor transactor modules per channel, bundled for a whole port. Follow the fw-proto-kit structure: `xtor_if` + synthesizable core + bridge. |
| Abstractors | Classes for manager-side, subordinate-side and monitor roles, inserted automatically by the bundle type's `connect()`. Configuration knobs by path: per-channel stall rates, outstanding limit, response reordering (subordinate side), error injection. |
| Pin-map presets | Rules covering the common naming styles of the reference IPs (§6). Examples: `s_axi_` + field, `m_axi_` + field, upper case `S_AXI_` + upper field. Wrapping a typical IP should take one line per port. |
| Formal | (1) the fw-proto-kit back-to-back proof of the cores, required per kit; (2) property generation from the rules for a wrapped IP (§7). |
| Tests | Back-to-back simulation (required per kit), plus one test per reference IP (§6). |

## 4. AXI4 specifics to design carefully

- **Channels and roles.** There are five independent ready/valid channels. A manager
  drives AW, W and AR and receives B and R; a subordinate mirrors it. A monitor watches
  all five.
- **IDs and ordering.** Responses with the same ID return in request order; responses
  with different IDs may return in any order. Reads and writes are independent.
- **Write ordering.**
  - B follows both the AW and the W beat with `wlast`.
  - W may precede AW (AXI4 allows it). The rules must not forbid it.
- **Bursts.**
  - Types INCR, WRAP and FIXED; `len` + 1 beats.
  - `wlast`/`rlast` on exactly the last beat.
  - WRAP alignment constraints; 4 KB boundary crossing forbidden.
  - Narrow transfers (`size` < bus width) with `wstrb`.
- **Responses.** OKAY, EXOKAY, SLVERR, DECERR. Exclusive access needs an
  escape-hatch rule, see §5.
- **Wire parameters vs API facts.**
  - **From the struct port:** ID, ADDR, DATA and USER widths, set by the wrapped IP's
    parameters (`extern_map()` records them).
  - **From the API's declared facts, when an API port is lowered with no IP behind it:**
    outstanding count, whether responses may reorder, which burst types are used.
    These decide the ID width and the options.

## 5. The AXI4 contract as rules

Each rule is a listener annotation (form in §2). The minimum set:

| Rule | Kind |
|---|---|
| R and B only for an outstanding AR or AW, matched by ID | correspondence |
| Same-ID responses in request order (read and write separately) | keyed order (`fw_any` id) |
| A read returns exactly `arlen + 1` R beats, `rlast` on the last only | grouping |
| W carries exactly `awlen + 1` beats for each AW, in AW order, `wlast` on the last | grouping, correspondence |
| B after the AW and the W with `wlast` of that write | happens-before |
| Burst legality: WRAP length and alignment; no 4 KB crossing; `size` ≤ bus width | immediate, on AW/AR |
| Outstanding ≤ declared capacity (per ID or total) | capacity |
| Exclusive access (EXOKAY pairing) | free-form escape hatch |

**Data integrity is a separate, optional user rule:** "a read after a write to the same
address returns the written data", with the address an `fw_any`. It is the showcase for
an API-level property written in a few lines.

## 6. Reference IPs

Researched 2026-11-10. Licenses and port styles were checked against the repositories.
Yosys 0.70 and Verilator 5.054 were run on the modules marked "tool check". Fetch the
IPs into the workspace with ivpm (git) rather than copying them into fw-hdl.

### 6.1 Shortlist

| # | Module | Role | Port style | Stresses |
|---|---|---|---|---|
| 1 | verilog-axi `axi_ram` | subordinate | flat, lowercase `s_axi_*`; `clk`/`rst` (active high) | INCR/FIXED bursts, narrow transfers, WSTRB, in-order responses. No QOS/REGION/USER pins, so those fields are absent. |
| 2 | wb2axip `demofull` | subordinate | flat, uppercase `S_AXI_*`; `S_AXI_ACLK`/`S_AXI_ARESETN` (active low); params `C_S_AXI_*` | WRAP bursts, exclusive access (`OPT_LOCK`); non-AXI memory pins (`o_we`, `o_waddr`, `i_rdata`) beside the AXI port |
| 3 | verilog-axi `axi_crossbar` (2×2) | pass-through | flat, ports packed into wide vectors (`[S_COUNT*S_ID_WIDTH-1:0] s_axi_awid`) | bit-slice pin mapping; ID widening (`M_ID_WIDTH = S_ID_WIDTH + clog2(S_COUNT)`); out-of-order responses across IDs; USER |
| 4 | PULP `axi_cut`, then `axi_id_remap` | pass-through | packed `req_t`/`resp_t` structs as type parameters, `_i`/`_o` suffixes | struct-typed module ports; per-ID ordering across an ID remap; atomics (`aw_atop`) and USER fields |
| 5 | wb2axip `axidma` or verilog-axi `axi_cdma` | manager | flat `M_AXI_*`, plus an AXI-Lite control port `S_AXIL_*` | manager-side rules (outstanding limit, B after AW and the last W); one component with struct ports of two protocols |

How each tests the wrapping approach:
- **1 and 2:** the same field names in two cases and prefixes, plus clock/reset
  exceptions with both reset polarities.
- **3:** a slice of a wide pin for each port index.
- **4:** a module port that is itself a struct (see §10, question 2), and the
  Yosys path for heavy SystemVerilog.
- **5:** several struct ports, of different protocols, on one component.

How each tests the package:
- **1 and 2:** burst grouping, WSTRB and narrow rules on simple in-order subordinates;
  2 adds WRAP and exclusive access.
- **3 and 4:** really produce out-of-order responses across IDs. They are the test of
  the per-ID ordering rules and of a manager-side transactor that accepts reordering.
  4 checks that ordering survives ID remapping.
- **5:** the subordinate-side transactor (fw-hdl acting as memory) and the manager-side
  rules.

### 6.2 Repositories

**verilog-axi** (github.com/alexforencich/verilog-axi)
- MIT; can be vendored or fetched.
- Deprecated in favour of taxi (last commit 2025-02), but stable.
- Plain Verilog-2001.
- Other modules: `axi_register`, `axi_fifo`, `axi_axil_adapter`, `axi_dma`.
- Has cocotb + cocotbext-axi testbenches (Icarus by default, Verilator optional); no
  formal.
- Tool check: Yosys synth of `axi_ram` and hierarchy of `axi_crossbar` pass; Verilator
  `-Wall` lint of `axi_ram` passes.

**wb2axip** (github.com/ZipCPU/wb2axip)
- Apache-2.0 per the file headers. There is no root LICENSE file, and a GPL PDF left in
  `doc/` is from an older license.
- Maintained (last commit 2026-06).
- Other modules: `axixbar`, `axi2axilite`, `axidouble`, `aximm2s`/`axis2mm`.
- Tool check: Yosys synth of `demofull` and `axixbar` passes; Verilator lint of
  `demofull` passes.

**PULP axi** (github.com/pulp-platform/axi)
- Solderpad 0.51 (permissive). Very active (v0.39.11, 2026-11).
- Depends on `common_cells`, `common_verification` and `tech_cells_generic` via
  Bender; pin the revisions (`spill_register` was renamed).
- Structs come from `AXI_TYPEDEF_ALL(...)` macros. Most modules also have an `*_intf`
  variant with the `AXI_BUS` interface.
- Other modules: `axi_xbar`, `axi_to_mem`, `axi_dw_converter`, `axi_to_axi_lite`,
  `axi_atop_filter`.
- `src/axi_test.sv` holds random manager/subordinate, monitor and scoreboard classes, a
  useful SV-side reference.
- Tool check: native Yosys 0.70 fails on `axi_pkg.sv`. Use sv2v (in the workspace) or
  yosys-slang for synthesis and formal. Verilator lint of an `axi_cut` typedef wrapper
  passes.

**cocotbext-axi** (github.com/alexforencich/cocotbext-axi)
- MIT, active.
- `AxiMaster` (multiple outstanding; accepts reordered and interleaved responses),
  `AxiSlave`, `AxiRam`.
- Binds by prefix: `AxiBus.from_prefix(dut, "s_axi")`, the same rule as our pin map.
- No atomics, no AXI4 memory-mapped monitor, and the subordinate models apparently do
  not reorder.
- Use as an independent reference for differential tests when the Python side starts
  (§7.2).

**Not shortlisted:**
- **taxi** (fpganinja/taxi): CERN-OHL-S-2.0, strongly reciprocal. Fetch it, never
  vendor it. It has SV interface ports only, so use it only if interface-port support
  is wanted.
- **YosysHQ SVA-AXI4-FVIP:** permissive, spec-structured SVA, but stale (2023). Its
  named properties need Verific; open-source Yosys rejects them.
- **CVA6:** vendors PULP axi, so nothing new.
- **Ultra-Embedded:** stale.
- **Arm's protocol checker:** not open.

### 6.3 Formal comparison baseline

wb2axip `bench/formal/faxi_slave.v` and `faxi_master.v`:
- Hand-written, with flat pins.
- About 1300 lines each.
- They run on open-source SymbiYosys.

**These are a partial public version.** The README says the full properties (needed for
induction proofs and for out-of-order responses) are sold separately. Out-of-order
checking is therefore where generated properties can go beyond the open baseline.
Compare four things:
- lines written by the user;
- time to bind to a DUT;
- what is covered (out-of-order, exclusive access, data integrity);
- BMC depth and run time.

## 7. Demonstrations

### 7.1 Easier formal authoring

1. **Wrap** a reference AXI4 slave: an extern class plus one pin-map preset, about 10
   lines.
2. **Generate** a SymbiYosys job from the package:
   - the manager-side contract becomes **assumptions** on the IP's inputs;
   - the subordinate's obligations become **assertions** on its outputs;
   - the signal-level rules are added.
3. **Add** the data-integrity rule (§5) as a few lines at API level.
4. **Compare** with the hand-written wb2axip properties (§6.3), on lines written, what
   is covered and run time. Show at least one property the public set doesn't cover:
   per-ID ordering on `axi_crossbar` or `axi_id_remap`.
5. **Inject a bug** in a copy of the IP (e.g. B before the last W, or an `rlast`
   miscount). The counterexample is reported as an **API event trace** (which call, which
   ID), not only as a waveform.

### 7.2 API-level Python (deferred; design for it now)

pyhdl-if is the chosen route, but it is not in the workspace yet. Design the API
classes so that a pyhdl-if API definition can be generated from them. A Python test
would then call `write`/`read` through the inserted abstractor's handle, and walk the
tree to find endpoints. Keep the transaction-level API free of SV-only constructs that
would make this hard.

## 8. Known issues and prerequisites

These were found while prototyping; each affects this work.

- **Verilator folds some `$cast`s to 0.** A cast between a class and an interface class
  always fails when the class extends a base and adds `implements` itself. Every
  abstractor, bridge and extern wrapper has that shape. Never `$cast` to an interface
  class; use virtual queries or self-registration. See `verilator-cast-repro/README.md`.
  Builds use `-Wno-fatal`, so the `CASTCONST` warning is easy to miss.
- **`fw_port` resolves during connect, child by child.** A port whose provider chain
  passes through an export that a *later* sibling wires in its own `connect()` fails.
  Wrapping classes hit this. The prototype's workaround is to build the wrapper before
  its users. The fix is a separate resolution pass after every `connect()`.
- **The factory is not wired in.** `src/fw_factory.svh` and `src/fw_view_ctx.svh` are
  not included in `fw_hdl_pkg`. The prototype uses a stand-in (`fw_proto_factory`).
  Shells and outside configuration both need a real factory.
- **The emitter runs in an SV gen pass.** It elaborates the class tree in a simulation
  and writes the netlist and wrapper; dfm then compiles them. The agreed direction is to
  keep this for the first protocol or two, add a structure export (JSON), and move to
  the Python elaborator later. Don't build anything that only the SV gen pass could
  provide.
- **The pin map's Python side is missing.** `pin`/`prefix` exist in `src/fw_extern.svh`,
  but the Python elaborator (`fe/elab/hier.py`, `extern.py`) doesn't yet resolve them
  against the module header, or check widths and directions. AXI4 IPs with many pins
  will want those checks.
- **Extern file lists.** Existing wrappers name their source files
  (`fw_extern_utils(module, files)`). The decision is to name only the module; the
  migration of `src/` is pending (`abstractors.md` §5).
- **Transactor queue depth** is a `localparam` in the `xtor_if`s. Making it a run-time
  setting is needed for outside configuration.
- **Environment.**
  - Put `packages/verilator/bin` (5.054) first on `PATH`; `/tools` has 5.041, which
    rejects code in `fw_dbg_ctx.svh`.
  - The workspace venv needs `pip install --no-deps -e .`.
  - Yosys is at `packages/yosys/bin/yosys`.

## 9. Suggested milestones

| # | Delivers | Done when |
|---|---|---|
| A1 | Struct-port types and bundle for AXI4, with a parameter class; pin-map presets; reference IPs fetched with ivpm | `axi_ram`, `demofull` and `axi_crossbar` wrapped (`axi_cut` if struct pins are settled); each emitted netlist matches a hand-written instantiation and synthesizes in Yosys |
| A2 | Channel APIs, listener interfaces, transactors and abstractors; auto-insertion on the bundle | The back-to-back simulation test passes; a wrapped AXI4 RAM is driven through inserted abstractors from a class test; stalls set from outside reach the pins |
| A3 | Rules (§5) as listener annotations, checked in simulation | Rules pass on every reference IP in simulation; a seeded protocol bug is caught and reported as an API event |
| A4 | Property generation for SymbiYosys from the rules | The demonstration in §7.1, including the comparison with a hand-written property set |
| A5 | Transaction-level API (`read`/`write`) and the monitor | Transactions assembled by the monitor, with ID matching; data-integrity rule passes |
| A6 | Pass-through and manager IPs (interconnect, DMA) wrapped and assembled | A small system assembled at class level (manager → interconnect → RAM), emitted, simulated, with monitors on internal links |

Record progress in a status note in the package's repo after each milestone, so work can
resume after a context reset.

## 10. Open questions for the package agent to settle (and report back)

1. **Do channel struct ports compose into a bundle cleanly?** Struct ports today have
   one field table. Options: a bundle as one struct port whose fields carry channel
   prefixes, or a bundle class of five channel struct ports. The pin map and monitors
   want per-channel access; `connect()` wants the whole port.
2. **SV struct and interface ports in reference IPs.** PULP's ports are packed
   structs (`slv_req_i.aw.addr`), so the pin map needs struct members on the module
   side, e.g. `x.pin("slv_req_i.aw.addr", ...)`. Alternatively, bind a whole struct pin
   to a struct port when the layouts match. taxi has SV interface ports only; decide
   whether to support them or wrap such IPs in a flat shim. Also decide the Yosys route
   for heavy SystemVerilog (sv2v or yosys-slang).
3. **Rule vocabulary gaps** found while expressing AXI4. Report them; they feed the
   rule library.
4. **What should the generated formal harness need from the user beyond the wrapper?**
   E.g. bounding outstanding transactions for the solver.
