# Verilator 5.055: internal fault on a class localparam from `$bits(type param)`

Found 2026-11-11 in `axi4_to_mem` (`src/behav/fw_proto_axi4_behav_pkg.sv`, plan P5).
Reduced from that class by line deletion, then cleaned up by hand. Not yet reported upstream.

## Reproduce

```
export PATH=$PWD/packages/verilator/bin:$PATH     # from the repo root: 5.055
repro/verilator-class-localparam/run.sh
```

Expected output (`Verilator 5.055 devel rev v5.054-182-g4ab62c3ab`, the ivpm package):

```
t: exit 139 internal fault
t_wide: exit 0
```

## What triggers it

All in [`t.sv`](t.sv) (about 60 lines, one package and a top):
- a class `to_mem #(param_t P, type ADDR, type DATA)` with
  `localparam BPB = (BYTES < BUS) ? BYTES : BUS`, where `BYTES = $bits(DATA) / 8` and
  `BUS = P.DATA_W / 8`;
- a task that fills a queue `data_t d[$]` through an interface-class task
  (`xact_if #(P)::read`), whose argument types are typedefs of another parameterized
  class (`types #(P)::addr_t`, `data_t`, `attr_t`);
- a nested loop over `n < BYTES / BPB && n < d.size()` and `i < BPB`, writing
  `data[8*(n*BPB + i) +: 8] = d[n][8*i +: 8]`;
- the class specialized with DATA narrower than the bus (32-bit DATA on a 64-bit bus,
  so `BPB` = 4 = `BYTES`). With DATA as wide as the bus it builds.

Things that make it go away, each on its own (found while reducing):
- `BPB` a run-time member instead of a `localparam` (the workaround in
  `axi4_to_mem`);
- removing the interface-class call that fills `d`;
- writing `data[8*i +: 8]` instead of `data[8*(n*BPB + i) +: 8]`;
- an interface class with the same signature declared in the same package as the user
  class instead of in another package (seen in the unreduced setting).

It does not depend on `--timing`.

## Where it fails

`verilator --debug --gdbbt` (the binary has no symbols): the last stage logged is
`V3Class.cpp:288 classAll`, and the crash comes while writing its tree dump
(`Vtop_034_class.tree` is cut off). The backtrace is over a million frames of the same
few addresses, so it is an endless recursion, which suggests a cycle in the AST after
V3Class. Without `--debug` the build grows without bound (killed by the OOM killer at
about 60 GB) or segfaults under a `ulimit -v`.

Suggested next step for a fix: a debug build of 5.055 (or master), run
`--debug --dumpi-tree 9` on `t.sv`, and diff `Vtop_033_inline.tree` against what
V3Class makes of the loop body (look for a node that is its own ancestor, likely around
the part-select with the `BPB` parameter after class-parameter specialization).
