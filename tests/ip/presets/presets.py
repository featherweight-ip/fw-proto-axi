"""Pin-map preset check (plan P6): the emitted preset_<tag>_sys netlists
against stub modules whose headers follow the AMBA AXI4 signal names.

The stub headers come from the table below (AMBA IHI0022, A2), not from the
bundle, so the check is independent of the field table the presets read.
Verilator lints each netlist with its stub: a pin the preset names that the
header lacks (PINNOTFOUND), a header pin left unconnected (PINMISSING), or a
width that differs (WIDTH) fails it. The emitter itself checks that every bit
of every field is mapped once.
"""
import os
import subprocess

from dv_flow.mgr import TaskDataResult

# The parameter sets, as in tests/env/axi4_test_params_pkg.sv.
PARAMS = {
    "def": dict(ADDR_W=32, DATA_W=64, ID_W=4, AWUSER_W=0, WUSER_W=0, BUSER_W=0,
                ARUSER_W=0, RUSER_W=0, HAS_QOS=1, HAS_REGION=1),
    "wide": dict(ADDR_W=64, DATA_W=512, ID_W=8, AWUSER_W=4, WUSER_W=2, BUSER_W=1,
                 ARUSER_W=3, RUSER_W=5, HAS_QOS=1, HAS_REGION=1),
}

# (signal, width from P, driven by the manager). A width of 0 means absent.
def _signals(p):
    qos = 4 if p["HAS_QOS"] else 0
    reg = 4 if p["HAS_REGION"] else 0
    sig = []
    for ch, user in (("AW", p["AWUSER_W"]), ("AR", p["ARUSER_W"])):
        sig += [(ch + "ID", p["ID_W"], 1), (ch + "ADDR", p["ADDR_W"], 1),
                (ch + "LEN", 8, 1), (ch + "SIZE", 3, 1), (ch + "BURST", 2, 1),
                (ch + "LOCK", 1, 1), (ch + "CACHE", 4, 1), (ch + "PROT", 3, 1),
                (ch + "QOS", qos, 1), (ch + "REGION", reg, 1), (ch + "USER", user, 1),
                (ch + "VALID", 1, 1), (ch + "READY", 1, 0)]
    sig += [("WDATA", p["DATA_W"], 1), ("WSTRB", p["DATA_W"] // 8, 1), ("WLAST", 1, 1),
            ("WUSER", p["WUSER_W"], 1), ("WVALID", 1, 1), ("WREADY", 1, 0)]
    sig += [("BID", p["ID_W"], 0), ("BRESP", 2, 0), ("BUSER", p["BUSER_W"], 0),
            ("BVALID", 1, 0), ("BREADY", 1, 1)]
    sig += [("RID", p["ID_W"], 0), ("RDATA", p["DATA_W"], 0), ("RRESP", 2, 0),
            ("RLAST", 1, 0), ("RUSER", p["RUSER_W"], 0), ("RVALID", 1, 0),
            ("RREADY", 1, 1)]
    return [s for s in sig if s[1] != 0]


def stub(tag):
    """Module preset_<tag>: a subordinate port (s_axi_) and a manager port
    (m_axi_), named in the tag's style; outputs tied to 0."""
    pset, style = tag.split("_")
    uc = style == "uc"
    p = PARAMS[pset]
    ports, outs = [], []
    ports.append("input  logic %s" % ("ACLK" if uc else "clk"))
    ports.append("input  logic %s" % ("ARESETN" if uc else "rst"))
    for pre, is_mgr in (("s_axi_", False), ("m_axi_", True)):
        for name, w, by_mgr in _signals(p):
            pin = (pre.upper() + name) if uc else (pre + name.lower())
            out = by_mgr == is_mgr
            rng = "" if w == 1 else "[%d:0] " % (w - 1)
            ports.append("%s logic %s%s" % ("output" if out else "input ", rng, pin))
            if out:
                outs.append(pin)
    lines = ["/* verilator lint_off UNUSEDSIGNAL */",
             "module preset_%s (" % tag,
             ",\n".join("    " + x for x in ports),
             ");"]
    lines += ["    assign %s = '0;" % o for o in outs]
    lines += ["endmodule", "/* verilator lint_on UNUSEDSIGNAL */", ""]
    return "\n".join(lines)


TAGS = ["def_lc", "def_uc", "wide_lc", "wide_uc"]


def check(input):
    emitted = {}
    for fs in input.inputs:
        for f in getattr(fs, "files", []):
            emitted[os.path.basename(f)] = os.path.join(fs.basedir, f)
    status = 0
    for tag in TAGS:
        sys_mod = "preset_%s_sys" % tag
        if sys_mod + ".sv" not in emitted:
            print("presets %s: no emitted %s.sv" % (tag, sys_mod))
            status = 1
            continue
        stub_path = os.path.join(input.rundir, "preset_%s.sv" % tag)
        with open(stub_path, "w") as f:
            f.write(stub(tag))
        log = os.path.join(input.rundir, "lint_%s.log" % tag)
        cmd = ["verilator", "--lint-only", "-Wno-lint", "-Wwarn-WIDTH",
               "-Wwarn-PINMISSING", "--top-module", sys_mod,
               emitted[sys_mod + ".sv"], stub_path]
        with open(log, "w") as f:
            rc = subprocess.run(cmd, cwd=input.rundir, stdout=f,
                                stderr=subprocess.STDOUT).returncode
        print("presets %s: %s (log %s)" % (tag, "PASS" if rc == 0 else "FAIL", log))
        if rc != 0:
            status = 1
            with open(log) as f:
                print("".join(f.readlines()[:20]))
    return TaskDataResult(status=status)
