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

Only ``fw_rv_ch`` channels are supported.
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


def _typedefs(b: Bundle) -> List[str]:
    """``typedef <payload> <name>;`` per channel. The vif and transactor parameters
    use these names: Verilator (5.055) faults on a virtual interface whose type
    parameter is written as a class-scoped type of a parameter (``ty #(P)::b_t``)."""
    return ["    typedef %s %s;" % (c.payload, c.payload_name) for c in b.channels]


def render_chans(b: Bundle, role: str) -> str:
    """The channel transactors' handles (a class: an interface may not hold vifs)."""
    name = xtor_name(b, role) + "_chans"
    out = ["// The channel transactors of %s, as virtual interfaces." % xtor_name(b, role),
           "class %s %s;" % (name, b.header)]
    out += _typedefs(b)
    out += ["    virtual fw_rv_%s_xtor_if #(%s) %s;" % (_kind(b, role, c), c.payload_name, c.name)
            for c in b.channels]
    args = ", ".join("virtual fw_rv_%s_xtor_if #(%s) %s_" % (_kind(b, role, c), c.payload_name,
                                                             c.name) for c in b.channels)
    out.append("    function new(%s);" % args)
    out += ["        %s = %s_;" % (c.name, c.name) for c in b.channels]
    out.append("    endfunction")
    # Run-time knobs by path, "<ch>.<knob>": the monitor has a queue depth only;
    # initiators and targets also have max_gap (their stall setting).
    knobs = ["depth"] if role == MON else ["depth", "max_gap"]
    out += ["",
            "    // Sets one channel's knob by path, \"<ch>.%s\". 0 if there is no such knob."
            % "|".join(knobs),
            "    function bit set_knob(string path, int unsigned v);",
            "        case (path)"]
    for c in b.channels:
        out += ['            "%s.%s": %s.%s = v;' % (c.name, k, c.name, k) for k in knobs]
    out += ["            default: return 0;",
            "        endcase",
            "        return 1;",
            "    endfunction",
            "endclass"]
    return "\n".join(out) + "\n"


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


def render_xtor_core(b: Bundle, role: str) -> str:
    """The synthesizable part of a role's transactor: one fw-hdl rv core per channel,
    the payloads (flat, in their structs' layout) spliced onto the pins. No classes:
    it reads only the bundle's class-free package and its woven part."""
    name = xtor_name(b, role) + "_core"
    _, _, rst_hi = _clock_reset(b)
    clk = b.clock
    dp = b.defs_pkg
    out = ["// %s: the synthesizable core. One fw-hdl rv" % _what(b, role),
           "// core per channel, the payloads (flat, packed as their structs) spliced onto",
           "// the pins (names as in the field table and on the protocol checker). The",
           "// <ch>_up_* links go to the class side (%s adds the rv interfaces)." % xtor_name(b, role),
           "module %s\n    import %s::*, %s_woven::*;\n%s (" % (name, dp, dp, b.header)]
    out += _ports(b, role, True)
    out.append(");")
    for c in b.channels:
        kind = _kind(b, role, c)
        up = c.name.upper()
        out += ["",
                "    // %s: %s" % (c.name, {"initiator": "sent", "target": "received",
                                            "monitor": "observed"}[kind]),
                "    localparam int unsigned %s_BITS = %s(%s);" % (up, bits_fn(b, c), b.struct_param)]
        lsb = []
        for i, m in enumerate(c.members):
            later = [_width(x.type) for x in c.members[i + 1:]]
            lsb.append(" + ".join(later) if later else "0")
        for m, l in zip(c.members, lsb):
            out.append("    localparam int unsigned %s_%s_LSB = %s;" % (up, m.name.upper(), l))
        out.append("    logic [%s_BITS-1:0] %s_d;" % (up, c.name))
        conns = [".clock(%s)" % clk, ".reset(%s)" % rst_hi,
                 ".up_data(%s_up_data)" % c.name, ".up_valid(%s_up_valid)" % c.name]
        if kind == "monitor":
            conns += [".up_first(%s_up_first)" % c.name, ".up_xfer(%s_up_xfer)" % c.name]
        conns += [".up_ready(%s_up_ready)" % c.name, ".data(%s_d)" % c.name,
                  ".valid(%svalid)" % c.name, ".ready(%sready)" % c.name]
        out.append("    fw_rv_%s_xtor_core #(.W(%s_BITS)) u_%s (%s);"
                   % (kind, up, c.name, ", ".join(conns)))
        for m in c.members:
            pin = "%s%s" % (c.name, m.name)
            fld = "%s_d[%s_%s_LSB +: %s]" % (c.name, up, m.name.upper(), _width(m.type))
            opt = m.attrs.get("fw_opt")
            if kind == "initiator":
                rhs = fld if opt is None else "(%s) ? %s : '0" % (_opt_cond(b, opt), fld)
                out.append("    assign %s = %s;" % (pin, rhs))
            else:
                rhs = pin if opt is None else "(%s) ? %s : '0" % (_opt_cond(b, opt), pin)
                out.append("    assign %s = %s;" % (fld, rhs))
    out.append("endmodule : %s" % name)
    return "\n".join(out) + "\n"


def _imports(b: Bundle, pkg: str) -> str:
    return "import %s::*, %s_woven::*, %s::*, %s_woven::*;" % (b.defs_pkg, b.defs_pkg, pkg, pkg)


def render_xtor_if(b: Bundle, role: str, pkg: str) -> str:
    name = xtor_name(b, role) + "_if"
    out = ["// The class side of %s (u_if): %s sets chans at time 0," % (xtor_name(b, role),
                                                                     xtor_name(b, role)),
           "// then raises bound; %s_bridge waits for bound." % xtor_name(b, role),
           "interface %s\n    %s\n%s;" % (name, _imports(b, pkg), b.header),
           "    %s_chans %s chans;" % (xtor_name(b, role), b.params_ref),
           "    bit bound;",
           "endinterface : %s" % name]
    return "\n".join(out) + "\n"


def render_xtor_module(b: Bundle, role: str, pkg: str) -> str:
    """The role's transactor for simulation: the core (``<name>_core``) plus one
    fw-hdl rv interface per channel, the class side's handles."""
    name = xtor_name(b, role)
    _, _, rst_hi = _clock_reset(b)
    clk = b.clock
    out = ["// %s. %s_core on the pins, one fw-hdl" % (_what(b, role), name),
           "// rv interface per channel on its links (names as in the field table and on",
           "// the protocol checker, so `.*` connects). The class side is u_if",
           "// (%s_if), driven by %s_bridge." % (name, name),
           "module %s\n    %s\n%s (" % (name, _imports(b, pkg), b.header)]
    out += _ports(b, role, False)
    out.append(");")
    out += _typedefs(b)
    out.append("    %s_if %s u_if ();" % (name, b.params_ref))
    links = []
    for c in b.channels:
        kind = _kind(b, role, c)
        sigs = ["up_valid", "up_ready"] + (["up_first", "up_xfer"] if kind == "monitor" else [])
        out += ["",
                "    %s %s_up_data;" % (c.payload_name, c.name),
                "    bit %s;" % ", ".join("%s_%s" % (c.name, x) for x in sigs)]
        conns = [".clock(%s)" % clk, ".reset(%s)" % rst_hi] + [
            ".%s(%s_%s)" % (x, c.name, x) for x in ["up_data"] + sigs]
        out.append("    fw_rv_%s_xtor_if #(.T(%s)) u_%s_if (%s);"
                   % (kind, c.payload_name, c.name, ", ".join(conns)))
        links += [".%s_%s(%s_%s)" % (c.name, x, c.name, x) for x in ["up_data"] + sigs]
    out += ["",
            "    %s_core %s u_core (.*, %s);" % (name, b.params_ref, ", ".join(links)),
            "",
            "    initial begin",
            "        u_if.chans = new(%s);" % ", ".join("u_%s_if" % c.name for c in b.channels),
            "        u_if.bound = 1;",
            "    end",
            "endmodule : %s" % name]
    return "\n".join(out) + "\n"


def render_role_bridge(b: Bundle, role: str) -> str:
    name = xtor_name(b, role) + "_bridge"
    req, rsp = api_names(b)
    sends = [c for c in b.channels if _sends(b, role, c)]
    recvs = [c for c in b.channels if not _sends(b, role, c)]
    out_api, in_api = (req, rsp) if role == b.roles[0] else (rsp, req)
    in_var = "m_" + in_api[len(b.proto) + 1:-3]                     # m_rsp / m_req
    vif = "virtual %s_if %s" % (xtor_name(b, role), b.params_ref)
    out = ["// The pins of %s as the %s's channel API: %s goes out through"
           % (xtor_name(b, role), role, out_api),
           "// the rv initiators; run() passes each beat the pins receive to %s (%s)."
           % (in_var, in_api),
           "class %s %s implements %s;" % (name, b.header, b.spec(out_api))]
    for c in sends:
        out.append("    typedef %s::%s %s;" % (b.spec(out_api), c.payload_name, c.payload_name))
    for c in recvs:
        out.append("    typedef %s::%s %s;" % (b.spec(in_api), c.payload_name, c.payload_name))
    out += ["    %s vif;" % vif,
            "    %s %s;" % (b.spec(in_api), in_var),
            "",
            "    function new(%s vif_, %s %s = null);" % (vif, b.spec(in_api), in_var[2:]),
            "        this.vif = vif_;",
            "        %s = %s;" % (in_var, in_var[2:]),
            "    endfunction"]
    for c in sends:
        out += ["",
                "    virtual task %s(input %s t);" % (c.name, c.payload_name),
                "        wait (vif.bound);",
                "        vif.chans.%s.send(t);" % c.name,
                "    endtask"]
    out += ["",
            "    // One loop per received channel, so a stalled channel holds up no other.",
            "    virtual task run();",
            "        wait (vif.bound);",
            "        fork"]
    for c in recvs:
        out.append("            forever begin %s t; vif.chans.%s.recv(t); %s.%s(t); end"
                   % (c.payload_name, c.name, in_var, c.name))
    out += ["        join", "    endtask", "endclass"]
    return "\n".join(out) + "\n"


def render_mon_bridge(b: Bundle) -> str:
    name = xtor_name(b, MON) + "_bridge"
    req, rsp = api_names(b)
    vif = "virtual %s_if %s" % (xtor_name(b, MON), b.params_ref)
    out = ["// What %s sees, as listener calls: <ch>_pre on the first valid"
           % xtor_name(b, MON),
           "// cycle of a beat, <ch>_post on its handshake. Add listeners to req and rsp.",
           "class %s %s;" % (name, b.header)]
    for c in b.channels:
        api = req if c.fwd else rsp
        out.append("    typedef %s::%s %s;" % (b.spec(api), c.payload_name, c.payload_name))
    out += ["    %s vif;" % vif,
            "    %s req = new();" % b.spec(req + "_listener_fanout"),
            "    %s rsp = new();" % b.spec(rsp + "_listener_fanout"),
            "",
            "    function new(%s vif_);" % vif,
            "        this.vif = vif_;",
            "    endfunction",
            "",
            "    virtual task run();",
            "        wait (vif.bound);",
            "        fork"]
    for c in b.channels:
        fan = "req" if c.fwd else "rsp"
        out += ["            forever begin",
                "                %s t;" % c.payload_name,
                "                bit first, xfer;",
                "                vif.chans.%s.get_ev(t, first, xfer);" % c.name,
                "                if (first) %s.%s_pre(t);" % (fan, c.name),
                "                if (xfer) %s.%s_post(t);" % (fan, c.name),
                "            end"]
    out += ["        join", "    endtask", "endclass"]
    return "\n".join(out) + "\n"


def render_files(b: Bundle, pkg: str) -> List[Tuple[str, str]]:
    """[(file name, text)]: per role (and mon), the core, the interface and the
    module, one declaration per file, named after it."""
    out = []
    for role in list(b.roles) + [MON]:
        name = xtor_name(b, role)
        out.append((name + "_core.sv", render_xtor_core(b, role)))
        out.append((name + "_if.sv", render_xtor_if(b, role, pkg)))
        out.append((name + ".sv", render_xtor_module(b, role, pkg)))
    return out


def render_bridges(b: Bundle) -> List[str]:
    """Package items: per role (and mon), the chans class; then the bridges."""
    roles = list(b.roles) + [MON]
    return ([render_chans(b, r) for r in roles]
            + [render_role_bridge(b, r) for r in b.roles] + [render_mon_bridge(b)])
