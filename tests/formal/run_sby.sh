#!/bin/bash
# Run SymbiYosys on a harness outside formal.sby (which has no prove mode):
# $FV_TOP = axi4_fv (default; back-to-back cores) or axi4_slice_fv.
# Usage: run_sby.sh <mode: bmc|prove|cover> <depth> <workdir> [src-dir]
# src-dir defaults to the repo's src (teeth.sh passes a mutated copy).
# Extra sv2v defines come from $FV_DEFINES; a parameter override for the
# harness from $FV_CHPARAM (e.g. "-set MAX_OUT 3"); the sby engine from
# $FV_ENGINE (default "smtbmc boolector").
set -e
mode=$1; depth=$2; work=$3
here=$(cd $(dirname $0) && pwd)
src=${4:-$here/../../src}
engine=${FV_ENGINE:-smtbmc boolector}
# The abc engines need a design without x constants (techmap of $shiftx
# makes them; they become free inputs).
abc=; [[ $engine == abc* ]] && abc=1
top=${FV_TOP:-axi4_fv}
mkdir -p $work; work=$(cd $work && pwd)
sv2v --exclude=Assert -DFORMAL $FV_DEFINES \
  $src/types/axi4_types_pkg.sv $src/checker/axi4_checker.sv \
  $src/cores/axi4_slice.sv $src/cores/axi4_mgr_core.sv $src/cores/axi4_sub_core.sv \
  $here/axi4_stream_chk.sv $here/axi4_slice_fv.sv $here/axi4_fv.sv > $work/$top.v
cat > $work/${top}_$mode.sby <<SBY
[options]
mode $mode
depth $depth
${abc:+vcd_sim on}

[engines]
$engine

[script]
read_verilog -sv -formal $top.v
${FV_CHPARAM:+chparam $FV_CHPARAM $top}
prep -top $top
${abc:+flatten; opt -full; techmap; opt -fast; setundef -anyseq}

[files]
$work/$top.v
SBY
cd $work && rm -rf ${top}_$mode && sby -f ${top}_$mode.sby > ${top}_$mode.log 2>&1 && rc=0 || rc=$?
tail -3 $work/${top}_$mode.log
exit $rc
