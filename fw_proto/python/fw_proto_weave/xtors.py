"""Pin-level transactors of a bundle (design §4.5, §5): the role wrappers and their
bridges. Emitted only when the weaver's ``xtor`` option is on, because they need
fw-hdl's ready/valid kit (``fw-hdl.hdl.rv-src``). The bundle must name its
class-free package (``fw_defs_pkg``), which the synthesizable cores import.

    <proto>_<payload>_bits(P)    function (item of ``<fw_defs_pkg>_woven``, emitted
                                 whenever ``fw_defs_pkg`` is set): a payload's width
    <proto>_<role>_xtor_core #(P)  module, one per role and one for the monitor
                                 (``mon``), synthesizable, class-free: an fw-hdl rv
                                 core per channel (initiator for the channels the role
                                 sends, target for the ones it receives, monitor for
                                 all of them in ``mon``), the flat payloads spliced
                                 onto the pins. Pin names are the field table's
                                 (``<ch><member>``, ``<ch>valid``, ``<ch>ready``);
                                 absent fields (fw_opt) keep their pin, tied to 0.
                                 Clock and reset come from the bundle's ``fw_clock``
                                 and ``fw_reset_n`` (or active-high ``fw_reset``).
                                 ``<ch>_up_*`` link each core to the class side.
    <proto>_<role>_xtor #(P)     module: the core plus one fw-hdl rv interface per
                                 channel on its links; the same pins.
    <proto>_<role>_xtor_if #(P)  interface (``u_if`` in the module): the class side,
                                 one vif for the bridge. Its ``chans`` (a
                                 ``<proto>_<role>_xtor_chans`` class, in the woven
                                 package, since an interface may not hold vifs) has the
                                 channel transactors' handles; ``bound`` rises once set
    <proto>_<role>_xtor_bridge   class (package item): the pins as the role's
                                 channel APIs. Outbound, ``<ch>(t)`` is
                                 ``vif.chans.<ch>.send(t)``; inbound, ``run()`` forks one
                                 ``recv -> m_<api>.<ch>(t)`` loop per channel.
    <proto>_mon_xtor_bridge      class: ``run()`` forks one loop per channel and
                                 calls ``<ch>_pre`` on the first valid cycle of a
                                 beat and ``<ch>_post`` on its handshake, on the
                                 ``req``/``rsp`` listener fan-outs.

Only ``fw_rv_ch`` channels are supported. The SV text is in ``templates/xtors/``;
here are the checks, the widths and the view objects the templates read.
"""
import re
from typing import List, Tuple

from .bundle import Bundle, Channel
from .ports import _opt_cond
from .sv import args_unused

RV_FAMILY = "fw_rv_ch"
MON = "mon"
_VEC = re.compile(r"^(logic|bit|reg)\b(.*)$")


def xtor_name(b: Bundle, role: str) -> str:
    return "%s_%s_xtor" % (b.proto, role)


def api_names(b: Bundle) -> Tuple[str, str]:
    return "%s_req_if" % b.proto, "%s_rsp_if" % b.proto


def _sends(b: Bundle, role: str, c: Channel) -> bool:
    """True if ``role`` drives the channel's valid and payload."""
    return c.fwd == (role == b.roles[0])


def _kind(b: Bundle, role: str, c: Channel) -> str:
    if role == MON:
        return "monitor"
    return "initiator" if _sends(b, role, c) else "target"


def _pin_type(member_type: str) -> str:
    """The pin's type: a vector as written, anything else as a vector of its width,
    so enum-typed members connect to plain nets."""
    m = _VEC.match(member_type.strip())
    if m:
        return "logic" + m.group(2)
    return "logic [$bits(%s)-1:0]" % member_type.strip()


def _clock_reset(b: Bundle) -> Tuple[str, str, str]:
    """(clock pin, reset pin, active-high reset expression)."""
    if b.reset_n:
        return b.clock, b.reset_n, "!" + b.reset_n
    return b.clock, b.reset, b.reset


def check(b: Bundle, err) -> bool:
    bad = [c.name for c in b.channels if c.family != RV_FAMILY]
    if bad:
        err("%s: xtor: only %s channels are supported (not %s)"
            % (b.decl_name, RV_FAMILY, ", ".join(bad)))
        return False
    if len(b.roles) != 2 or MON in b.roles:
        err("%s: xtor: needs exactly two roles, neither named '%s'" % (b.decl_name, MON))
        return False
    if not b.defs_pkg or _param_type(b) is None:
        err("%s: xtor: needs fw_defs_pkg (the class-free package of its parameters) and"
            " one struct parameter" % b.decl_name)
        return False
    return True


# ---- what the templates (templates/xtors/) read ------------------------------------
class _Member:
    """One payload member of a channel: its LSB in the flat payload, and the assign
    that splices it onto its pin (the fw_opt guard applied)."""

    def __init__(self, b: Bundle, ch: "_Chan", i: int):
        m = ch.c.members[i]
        later = [_width(x.type) for x in ch.c.members[i + 1:]]
        self.up = m.name.upper()
        self.lsb = " + ".join(later) if later else "0"
        pin = "%s%s" % (ch.name, m.name)
        fld = "%s_d[%s_%s_LSB +: %s]" % (ch.name, ch.up, self.up, _width(m.type))
        src, self.lhs = (fld, pin) if ch.kind == "initiator" else (pin, fld)
        opt = m.attrs.get("fw_opt")
        self.rhs = src if opt is None else "(%s) ? %s : '0" % (_opt_cond(b, opt), src)


class _Chan:
    """One channel, as one role's transactor sees it."""

    def __init__(self, b: Bundle, role: str, c: Channel):
        self.c = c
        self.name, self.payload, self.payload_name = c.name, c.payload, c.payload_name
        self.kind = _kind(b, role, c)
        self.up = c.name.upper()
        self.verb = {"initiator": "sent", "target": "received", "monitor": "observed"}[self.kind]
        self.bits_fn = bits_fn(b, c)
        self.vif_type = "fw_rv_%s_xtor_if #(%s)" % (self.kind, c.payload_name)
        sigs = ["up_valid", "up_ready"] + (["up_first", "up_xfer"]
                                           if self.kind == "monitor" else [])
        self.up_sigs = ["%s_%s" % (c.name, s) for s in sigs]
        self.links = [".%s_%s(%s_%s)" % (c.name, s, c.name, s) for s in ["up_data"] + sigs]
        clk, rst_hi = b.clock, _clock_reset(b)[2]
        self.if_conns = [".clock(%s)" % clk, ".reset(%s)" % rst_hi] + [
            ".%s(%s_%s)" % (s, c.name, s) for s in ["up_data"] + sigs]
        core = ["up_data", "up_valid"] + (["up_first", "up_xfer"]
                                          if self.kind == "monitor" else []) + ["up_ready"]
        self.core_conns = ([".clock(%s)" % clk, ".reset(%s)" % rst_hi]
                           + [".%s(%s_%s)" % (s, c.name, s) for s in core]
                           + [".data(%s_d)" % c.name, ".valid(%svalid)" % c.name,
                              ".ready(%sready)" % c.name])
        api = api_names(b)[0 if c.fwd else 1]
        self.api_spec = b.spec(api)
        self.fan = "req" if c.fwd else "rsp"
        self.members = [_Member(b, self, i) for i in range(len(c.members))]


class XtorView:
    """What the xtors/ templates read for one role (or mon) of a bundle."""

    def __init__(self, b: Bundle, role: str, pkg: str = ""):
        self.role = role
        self.name = xtor_name(b, role)
        self.header, self.params_ref, self.struct_param = b.header, b.params_ref, b.struct_param
        self.chans = [_Chan(b, role, c) for c in b.channels]
        # Run-time knobs by path, "<ch>.<knob>": the monitor has a queue depth only;
        # initiators and targets also have max_gap (their stall setting).
        self.knobs = ["depth"] if role == MON else ["depth", "max_gap"]
        self.chans_args = ["virtual %s %s_" % (c.vif_type, c.name) for c in self.chans]
        self.chan_ifs = ["u_%s_if" % c.name for c in self.chans]
        self.links = [l for c in self.chans for l in c.links]
        self.what = _what(b, role)
        self.dp = b.defs_pkg
        self.imports = _imports(b, pkg) if pkg else ""
        self.pins = _ports(b, role, False)
        self.core_pins = _ports(b, role, True)
        self.vif = "virtual %s_if %s" % (self.name, b.params_ref)
        req, rsp = api_names(b)
        self.req_fanout = b.spec(req + "_listener_fanout")
        self.rsp_fanout = b.spec(rsp + "_listener_fanout")
        if role != MON:
            self.sends = [c for c in self.chans if _sends(b, role, c.c)]
            self.recvs = [c for c in self.chans if not _sends(b, role, c.c)]
            self.out_api, self.in_api = (req, rsp) if role == b.roles[0] else (rsp, req)
            self.out_spec, self.in_spec = b.spec(self.out_api), b.spec(self.in_api)
            self.in_arg = self.in_api[len(b.proto) + 1:-3]                  # rsp / req
            self.in_var = "m_" + self.in_arg


def render_chans(d, b: Bundle, role: str) -> str:
    """The channel transactors' handles (a class: an interface may not hold vifs)."""
    return d.render("xtors/chans.sv.j2", x=XtorView(b, role))


# ---- the class-free (synthesizable) layer -----------------------------------------
def check_defs(b: Bundle, err) -> bool:
    if _param_type(b) is None:
        err("%s: fw_defs_pkg needs a bundle with one struct parameter" % b.decl_name)
        return False
    return True


_RANGE = re.compile(r"^(?:logic|bit|reg)\s*\[(?P<msb>.+):\s*(?P<lsb>\d+)\s*\]$")
_PARAM = re.compile(r"#\s*\(\s*(?:parameter\s+)?(?P<type>\w+)\s+(?P<name>\w+)\b")


def _param_type(b: Bundle):
    """The type of the bundle's one struct parameter (``axi4_param_t``)."""
    m = _PARAM.search(b.header)
    return m.group("type") if m and b.struct_param == m.group("name") else None


def _width(type_text: str) -> str:
    """The bit width of a member type, as an expression of the parameter."""
    t = type_text.strip()
    m = _RANGE.match(t)
    if m:
        msb, lsb = m.group("msb").strip(), int(m.group("lsb"))
        if msb.isdigit():
            return str(int(msb) - lsb + 1)
        mm = re.match(r"^(.*?)\s*-\s*1$", msb)
        if mm and lsb == 0:
            return "(%s)" % mm.group(1)
        return "((%s) - %d + 1)" % (msb, lsb)
    if t in ("logic", "bit", "reg"):
        return "1"
    return "$bits(%s)" % t


def bits_fn(b: Bundle, c: Channel) -> str:
    return "%s_%s_bits" % (b.proto, c.payload_name)


def render_bits_fns(b: Bundle) -> str:
    """Package item for the bundle's class-free package: the width of each payload
    struct, as a function of the parameter, so RTL can size a payload without the
    class layer."""
    out = ["// Bits of each %s payload, packed as its struct: members MSB first, in"
           % b.decl_name,
           "// declaration order, absent (fw_opt) members held at their one-bit width."]
    seen = set()
    for c in b.channels:
        if c.payload_name in seen:
            continue
        seen.add(c.payload_name)
        out += ["function automatic int unsigned %s(%s %s);"
                % (bits_fn(b, c), _param_type(b), b.struct_param),
                "    return %s;" % " + ".join(_width(m.type) for m in c.members),
                "endfunction"]
    return args_unused("\n".join(out))


def _ports(b: Bundle, role: str, uplink: bool) -> List[str]:
    """The pins (and, for the core, the link to the class side), comma-joined."""
    clk, rst, _ = _clock_reset(b)
    ports = ["    input  logic %s" % clk, "    input  logic %s" % rst]
    for c in b.channels:
        # valid and the payload go one way, ready the other; all in for the monitor
        fwd = "input " if role == MON or not _sends(b, role, c) else "output"
        rev = "input " if role == MON or _sends(b, role, c) else "output"
        ports += ["",
                  "    %s logic %svalid" % (fwd, c.name),
                  "    %s logic %sready" % (rev, c.name)]
        ports += ["    %s %s %s%s" % (fwd, _pin_type(m.type), c.name, m.name) for m in c.members]
    if uplink:
        ports.append("")
        for c in b.channels:
            kind = _kind(b, role, c)
            d, r = ("input ", "output") if kind == "initiator" else ("output", "input ")
            ports += ["    %s logic [%s(%s)-1:0] %s_up_data" % (d, bits_fn(b, c), b.struct_param, c.name),
                      "    %s logic %s_up_valid" % (d, c.name)]
            if kind == "monitor":
                ports += ["    output logic %s_up_first" % c.name,
                          "    output logic %s_up_xfer" % c.name]
            ports.append("    %s logic %s_up_ready" % (r, c.name))
    body = []
    real = [i for i, p in enumerate(ports) if p]
    for i, p in enumerate(ports):
        body.append(p + ("," if i != real[-1] else "") if p else "")
    return body


def _what(b: Bundle, role: str) -> str:
    if role == MON:
        return "Passive monitor of one %s link: every pin is an input" % b.decl_name
    return "The %s side of %s" % (role, b.decl_name)


def _imports(b: Bundle, pkg: str) -> str:
    return "import %s::*, %s_woven::*, %s::*, %s_woven::*;" % (b.defs_pkg, b.defs_pkg, pkg, pkg)


def render_xtor_core(d, b: Bundle, role: str) -> str:
    """The synthesizable part of a role's transactor: one fw-hdl rv core per channel,
    the payloads (flat, in their structs' layout) spliced onto the pins. No classes:
    it reads only the bundle's class-free package and its woven part."""
    return d.render("xtors/core.sv.j2", x=XtorView(b, role))


def render_xtor_if(d, b: Bundle, role: str, pkg: str) -> str:
    return d.render("xtors/if.sv.j2", x=XtorView(b, role, pkg))


def render_xtor_module(d, b: Bundle, role: str, pkg: str) -> str:
    """The role's transactor for simulation: the core (``<name>_core``) plus one
    fw-hdl rv interface per channel, the class side's handles."""
    return d.render("xtors/module.sv.j2", x=XtorView(b, role, pkg))


def render_role_bridge(d, b: Bundle, role: str) -> str:
    return d.render("xtors/role_bridge.sv.j2", x=XtorView(b, role))


def render_mon_bridge(d, b: Bundle) -> str:
    return d.render("xtors/mon_bridge.sv.j2", x=XtorView(b, MON))


def render_files(d, b: Bundle, pkg: str) -> List[Tuple[str, str]]:
    """[(file name, text)]: per role (and mon), the core, the interface and the
    module, one declaration per file, named after it."""
    out = []
    for role in list(b.roles) + [MON]:
        name = xtor_name(b, role)
        out.append((name + "_core.sv", render_xtor_core(d, b, role)))
        out.append((name + "_if.sv", render_xtor_if(d, b, role, pkg)))
        out.append((name + ".sv", render_xtor_module(d, b, role, pkg)))
    return out


def render_bridges(d, b: Bundle) -> List[str]:
    """Package items: per role (and mon), the chans class; then the bridges."""
    roles = list(b.roles) + [MON]
    return ([render_chans(d, b, r) for r in roles]
            + [render_role_bridge(d, b, r) for r in b.roles] + [render_mon_bridge(d, b)])
