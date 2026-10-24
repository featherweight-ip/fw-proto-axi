#!/usr/bin/env bash
#****************************************************************************
#* ci/run.sh -- the checks CI runs on every commit.
#*
#* A workflow file calls this and nothing else, so what a check IS lives in
#* one place. It runs unchanged on a laptop, which is how it gets debugged.
#*
#*   1. bootstrap -- ivpm into a venv, `ivpm update` of the dep-set, then
#*      fw-hdl's dfm plugin (ivpm does not install it)
#*   2. dfm run lint-rtl, tests, fv-cover, fv-prove, fv-teeth (and fv, the
#*      ~6.5 min BMC, when CI_FV_BMC=1) -- each under a timeout, each with
#*      its own --report bundle; all always run, so one failing does not
#*      hide another
#*   3. collect   -- the lint SARIF/JSON and the test JUnit/CTRF files into
#*      $CI_REPORTS
#*
#* Exit status is nonzero iff any check failed (or bootstrap did).
#*
#* Environment:
#*   CI_DEP_SET   ivpm dep-set to fetch (default: dev)
#*   CI_REPORTS   where the reports are collected (default: ci-reports)
#*   CI_FV_BMC=1  also run `dfm run fv` (formal BMC, ~6.5 min)
#*   CI_TIMEOUT   per-check timeout in seconds (default: 900)
#*   IVPM_CACHE   ivpm's package cache (default: ~/.cache/ivpm)
#*   CI_SKIP_BOOTSTRAP=1
#*                use packages/ as it is -- on a laptop that already has it,
#*                this is just the checks and the reports
#****************************************************************************
set -u -o pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

dep_set="${CI_DEP_SET:-dev}"
reports="${CI_REPORTS:-ci-reports}"
tmo="${CI_TIMEOUT:-900}"
export IVPM_CACHE="${IVPM_CACHE:-$HOME/.cache/ivpm}"
mkdir -p "$IVPM_CACHE"

group()    { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }

# ---- 1. bootstrap ----------------------------------------------------------
if [ "${CI_SKIP_BOOTSTRAP:-0}" != "1" ]; then
    group "bootstrap: ivpm update -d $dep_set"
    if ! command -v direnv >/dev/null 2>&1; then
        # packages/packages.envrc is written for direnv, so the environment a
        # developer gets from `direnv allow` is the one CI gets too.
        sudo=""
        [ "$(id -u)" = "0" ] || sudo="sudo"
        $sudo apt-get update -qq && $sudo apt-get install -y -qq direnv >/dev/null \
            || { echo "::error::could not install direnv"; exit 1; }
    fi
    python3 -m venv .ci-venv \
        && .ci-venv/bin/pip install -q --upgrade pip ivpm uv \
        || { echo "::error::could not install ivpm"; exit 1; }
    # -a: clone git URLs as written (HTTPS); a runner has no ssh identity.
    .ci-venv/bin/ivpm update -a -d "$dep_set" \
        || { echo "::error::ivpm update -d $dep_set failed"; exit 1; }
    # fw-hdl's dfm plugin (fw.hdl.* tasks); the packages venv has no pip.
    .ci-venv/bin/uv pip install --python packages/python/bin/python --no-deps \
        -e packages/fw-hdl/python \
        || { echo "::error::could not install the fw-hdl dfm plugin"; exit 1; }
    direnv allow . || exit 1
    endgroup
fi

# ---- 2. the checks ----------------------------------------------------------
rm -rf "$reports"
mkdir -p "$reports"

declare -A status
run_check() {
    local verb="$1"
    group "dfm run $verb"
    # timeout: a task-graph cycle makes dfm hang instead of exiting.
    timeout "$tmo" direnv exec . dfm run "$verb" -u log --report "$reports/$verb"
    status[$verb]=$?
    endgroup
    if [ -f "$reports/$verb/report.md" ]; then
        group "report: $verb (status ${status[$verb]})"
        cat "$reports/$verb/report.md"
        endgroup
    fi
}

checks=(lint-rtl tests fv-cover fv-prove fv-teeth)
[ "${CI_FV_BMC:-0}" = "1" ] && checks+=(fv)
for c in "${checks[@]}"; do run_check "$c"; done

# ---- 3. collect -------------------------------------------------------------
copy_first() {
    local pattern="$1" dest="$2" f
    f=$(ls -1 $pattern 2>/dev/null | head -1)
    [ -n "$f" ] && mkdir -p "$dest" && cp "$f" "$dest"
}
copy_first "rundir/*/lint.sarif"      "$reports/lint-rtl/"
copy_first "rundir/*/lint.json"       "$reports/lint-rtl/"
copy_first "rundir/*.tests/junit.xml" "$reports/tests/"
copy_first "rundir/*.tests/ctrf.json" "$reports/tests/"

verdict() { [ "${status[$1]}" = "0" ] && echo "pass" || echo "FAIL (status ${status[$1]})"; }

rc=0
for c in "${checks[@]}"; do
    printf '%-10s %s\n' "$c:" "$(verdict $c)"
    [ "${status[$c]}" = "0" ] || rc=1
done
exit $rc
