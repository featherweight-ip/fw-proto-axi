#!/bin/bash
# Formal runs of the generated transactors' cores (axi4_fv.sv). The RTL comes
# from the task's inputs ($DFM_INPUTS, the woven-xtor weave): only the class-free
# files are taken -- the defs package and its woven part, and every *_xtor_core.sv
# (the generated cores and fw-hdl's rv cores they instantiate).
# Usage: fv_b2b.sh <bmc|cover|teeth> <depth> <workdir>
#   bmc    BMC of axi4_fv          cover  its covers (FV_COVER), all must be reached
#   teeth  planted bugs, one at a time in a copy of a core: each BMC must FAIL
set -eu
mode=$1; depth=$2; work=$3
here=$(cd $(dirname $0) && pwd)
src=$here/../../src
mkdir -p $work; work=$(cd $work && pwd)

mapfile -t rtl < <(python3 - <<'PY'
import json, os
seen, out = set(), []
for it in json.load(open(os.environ["DFM_INPUTS"])):
    base = it.get("basedir", "")
    for f in it.get("files", []):
        p = os.path.normpath(os.path.join(base, f))
        n = os.path.basename(p)
        if p in seen or not (n.startswith("fw_proto_axi4_defs_pkg") or n.endswith("_xtor_core.sv")):
            continue
        if n.startswith("fw_rv_") and not (n.startswith("fw_rv_initiator") or n.startswith("fw_rv_target")):
            continue
        if n.startswith("axi4_mon_"):
            continue
        seen.add(p); out.append(p)
# packages first: the defs package, then its woven part, then the modules
out.sort(key=lambda p: (0 if p.endswith("fw_proto_axi4_defs_pkg.sv") else
                        1 if p.endswith("fw_proto_axi4_defs_pkg_woven.sv") else 2, p))
print("\n".join(out))
PY
)
printf '%s\n' "${rtl[@]}" > $work/rtl.f

# run <dir> <mode> <defines> <files...>: sv2v + sby; returns sby's status
run() {
  local d=$1 m=$2 defs=$3; shift 3
  mkdir -p $d
  sv2v --exclude=Assert -DFORMAL $defs "$@" $src/checker/axi4_checker.sv \
    $here/axi4_stream_chk.sv $here/axi4_fv.sv > $d/axi4_fv.v
  cat > $d/fv.sby <<SBY
[options]
mode $m
depth $depth

[engines]
smtbmc boolector

[script]
read_verilog -sv -formal axi4_fv.v
prep -top axi4_fv

[files]
$d/axi4_fv.v
SBY
  (cd $d && rm -rf fv && sby -f fv.sby > fv.log 2>&1)
}

case $mode in
  bmc)   run $work/bmc bmc "" "${rtl[@]}" && rc=0 || rc=$?; tail -3 $work/bmc/fv.log; exit $rc ;;
  cover) run $work/cover cover -DFV_COVER "${rtl[@]}" && rc=0 || rc=$?; tail -3 $work/cover/fv.log; exit $rc ;;
  teeth) ;;
  *) echo "fv_b2b.sh: unknown mode $mode" >&2; exit 2 ;;
esac

# name ~ file (basename, among the inputs) ~ sed expression (no '~')
mutants=(
  "mgr-awlen-zero~axi4_mgr_xtor_core.sv~s/assign awlen = aw_d\[AW_LEN_LSB +: 8\];/assign awlen = 8'd0;/"
  "mgr-wlast-wrong-bit~axi4_mgr_xtor_core.sv~s/assign wlast = w_d\[W_LAST_LSB +: 1\];/assign wlast = w_d[W_LAST_LSB + 1 +: 1];/"
  "sub-bresp-exokay~axi4_sub_xtor_core.sv~s/assign bresp = b_d\[B_RESP_LSB +: \$bits(axi4_resp_e)\];/assign bresp = 2'b01;/"
  "rv-valid-in-reset~fw_rv_initiator_xtor_core.sv~s/assign valid = valid_q \& !reset;/assign valid = valid_q;/"
)
fails=0
for m in "${mutants[@]}"; do
  IFS='~' read -r name file expr <<< "$m"
  d=$work/$name; mkdir -p $d
  files=()
  hit=0
  for f in "${rtl[@]}"; do
    if [ "$(basename $f)" = "$file" ]; then
      sed "$expr" $f > $d/$file
      cmp -s $f $d/$file && { echo "teeth $name: the mutation did not apply"; fails=$((fails+1)); continue 2; }
      files+=($d/$file); hit=1
    else
      files+=($f)
    fi
  done
  [ $hit = 1 ] || { echo "teeth $name: $file not among the inputs"; fails=$((fails+1)); continue; }
  if run $d bmc "" "${files[@]}"; then
    echo "teeth $name: BMC PASSED a planted bug"; fails=$((fails+1))
  else
    echo "teeth $name: caught ($(grep -m1 -o 'Assert failed in [^:]*' $d/fv.log))"
  fi
done
exit $fails
