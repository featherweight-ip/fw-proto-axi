#!/bin/bash
# Teeth check: plant one bug at a time in a copy of src and require the
# formal run to FAIL. A property set that passes a broken design proves
# nothing. Usage: teeth.sh <workdir>. (Mutants of the generated cores are in
# fv_b2b.sh teeth.)
#   slice mutants   unbounded proof of axi4_slice (axi4_slice_fv, abc pdr)
#   checker mutants an over-strict rule makes a legal cover unreachable
#                   (axi4_checker_fv, all rules assumed)
set -u
here=$(cd $(dirname $0) && pwd)
src=$here/../../src
work=${1:-$here/teeth_work}
rm -rf $work; mkdir -p $work
fails=0

# name ~ file (under src) ~ sed expression (no '~')  ~ top ~ mode ~ depth ~ engine
mutants=(
  "skid-refill-from-input~cores/axi4_slice.sv~s/out_data    <= skid_data;/out_data    <= in_data;/~axi4_slice_fv~prove~8~abc pdr"
  "ready-in-reset~cores/axi4_slice.sv~/assign in_ready/s/= aresetn \& /= /~axi4_slice_fv~prove~8~abc pdr"
  "skid-drops-beat~cores/axi4_slice.sv~s/skid_valid <= 1'b1;/skid_valid <= 1'b0;/~axi4_slice_fv~prove~8~abc pdr"
  "chk-wstrb-one-lane~checker/axi4_checker.sv~s/lanes\[i\] = (i >= lo) \&\& (i <= hi);/lanes[i] = (i == lo);/~axi4_checker_fv~cover~24~smtbmc boolector"
  "chk-rlast-first-beat~checker/axi4_checker.sv~s/rlast == (rq_cnt\[r_idx\] == rq_len\[r_idx\])/rlast == (rq_cnt[r_idx] == 8'd0)/~axi4_checker_fv~cover~24~smtbmc boolector"
)

for m in "${mutants[@]}"; do
  IFS='~' read -r name file expr top mode depth engine <<< "$m"
  d=$work/$name
  mkdir -p $d
  cp -r $src $d/src
  sed -i "$expr" $d/src/$file
  if cmp -s $src/$file $d/src/$file; then
    echo "TEETH $name: mutation did not apply -- FAIL"; fails=$((fails+1)); continue
  fi
  # Caught = sby says FAIL (a tool ERROR would be no evidence).
  FV_TOP=$top FV_ENGINE="$engine" $here/run_sby.sh $mode $depth $d/run $d/src > $d/log 2>&1
  if grep -q "DONE (FAIL" $d/log; then
    echo "TEETH $name: caught ($top $mode)"
  else
    echo "TEETH $name: NOT caught ($top $mode, $(tail -1 $d/log)) -- FAIL"; fails=$((fails+1))
  fi
done

if [ $fails -ne 0 ]; then echo "teeth: $fails mutant(s) survived"; exit 1; fi
echo "teeth: all ${#mutants[@]} mutants caught"
