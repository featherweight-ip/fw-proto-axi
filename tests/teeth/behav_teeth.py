#!/usr/bin/env python3
"""Teeth for the behaviour package: plant a bug, run the suites, restore.

Each mutant is one text edit to a file under src/behav. For every mutant the
script applies the edit, runs each selected run through dfm, records whether
the run caught it (any test failed, or the run did not pass), and puts the
file back. A run that does not build is reported as such: a mutant that does
not compile tests nothing.

    python3 tests/teeth/behav_teeth.py               # all mutants, all runs
    python3 tests/teeth/behav_teeth.py -m mgr_drop_b # one mutant
    python3 tests/teeth/behav_teeth.py --baseline    # unmutated runs only
    python3 tests/teeth/behav_teeth.py --list

Logs go to rundir/teeth/<mutant>/<run>.log; the summary table is printed and
written to rundir/teeth/summary.md. Run from the repo root (dfm finds the
flow there). The runs share run directories, so do not run two at once.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BEHAV = os.path.join(ROOT, "src", "behav")
RUNDIR = os.path.join(ROOT, "rundir")
OUT = os.path.join(RUNDIR, "teeth")
TIMEOUT_S = 1200

# name -> (dfm task, how to read its result)
RUNS = {
    "l2_ns-tlm":      ("fw.proto.axi.suites.l2-ns-run.tlm", "svunit"),
    "l2_ns-xtor":     ("fw.proto.axi.suites.l2-ns-run.xtor", "svunit"),
    "l2_mem_ns-tlm":  ("fw.proto.axi.suites.l2-mem-ns-run.tlm", "svunit"),
    "l2_mem_ns-xtor": ("fw.proto.axi.suites.l2-mem-ns-run.xtor", "svunit"),
    "ip-crossbar":    ("fw.proto.axi.ip.axi-crossbar-run", "ip:axi_crossbar"),
}


class Mutant:
    def __init__(self, name, path, old, new, what, gap=None):
        self.name, self.path, self.old, self.new, self.what = name, path, old, new, what
        # A known gap: why no run is expected to catch it (reported, not failed).
        self.gap = gap


# The D11 paths: the request/response split, responses inside or after the
# request call, per-ID order, and the response senders.
MUTANTS = [
    Mutant("blk_wr_queue_late", "axi4_burst_blocking.svh",
           "        m_wr[pl::aw_mask(aw).id].push_back(p);\n"
           "        req.write_burst(aw, w);\n",
           "        req.write_burst(aw, w);\n"
           "        m_wr[pl::aw_mask(aw).id].push_back(p);\n",
           "blocking shim queues a write's waiter after the request goes, so a "
           "B inside the call finds no waiter"),
    Mutant("blk_rd_done_first", "axi4_burst_blocking.svh",
           "        if (r.last) begin\n            void'(m_rd[r.id].pop_front());",
           "        if (1) begin\n            void'(m_rd[r.id].pop_front());",
           "blocking shim completes a read on its first R beat"),
    Mutant("mgr_wr_count_late", "axi4_mgr_adapter.svh",
           "        m_wr[a.id]++;\n        m_n_out++;\n        req.aw(a);\n"
           "        foreach (w[i]) req.w(pl::w_mask(w[i]));\n",
           "        req.aw(a);\n        foreach (w[i]) req.w(pl::w_mask(w[i]));\n"
           "        m_wr[a.id]++;\n        m_n_out++;\n",
           "manager adapter counts a write after its beats go, so a B before "
           "the call returns is rejected"),
    Mutant("mgr_w_interleave", "axi4_mgr_adapter.svh",
           "local semaphore        m_wr_sem = new(1);",
           "local semaphore        m_wr_sem = new(64);",
           "manager adapter lets concurrent writes interleave their W beats"),
    Mutant("mgr_drop_b", "axi4_mgr_adapter.svh",
           "        up.write_resp(t);\n",
           "        // up.write_resp(t);\n",
           "manager adapter does not pass B up"),
    Mutant("sub_rd_count_late", "axi4_sub_adapter.svh",
           "        m_rd[t.id].push_back(axi4_burst_beats(t.len));\n"
           "        m_n_active++;\n        tgt.read_burst(t);\n",
           "        tgt.read_burst(t);\n"
           "        m_rd[t.id].push_back(axi4_burst_beats(t.len));\n"
           "        m_n_active++;\n",
           "subordinate adapter records a read after calling the target, so R "
           "beats inside the call are rejected"),
    Mutant("sub_b_inline", "axi4_sub_adapter.svh",
           "        m_wr[b.id]--;\n        m_b.push_back(b);\n        -> m_b_ev;\n"
           "        start();\n",
           "        m_wr[b.id]--;\n        rsp.b(pl::b_mask(b));\n"
           "        m_n_active--;\n",
           "subordinate adapter sends B from inside the response call (blocks "
           "on the pins, D11 rule 2)",
           gap="only slower in these topologies; it deadlocks only in a cycle "
               "(a response call that needs the caller's own channel drained), "
               "which is the deadlock-analysis follow-up (plan P6)"),
    Mutant("sub_r_interleave", "axi4_sub_adapter.svh",
           "        if (m_r_open && !r_interleave) begin\n",
           "        if (0) begin\n",
           "subordinate adapter interleaves R beats of different IDs with "
           "r_interleave off"),
    Mutant("bx_rd_no_turns", "axi4_burst_on_xact.svh",
           "        m_rd_turns.wait_turn(ar.id, t);\n",
           "",
           "xact target answers reads of one ID in completion order, not "
           "request order"),
    Mutant("bx_wr_no_turns", "axi4_burst_on_xact.svh",
           "        m_wr_turns.wait_turn(aw.id, t);\n",
           "",
           "xact target answers writes of one ID in completion order, not "
           "request order"),
]


def result(run, kind):
    """'pass', 'CAUGHT (<detail>)' or 'no result' from a run's sim.log."""
    log = os.path.join(RUNDIR, run, "sim.log")
    if not os.path.exists(log):
        return "no result"
    with open(log, errors="replace") as f:
        text = f.read()
    if kind == "svunit":
        failed = sorted(set(re.findall(r"\]: (\w+)::FAILED", text)))
        m = re.search(r"(PASSED|FAILED) \((\d+) of (\d+) tests passing\)", text)
        if m and m.group(1) == "PASSED" and m.group(2) == m.group(3) and not failed:
            return "pass"
        detail = ", ".join(failed[:4]) + (" ..." if len(failed) > 4 else "")
        if not detail:
            fat = re.search(r"%Fatal: (.*)", text)
            detail = fat.group(1).strip()[:70] if fat else "did not finish"
        return "CAUGHT (%s)" % detail
    ip = kind.split(":", 1)[1]
    if re.search(r"\[%s\] PASS\b" % ip, text):
        return "pass"
    m = re.search(r"\[%s\] (FAIL[^\n]*|TIMEOUT[^\n]*)" % ip, text)
    return "CAUGHT (%s)" % (m.group(1).strip()[:70] if m else "did not finish")


def run_one(name, log_path):
    task, kind = RUNS[name]
    rd = os.path.join(RUNDIR, task)
    # A stale sim.log would read as this run's result if the build fails.
    for f in ("sim.log",):
        p = os.path.join(rd, f)
        if os.path.exists(p):
            os.remove(p)
    t0 = time.time()
    with open(log_path, "w") as log:
        try:
            subprocess.run(["dfm", "run", task], cwd=ROOT, stdout=log,
                           stderr=subprocess.STDOUT, timeout=TIMEOUT_S)
        except subprocess.TimeoutExpired:
            return "CAUGHT (wall-clock timeout)", time.time() - t0
    return result(task, kind), time.time() - t0


def run_set(label, runs, rows):
    os.makedirs(os.path.join(OUT, label), exist_ok=True)
    row = {}
    for r in runs:
        res, dt = run_one(r, os.path.join(OUT, label, r + ".log"))
        row[r] = res
        print("  %-18s %-16s %s  (%.0fs)" % (label, r, res, dt), flush=True)
    rows.append((label, row))
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-m", "--mutant", action="append", help="mutant(s) to run")
    ap.add_argument("-r", "--run", action="append", choices=list(RUNS),
                    help="run(s) to use (default: all)")
    ap.add_argument("--baseline", action="store_true", help="unmutated runs only")
    ap.add_argument("--no-baseline", action="store_true",
                    help="skip the unmutated runs before the mutants")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()

    if a.list:
        for m in MUTANTS:
            print("%-18s %-26s %s%s" % (m.name, m.path, m.what,
                                        " [known gap]" if m.gap else ""))
        return 0

    names = {m.name for m in MUTANTS}
    for n in a.mutant or []:
        if n not in names:
            ap.error("unknown mutant %s" % n)
    mutants = [m for m in MUTANTS if not a.mutant or m.name in a.mutant]
    runs = a.run or list(RUNS)
    if os.path.exists(OUT) and not a.mutant and not a.run:
        shutil.rmtree(OUT)
    os.makedirs(OUT, exist_ok=True)

    # Check every edit applies before running anything.
    for m in mutants:
        with open(os.path.join(BEHAV, m.path)) as f:
            n = f.read().count(m.old)
        if n != 1:
            print("mutant %s: its text occurs %d times in %s" % (m.name, n, m.path))
            return 2

    rows = []
    if not a.no_baseline:
        base = run_set("baseline", runs, rows)
        bad = [r for r, v in base.items() if v != "pass"]
        if bad:
            print("baseline does not pass: %s" % ", ".join(bad))
            return 1
    if a.baseline:
        mutants = []

    for m in mutants:
        path = os.path.join(BEHAV, m.path)
        with open(path) as f:
            orig = f.read()
        try:
            with open(path, "w") as f:
                f.write(orig.replace(m.old, m.new))
            run_set(m.name, runs, rows)
        finally:
            with open(path, "w") as f:
                f.write(orig)

    lines = ["| mutant | " + " | ".join(runs) + " |",
             "|---|" + "---|" * len(runs)]
    missed, known = [], []
    gaps = {m.name: m.gap for m in MUTANTS}
    for label, row in rows:
        lines.append("| %s | %s |" % (label, " | ".join(row.get(r, "") for r in runs)))
        if label != "baseline":
            if any(v == "no result" for v in row.values()):
                missed.append(label + " (did not build)")
            elif not any(v.startswith("CAUGHT") for v in row.values()):
                (known if gaps.get(label) else missed).append(label)
    lines.append("")
    lines.append("Not caught: %s" % (", ".join(missed) if missed else "none"))
    for k in known:
        lines.append("Known gap, not caught: %s: %s" % (k, gaps[k]))
    text = "\n".join(lines) + "\n"
    with open(os.path.join(OUT, "summary.md"), "w") as f:
        f.write(text)
    print()
    print(text)
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
