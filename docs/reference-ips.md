# Reference IPs

Existing AXI4 RTL wrapped as extern components and driven from class tests through
inserted abstractors (plan P6, design in [p6-abstractors.md](p6-abstractors.md)). This
note covers how each IP is wrapped, what its test checks, and how to wrap the next one.

Run them all with `dfm run ip`. A single IP is `dfm run ip.axi-ram`, and likewise
`ip.demofull`, `ip.axi-crossbar` and `ip.presets`.

## Sources

Fetched by ivpm into `packages/` (`ivpm.yaml`, type `raw`):

| Package | Upstream | Revision used | IPs |
|---|---|---|---|
| `verilog-axi` | github.com/alexforencich/verilog-axi | `516bd5d` (2025-02-27) | `axi_ram`, `axi_crossbar` |
| `wb2axip` | github.com/ZipCPU/wb2axip | `2e8d3bc` (2026-06-02) | `demofull` |

PULP's AXI IPs wait on brief Q2 (SV struct pins).

## Wrapping an IP

An extern component names the module, its parameters, its clock and reset, and one pin
rule per AXI port:

```systemverilog
class axi_ram_rtl extends fw_extern_component;
    axi4_sub_sp #(P) s;
    ...
    virtual function string extern_module(); return "axi_ram"; endfunction

    virtual function void extern_map(fw_extern_map x);
        x.param("DATA_WIDTH", P.DATA_W);
        x.param("ADDR_WIDTH", P.ADDR_W);
        x.param("ID_WIDTH", P.ID_W);
        x.clock("clk");
        x.reset("rst");
        x.prefix(s, "s_axi_");          // the preset: one line per port
    endfunction
endclass
```

`P` must match the IP's pins. A field the IP lacks is absent in `P`: width 0, or
`HAS_QOS`/`HAS_REGION` set to 0. The struct port's role is the IP's side of the link. An
IP that is a subordinate has an `axi4_sub_sp`, and one that drives a bus has an
`axi4_mgr_sp`.

Around it there are two more classes:
- `<ip>_sys`, an `fw_rtl_structural`, is emitted as a module. Its ports bind to the
  extern's with `bind_inner`.
- `<ip>_api`, an `fw_component` created through the factory, is what tests see. Each of
  its struct ports is connected to an API socket with `core.<port>.connect(<socket>)`,
  which inserts the abstractor.

The pin rules (fw-hdl `fw_extern_map`):

| Rule | Use |
|---|---|
| `prefix(sp, "s_axi_")` | pins named prefix + channel + field (`s_axi_awaddr`) |
| `.upper()` | upper-case names (`S_AXI_AWADDR`) |
| `.rename(field, pin)` | one field whose pin is named differently |
| `.slot(k)` | the port is slot k of packed-vector pins (crossbars) |
| `pin(pin, sp, field, msb, lsb, slot)` | one pin, or a slice of a field |
| `tie(pin, value)` / `open(pin)` | a pin outside the bundle: an input held, an output left open |
| `clock(pin)` / `reset(pin, .active_low(1))` | the component's clock and reset |

The emitter fails if any bit of a field is unmapped or mapped twice, if a pin is mapped
twice, or if a pin's slots are not 0..n-1. It writes parameter values wider than 32 bits
sized.

## The IPs

| IP | Wrapping | `P` | What the test checks |
|---|---|---|---|
| `axi_ram` | `prefix(s, "s_axi_")` | ID 8, 32-bit data, 16-bit address; no QOS, REGION or USER | the `l2_mem_ns` scenarios that fit a plain RAM: single write/read, 40 random bursts, 4 concurrent IDs. Each is checked against `axi4_mem_model` as the reference. It also checks that stalls set by path reach the pins: `r.max_gap`/`b.max_gap` on `dut.s_abs` (`fw_proto_cfg`) must make R stall for at least two cycles per beat (checked when `max_gap` >= 8). |
| `demofull` | `prefix(s, "S_AXI_").upper()`, active-low `S_AXI_ARESETN`, the memory port tied/open | ID 4, 32-bit data, 16-bit address, QOS; no REGION or USER | the AXI side: responses, IDs, beat counts. `i_rdata` is tied to a constant, so every active lane of every read must return it. |
| `axi_crossbar` (2x2) | `prefix(sN, "s_axi_").slot(N)`, `prefix(mN, "m_axi_").slot(N)`; USER pins tied/open | slave ports ID 4 with QOS; master ports ID 5 with QOS and REGION | two managers at once over two memories (m0 at 0x0000-0x7fff, m1 at 0x8000-0xffff), with ID widening (both memories see both slave ports). mem1 answers up to 300 ns late, so reads behind m0 overtake reads behind m1; the test requires at least one read out of order on s0. |
| presets | `prefix` in both styles, on a subordinate and a manager port | `P_DEF` and `P_WIDE` (`tests/env/axi4_test_params_pkg.sv`) | no traffic. The emitted netlists are linted against stub modules whose headers come from an AMBA signal table in `presets/presets.py`, independent of the bundle. A pin the preset names that the header lacks, a header pin left unconnected, or a width that differs fails the test. |

Each of the first three IPs has four checks:
- `<ip>-run`: the class tests through the abstractors, in simulation.
- `<ip>-netlist`: the emitted `<ip>_sys.sv` equals a hand-written `<ip>_sys_ref.sv` after
  comments are removed and whitespace normalized.
- `<ip>-synth`: Yosys synthesizes the emitted netlist with the IP's RTL.
- Teeth, by hand: `+plant` on `<ip>-run` flips one bit of the first write's data, or,
  with a tied read value, of the expected value. The run must fail. This was checked
  for `axi_ram` and `demofull`.

The AXI4 rules (plan P7, [rules.md](rules.md)) run on every abstractor of the first
three IPs, attached by path (`ip_axi_rules`). A rule failure fails the run. The
crossbar's master ports also carry the capacity rule, at `M_ISSUE`+1 (5 writes, 5
reads): with two slave ports the crossbar can issue one past `M_ISSUE` (see
[rules.md](rules.md), Where they are attached).

All of them share the test bench in `tests/ip/common`:
- `ip_axi_tb`: a manager adapter, a blocking shim and the reference memory behind an
  `axi4_mgr_socket`.
- `ip_axi_mem`: a memory behind an `axi4_sub_socket`, for manager ports that leave the
  module tree.
- `ip_axi_rules`: the AXI4 rules on abstractors, by path.

## What the IPs taught

- verilog-axi's crossbar does not accept R beats of different IDs interleaved. The
  subordinate adapter interleaves only with `r_interleave` set; it is off by default, and
  the L2 reorder tests turn it on.
- Yosys 0.70 truncates an unsized parameter value wider than 32 bits, hence the sized
  values (crossbar `M_ADDR_WIDTH`).
- Yosys 0.70 cannot run `$error` in an initial block's for loop (verilog-axi's parameter
  checks). `ip_checks.py` gives it a copy in which `$error` is `$display`.
- `axi_ram` treats WRAP as INCR, so its test does not use WRAP (`use_wrap = 0`).

## Adding an IP

1. Add the repository to `ivpm.yaml`, if it is not already there.
2. Create `tests/ip/<ip>/`, one class per `.svh`, included by `<ip>_ip_pkg.sv`:
   `<ip>_rtl` (the extern), `<ip>_sys`, `<ip>_api` (registered with `fw_proto_reg`), a
   test class extending `ip_axi_tb`, and the top.
3. Add `<ip>_gen.sv` (the generate pass) and `<ip>_tb.sv` (the run), copied from
   `axi_ram`.
4. Add the tasks to `tests/ip/flow.yaml`: `-rtl`, `-pkg`, `-gen-*`, `-emitted`, `-tb`,
   `-img`, `-run`, `-netlist`, `-synth`, and the `<ip>` task that needs them. Then add
   `ip.<ip>` to the `ip` root in `flow.yaml`.
5. Write `<ip>_sys_ref.sv` by hand. Run with `+plant` once and check that it fails.
