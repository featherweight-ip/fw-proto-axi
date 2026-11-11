"""fw_proto weavers: golden output and a Verilator -Wall lint of the woven code.

Goldens are refreshed with FW_PROTO_REGEN=1 and reviewed in the diff."""
import os
import shutil
import subprocess

import pytest

from sv_weave.config import parse_config
from sv_weave.run import run

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
GOLDEN = os.path.join(HERE, "golden")
# fw_proto_pkg builds on fw-hdl's component model (fw_hdl_pkg).
HDL = os.path.join(ROOT, "packages", "fw-hdl", "src")
INCDIRS = [HDL, os.path.join(ROOT, "fw_proto", "src")]
INC_ARGS = ["+incdir+" + d for d in INCDIRS]
HDL_SOURCES = [os.path.join(HDL, f) for f in (
    "fw_clock_xtor_if.sv", "fw_clock_period_xtor_if.sv", "fw_hdl_pkg.sv")]
DEFS = os.path.join(ROOT, "src/core/fw_proto_axi4_defs_pkg.sv")
# fw-hdl, the runtime and the AXI4 core: what every weave here reads.
BASE = HDL_SOURCES + [os.path.join(ROOT, "fw_proto/src/fw_proto_pkg.sv"), DEFS,
                      os.path.join(ROOT, "src/core/fw_proto_axi4_core_pkg.sv")]
SOURCES = BASE + [os.path.join(ROOT, "tests/weave/synth/weave_synth_pkg.sv")]
CFG = """
sv-weave:
  binding: fw_proto_weave:FwProtoBinding
  plugin-path: [%s]
  weavers:
  - name: fw_proto_weave:FwProtoWeaver
""" % os.path.join(ROOT, "fw_proto", "python")


@pytest.fixture(scope="module")
def woven(tmp_path_factory):
    from sv_weave.filelist import SourceSpec
    out = str(tmp_path_factory.mktemp("woven"))
    spec = SourceSpec()
    spec.files.extend(SOURCES)
    spec.incdirs.extend(INCDIRS)
    res = run(parse_config(CFG, base_dir=ROOT), spec=spec, out_dir=out)
    return res


def _classes(text):
    return [l.split()[l.split().index("class") + 1] for l in text.splitlines()
            if " class " in " " + l and "endclass" not in l and l.strip()[:2] != "//"]


@pytest.mark.parametrize("pkg", ["fw_proto_axi4_defs_pkg_woven", "fw_proto_axi4_core_pkg_woven",
                                 "weave_synth_pkg_woven"])
def test_golden(woven, pkg):
    text = woven.file(pkg + ".sv").text
    path = os.path.join(GOLDEN, pkg + ".sv")
    if os.environ.get("FW_PROTO_REGEN"):
        with open(path, "w") as fp:
            fp.write(text)
    with open(path) as fp:
        assert text == fp.read(), "woven output differs from %s (FW_PROTO_REGEN=1 to refresh)" % path


def test_derived_classes(woven):
    names = _classes(woven.file("fw_proto_axi4_core_pkg_woven.sv").text)
    for api in ("axi4_req_if", "axi4_rsp_if", "axi4_xact_if"):
        for sfx in ("_listener", "_listener_base", "_listener_fanout", "_base", "_proxy", "_imp"):
            assert api + sfx in names
    for name in ("axi4_req_if_inbox", "axi4_rsp_if_inbox", "axi4_sp", "axi4_mgr_sp",
                 "axi4_sub_sp", "axi4_payloads"):
        assert name in names
    assert "axi4_req_if" in names and "axi4_rsp_if" in names


LINT_TOP = """
module lint_top;
  import fw_proto_axi4_defs_pkg::*;
  import fw_proto_axi4_core_pkg::*;
  import fw_proto_axi4_core_pkg_woven::*;
  import weave_synth_pkg_woven::*;
  localparam axi4_param_t P_MIN = '{ADDR_W: 32, DATA_W: 32, ID_W: 0, AWUSER_W: 0,
      WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0, HAS_QOS: 0, HAS_REGION: 0};
  localparam axi4_param_t P_WIDE = '{ADDR_W: 64, DATA_W: 512, ID_W: 8, AWUSER_W: 4,
      WUSER_W: 2, BUSER_W: 1, ARUSER_W: 3, RUSER_W: 5, HAS_QOS: 1, HAS_REGION: 1};
  axi4_xact_if_proxy #(P_MIN) x0 = new;
  axi4_xact_if_proxy #(P_WIDE) x1 = new;
  axi4_req_if_proxy #(P_MIN) q0 = new;
  axi4_rsp_if_listener_fanout #(P_WIDE) f1 = new;
  syn_if_proxy #(byte, 6) s0 = new;
endmodule
"""


def _verilator():
    pk = os.path.join(ROOT, "packages", "verilator", "bin", "verilator")
    return pk if os.path.exists(pk) else shutil.which("verilator")


@pytest.mark.skipif(_verilator() is None, reason="verilator not found")
def test_lint_wall(woven, tmp_path):
    top = tmp_path / "lint_top.sv"
    top.write_text(LINT_TOP)
    files = SOURCES + [os.path.join(woven.out_dir, n) for n in woven.compile_order
                       if n.endswith("_woven.sv")] + [str(top)]
    # UNDRIVEN: Verilator reports the outputs of pure virtual prototypes.
    # -Wno-fatal: fw_hdl_pkg carries warnings of its own; only the woven files count.
    cmd = [_verilator(), "--lint-only", "-Wall", "-Wno-fatal", "-Wno-UNUSEDPARAM",
           "-Wno-UNUSEDSIGNAL", "-Wno-UNDRIVEN",
           "--top-module", "lint_top"] + INC_ARGS + files
    r = subprocess.run(cmd, capture_output=True, text=True)
    woven_msgs = [l for l in r.stderr.splitlines() if "_woven.sv" in l]
    assert r.returncode == 0 and not woven_msgs, r.stderr[-3000:]


# ---- option xtor: the pin-level transactors (xtors.py) ---------------------------

RV = os.path.join(ROOT, "packages", "fw-hdl", "src", "std", "rv")
RV_SOURCES = [os.path.join(RV, "fw_rv_%s_xtor%s.sv" % (k, s))
              for k in ("initiator", "target", "monitor") for s in ("_if", "_core", "")]
XTOR_FILES = ["axi4_%s_xtor%s.sv" % (r, s) for r in ("mgr", "sub", "mon")
              for s in ("", "_core", "_if")]
XTOR_CFG = CFG + "    options: {xtor: true}\n"


@pytest.fixture(scope="module")
def woven_xtor(tmp_path_factory):
    from sv_weave.filelist import SourceSpec
    out = str(tmp_path_factory.mktemp("woven_xtor"))
    spec = SourceSpec()
    # The stub top keeps slang from elaborating the wrappers: slang 12.1 takes two
    # payload structs with the same members (aw_t, ar_t at default P) for one type
    # in an interface's type parameter and rejects the vif assignments. Verilator
    # checks the wrappers instead (test_xtor_lint_wall).
    spec.files.extend(BASE + RV_SOURCES + [os.path.join(ROOT, "src", "weave",
                                                               "xtor_weave_top.sv")])
    spec.incdirs.extend(INCDIRS)
    spec.tops = ["xtor_weave_top"]
    return run(parse_config(XTOR_CFG, base_dir=ROOT), spec=spec, out_dir=out)


def test_xtor_files(woven_xtor):
    assert woven_xtor.verify_status == "full"
    assert woven_xtor.compile_order[-9:] == sorted(XTOR_FILES)
    names = _classes(woven_xtor.file("fw_proto_axi4_core_pkg_woven.sv").text)
    for role in ("mgr", "sub", "mon"):
        assert "axi4_%s_xtor_chans" % role in names
        assert "axi4_%s_xtor_bridge" % role in names


@pytest.mark.parametrize("name", XTOR_FILES)
def test_xtor_golden(woven_xtor, name):
    text = woven_xtor.file(name).text
    path = os.path.join(GOLDEN, name)
    if os.environ.get("FW_PROTO_REGEN"):
        with open(path, "w") as fp:
            fp.write(text)
    with open(path) as fp:
        assert text == fp.read(), "woven output differs from %s (FW_PROTO_REGEN=1 to refresh)" % path


XTOR_LINT_TOP = """
module xtor_lint_top;
  import fw_proto_axi4_defs_pkg::*;
  import fw_proto_axi4_core_pkg::*;
  import fw_proto_axi4_core_pkg_woven::*;
  localparam axi4_param_t P_MIN = '{ADDR_W: 32, DATA_W: 32, ID_W: 0, AWUSER_W: 0,
      WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0, HAS_QOS: 0, HAS_REGION: 0};
  localparam axi4_param_t P_WIDE = '{ADDR_W: 64, DATA_W: 512, ID_W: 8, AWUSER_W: 4,
      WUSER_W: 2, BUSER_W: 1, ARUSER_W: 3, RUSER_W: 5, HAS_QOS: 1, HAS_REGION: 1};
  %s
endmodule
"""


@pytest.mark.skipif(_verilator() is None, reason="verilator not found")
def test_xtor_lint_wall(woven_xtor, tmp_path):
    """Each wrapper on its own (its pins left open) for P_MIN, P_DEF and P_WIDE, with
    its bridge: no -Wall finding in the generated files."""
    insts, i = [], 0
    for role in ("mgr", "sub", "mon"):
        for p in ("P_MIN", "AXI4_PARAM_DEFAULT", "P_WIDE"):
            insts.append("axi4_%s_xtor #(%s) u%d ();" % (role, p, i))
            insts.append("axi4_%s_xtor_bridge #(%s) b%d = new(u%d.u_if);" % (role, p, i, i))
            i += 1
    top = tmp_path / "xtor_lint_top.sv"
    top.write_text(XTOR_LINT_TOP % "\n  ".join(insts))
    files = (BASE + RV_SOURCES
             + [os.path.join(woven_xtor.out_dir, n) for n in woven_xtor.compile_order
                if n.endswith(".sv") and n != "sv_weave_init.sv"] + [str(top)])
    # -Wno-fatal: fw-hdl's rv interfaces carry warnings of their own (PROCASSINIT).
    cmd = [_verilator(), "--lint-only", "-Wall", "-Wno-fatal", "--timing", "-Wno-UNUSEDPARAM",
           "-Wno-UNUSEDSIGNAL", "-Wno-UNDRIVEN", "-Wno-PINMISSING",
           "--top-module", "xtor_lint_top"] + INC_ARGS + files
    r = subprocess.run(cmd, capture_output=True, text=True)
    gen = tuple(XTOR_FILES) + ("_woven.sv",)
    msgs = [l for l in r.stderr.splitlines() if l.startswith("%") and any(g in l for g in gen)]
    errs = [l for l in r.stderr.splitlines() if l.startswith("%Error")]
    assert r.returncode == 0 and not msgs and not errs, r.stderr[-3000:]


def _sv2v():
    pk = os.path.join(ROOT, "packages", "yosys", "bin", "sv2v")
    return pk if os.path.exists(pk) else shutil.which("sv2v")


@pytest.mark.skipif(_sv2v() is None, reason="sv2v not found")
def test_xtor_cores_class_free(woven_xtor, tmp_path):
    """The synthesizable layer reads into an RTL flow: sv2v converts the class-free
    package, its woven part, fw-hdl's rv cores and the generated cores, with no
    class package in the list."""
    gen = [os.path.join(woven_xtor.out_dir, n) for n in
           ["fw_proto_axi4_defs_pkg_woven.sv"] + [f for f in XTOR_FILES if f.endswith("_core.sv")]]
    rv = [f for f in RV_SOURCES if f.endswith("_core.sv")]
    r = subprocess.run([_sv2v(), DEFS] + gen + rv, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr[-3000:]
    for role in ("mgr", "sub", "mon"):
        assert "module axi4_%s_xtor_core" % role in r.stdout

