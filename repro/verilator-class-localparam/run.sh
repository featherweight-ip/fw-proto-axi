#!/bin/bash
# Builds t.sv twice with the Verilator first on PATH (the project's 5.055:
# export PATH=$PWD/packages/verilator/bin:$PATH from the repo root):
#   narrow  DATA = logic [31:0] on a 64-bit bus: internal fault (expected to fail)
#   wide    DATA = logic [63:0]: builds (the control)
# A 12 GB address-space limit turns the runaway into a quick segfault; without it
# the build grows until the OOM killer stops it.
cd "$(dirname "$0")"
verilator --version
sed 's/to_mem #(PDEF, logic \[31:0\], logic \[31:0\]) tm;/to_mem #(PDEF, logic [31:0], logic [63:0]) tm;/' \
    t.sv > t_wide.sv
for v in t t_wide; do
    rm -rf obj_$v
    ( ulimit -v 12000000; verilator --cc -Wno-fatal -Wno-lint --Mdir obj_$v $v.sv --top-module top \
        > $v.log 2>&1 )
    echo "$v: exit $? $(grep -m1 -o 'internal fault' $v.log)"
done
