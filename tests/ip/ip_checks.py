"""Checks of the reference-IP tests (tests/ip/flow.yaml), called from pytask
bodies: the emitted netlist against a hand-written one, and Yosys synthesis of
the emitted netlist with the IP's RTL."""
import os
import re
import subprocess

from dv_flow.mgr import TaskDataResult


def _files(input):
    for fs in input.inputs:
        for f in getattr(fs, "files", []):
            yield os.path.join(fs.basedir, f)


def _norm(text):
    return " ".join(re.sub(r"//[^\n]*", "", text).split())


def netlist(input, module, ref):
    """The emitted <module>.sv equals `ref` (relative to tests/ip) after removing
    comments and normalizing whitespace."""
    got = [p for p in _files(input) if os.path.basename(p) == module + ".sv"]
    ref = os.path.join(input.srcdir, ref)
    if not got:
        print("netlist: no emitted %s.sv" % module)
        return TaskDataResult(status=1)
    if _norm(open(got[0]).read()) != _norm(open(ref).read()):
        print("netlist: %s differs from %s" % (got[0], ref))
        return TaskDataResult(status=1)
    print("netlist: PASS (%s matches %s)" % (got[0], ref))
    return TaskDataResult(status=0)


def _for_yosys(path, rundir):
    """Yosys 0.70 cannot run $error in an initial block's for loop (verilog-axi's
    parameter checks): a copy in which $error is $display. The checks still run;
    a failing one stops synthesis at its $finish."""
    text = open(path).read()
    if "$error(" not in text:
        return path
    out = os.path.join(rundir, "yosys_" + os.path.basename(path))
    open(out, "w").write(text.replace("$error(", "$display("))
    return out


def synth(input, top):
    """Yosys synthesis of the emitted <top>.sv with the RTL (.v) it instantiates."""
    srcs = [_for_yosys(p, input.rundir) for p in _files(input)
            if os.path.basename(p) == top + ".sv" or p.endswith(".v")]
    log = os.path.join(input.rundir, "yosys.log")
    cmd = ["yosys", "-q", "-l", log, "-p",
           "read_verilog -sv %s; synth -top %s; stat" % (" ".join(srcs), top)]
    rc = subprocess.run(cmd, cwd=input.rundir).returncode
    print("synth %s: %s (log %s)" % (top, "PASS" if rc == 0 else "FAIL", log))
    return TaskDataResult(status=rc)
