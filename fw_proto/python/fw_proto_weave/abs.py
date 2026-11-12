"""Abstractor glue of a bundle (design §4.5, docs/p6-abstractors.md): what lets a
class description put RTL behind the bundle's APIs. Emitted with the transactors
(the ``xtor`` option), whose modules and bridges it names.

    <proto>_<role>_socket #(P)  the role's API endpoint on a component: for the
                                first role an fw_socket (calls the fwd API,
                                provides the rev one), for the second its
                                fw_mirror
    <proto>_<role>_abs #(P)     description object (an fw_boundary): an abstractor
                                whose pins play <role>, inserted between a
                                component's endpoint of the other role and its RTL's
                                struct port. Its string tables name the transactor
                                (<proto>_<role>_xtor), its class side and the handle
    <proto>_<role>_abs_h #(P)   run-time handle (an fw_component): the transactor
                                bridge, with a proxy in each direction (where
                                listeners attach), joined to the endpoint; knobs set
                                by its path (fw_proto_cfg) go to the channel
                                transactors
    <proto>_observers #(P)      listeners registered by path for the handles, joined
                                to a handle's proxies when both are registered (how
                                rules and monitors attach to an inserted
                                abstractor, by path)
    <proto>_<role>_sp::connect(<proto>_<role>_socket)
                                (ports.py) inserts <endpoint>_abs under the port
                                owner's parent and links it to the port

The abstractor's role is the opposite of the RTL port's: an RTL subordinate port
is driven by a manager abstractor, which serves the wrapper's subordinate socket.
"""
from typing import List

from .bundle import Bundle
from .sv import args_unused
from .xtors import _clock_reset, api_names, xtor_name


def socket_name(b: Bundle, role: str) -> str:
    return "%s_%s_socket" % (b.proto, role)


def abs_name(b: Bundle, role: str) -> str:
    return "%s_%s_abs" % (b.proto, role)


def handle_name(b: Bundle, role: str) -> str:
    return abs_name(b, role) + "_h"


def _other(b: Bundle, role: str) -> str:
    return b.roles[1] if role == b.roles[0] else b.roles[0]


def _apis(b: Bundle, role: str):
    """(the API ``role`` sends, the API it receives)."""
    req, rsp = api_names(b)
    return (req, rsp) if role == b.roles[0] else (rsp, req)


def observers_name(b: Bundle) -> str:
    return "%s_observers" % b.proto


def _api_var(b: Bundle, api: str) -> str:
    """The handle's proxy member for an API: axi4_req_if -> req."""
    return api[len(b.proto) + 1:-3]


def check(b: Bundle, err) -> bool:
    if len(b.roles) != 2 or not b.struct_param:
        err("%s: abstractors need two roles and one struct parameter" % b.decl_name)
        return False
    return True


def render_socket(b: Bundle, role: str) -> str:
    req, rsp = api_names(b)
    first = role == b.roles[0]
    base = "fw_socket" if first else "fw_mirror"
    provides = rsp if first else req
    calls = req if first else rsp
    name = socket_name(b, role)
    return "\n".join([
        "// The %s's API endpoint on a component: calls %s, provides %s. Its peer"
        % (role, calls, provides),
        "// is the %s's (connect()); connect_up() exposes it one level out."
        % _other(b, role),
        "class %s %s extends %s #(%s, %s);"
        % (name, b.header, base, b.spec(req), b.spec(rsp)),
        "    function new(string name, fw_component parent, %s imp = null);"
        % b.spec(provides),
        "        super.new(name, parent, imp);",
        "    endfunction",
        "endclass"])


def render_abs(b: Bundle, role: str) -> str:
    """The description object whose pins play ``role``."""
    name = abs_name(b, role)
    other = _other(b, role)
    sends, _ = _apis(b, role)
    sp = "%s_%s_sp" % (b.proto, role)
    clk, rst, _ = _clock_reset(b)
    clk_rst = (".%s(clock), .%s(!reset)" % (clk, rst) if b.reset_n
               else ".%s(clock), .%s(reset)" % (clk, rst))
    chans = [c for c in b.channels if c.fwd == (role == b.roles[0])]
    out = ["// Description of an abstractor whose pins play %s (%s): it stands"
           % (role, xtor_name(b, role)),
           "// behind a %s endpoint and drives an RTL %s port. Inserted by"
           % (other, other),
           "// %s_%s_sp::connect(). Nothing runs through it: in the description its"
           % (b.proto, other),
           "// %s methods never return; at run time %s replaces it."
           % (sends, handle_name(b, role)),
           "class %s %s extends fw_boundary implements %s;"
           % (name, b.header, b.spec(sends))]
    for c in chans:
        out.append("    typedef %s::%s %s;" % (b.spec(sends), c.payload_name, c.payload_name))
    out += ["    %s sp;" % b.spec(sp),
            "    /* verilator lint_off UNDRIVEN */      // never triggered, by design",
            "    event m_never;",
            "    /* verilator lint_on UNDRIVEN */",
            "",
            "    function new(string name, fw_component parent);",
            "        super.new(name, parent);",
            '        sp = new("sp", this);',
            "    endfunction",
            "",
            "    // Stand behind the parent's endpoint.",
            "    function void serve(%s ep);" % b.spec(socket_name(b, other)),
            "        ep.set_imp(this);",
            "        m_serves = ep.get_name();",
            "    endfunction"]
    for c in chans:
        out += ["",
                "    virtual task %s(input %s t);" % (c.name, c.payload_name),
                "        @m_never;",
                "    endtask"]
    out += ["",
            "    virtual function fw_sp_base pin_sp(); return sp; endfunction",
            '    virtual function string xtor_module(); return "%s"; endfunction'
            % xtor_name(b, role),
            "    virtual function string vif_type();",
            '        return {"virtual %s_if #(", sp.param_lit(), ")"};' % xtor_name(b, role),
            "    endfunction",
            "    virtual function string handle_type();",
            '        return {"%s #(", sp.param_lit(), ")"};' % handle_name(b, role),
            "    endfunction",
            '    virtual function string xtor_clk_rst(); return "%s"; endfunction' % clk_rst,
            "endclass"]
    return args_unused("\n".join(out))


def render_observers(b: Bundle) -> str:
    """The registry that joins listeners registered by path to the handles."""
    name = observers_name(b)
    req, rsp = api_names(b)
    rq, rs = _api_var(b, req), _api_var(b, rsp)
    lreq, lrsp = b.spec(req + "_listener"), b.spec(rsp + "_listener")
    preq, prsp = b.spec(req + "_proxy"), b.spec(rsp + "_proxy")
    return "\n".join([
        "// Listeners attached by path to the abstractor handles of this P. A test",
        "// registers listeners for a path (add; either may be null); each handle",
        "// registers its proxies under its path when it is built (attach). Whichever",
        "// comes second joins them, so the order does not matter as long as both come",
        "// before the traffic. unused() names the listener paths no handle took (a",
        "// misspelled path, another P).",
        "class %s %s;" % (name, b.header),
        "    static string m_path[$];",
        "    static %s m_%s[$];" % (lreq, rq),
        "    static %s m_%s[$];" % (lrsp, rs),
        "    static bit m_used[$];",
        "    static string m_h_path[$];",
        "    static %s m_h_%s[$];" % (preq, rq),
        "    static %s m_h_%s[$];" % (prsp, rs),
        "",
        "    static function void pair(int unsigned i, %s %s, %s %s);" % (preq, rq, prsp, rs),
        "        if (m_%s[i] != null) %s.add_listener(m_%s[i]);" % (rq, rq, rq),
        "        if (m_%s[i] != null) %s.add_listener(m_%s[i]);" % (rs, rs, rs),
        "        m_used[i] = 1;",
        "    endfunction",
        "",
        "    static function void add(string path, %s %s, %s %s);" % (lreq, rq, lrsp, rs),
        "        m_path.push_back(path);",
        "        m_%s.push_back(%s);" % (rq, rq),
        "        m_%s.push_back(%s);" % (rs, rs),
        "        m_used.push_back(0);",
        "        foreach (m_h_path[h]) if (m_h_path[h] == path)",
        "            pair(m_path.size() - 1, m_h_%s[h], m_h_%s[h]);" % (rq, rs),
        "    endfunction",
        "",
        "    static function void attach(string path, %s %s, %s %s);" % (preq, rq, prsp, rs),
        "        m_h_path.push_back(path);",
        "        m_h_%s.push_back(%s);" % (rq, rq),
        "        m_h_%s.push_back(%s);" % (rs, rs),
        "        foreach (m_path[i]) if (m_path[i] == path) pair(i, %s, %s);" % (rq, rs),
        "    endfunction",
        "",
        "    // The listener paths no handle has taken, comma-separated; \"\" if none.",
        "    static function string unused();",
        "        string s;",
        "        foreach (m_path[i]) if (!m_used[i]) s = {s, (s == \"\") ? \"\" : \", \", m_path[i]};",
        "        return s;",
        "    endfunction",
        "endclass"])


def render_handle(b: Bundle, role: str) -> str:
    """The run-time handle of ``render_abs``."""
    name = handle_name(b, role)
    other = _other(b, role)
    sends, recvs = _apis(b, role)
    s_var, r_var = sends[len(b.proto) + 1:-3], recvs[len(b.proto) + 1:-3]   # req / rsp
    bridge = xtor_name(b, role) + "_bridge"
    vif = "virtual %s_if %s" % (xtor_name(b, role), b.params_ref)
    return "\n".join([
        "// Run time: the abstractor %s, as a component. Calls made on the"
        % abs_name(b, role),
        "// endpoint go through %s to the pins (%s); what the pins receive goes"
        % (s_var, bridge),
        "// through %s to the endpoint's peer. Listeners attach to %s and %s."
        % (r_var, s_var, r_var),
        "// Knobs set for its path in fw_proto_cfg (\"<ch>.depth\", \"<ch>.max_gap\")",
        "// reach the channel transactors when it starts. Listeners registered for its",
        "// path (%s) are added to its proxies." % observers_name(b),
        "class %s %s extends fw_component implements fw_runnable;" % (name, b.header),
        "    %s bridge;" % b.spec(bridge),
        "    %s %s;" % (b.spec(sends + "_proxy"), s_var),
        "    %s %s;" % (b.spec(recvs + "_proxy"), r_var),
        "    %s m_ep;" % b.spec(socket_name(b, other)),
        "",
        "    function new(string name, fw_component parent, %s vif);" % vif,
        "        super.new(name, parent);",
        "        %s = new();" % r_var,
        "        bridge = new(vif, %s);" % r_var,
        "        %s = new(bridge);" % s_var,
        "        %s::attach(fw_rel_path(this), %s, %s);" % (b.spec(observers_name(b)),
                                                      _api_var(b, api_names(b)[0]),
                                                      _api_var(b, api_names(b)[1])),
        "        parent.add_runnable(this);",
        "    endfunction",
        "",
        "    function void serve(%s ep);" % b.spec(socket_name(b, other)),
        "        m_ep = ep;",
        "        ep.set_imp(%s);" % s_var,
        "    endfunction",
        "",
        "    virtual task run();",
        "        string path = fw_rel_path(this);",
        "        string names[$];",
        "        %s.m_target = m_ep.t;" % r_var,
        "        wait (bridge.vif.bound);",
        "        fw_proto_cfg::names(path, names);",
        "        foreach (names[i])",
        "            if (!bridge.vif.chans.set_knob(names[i], fw_proto_cfg::get_int(path, names[i], 0)))",
        '                $error("%s: no knob \'%s\'", path, names[i]);',
        "        bridge.run();",
        "    endtask",
        "endclass"])


def connect_method(b: Bundle, role: str) -> List[str]:
    """Lines of <proto>_<role>_sp::connect(): the port is RTL's, the endpoint a
    component's of the same role; the abstractor plays the other role."""
    a = abs_name(b, _other(b, role))
    return ["    // Across levels: the parent's API endpoint `api` reaches this port",
            "    // through an abstractor, <api>_abs, inserted under the parent.",
            "    // Like-to-like connections use link() and need none.",
            "    function %s connect(%s api);" % (b.spec(a), b.spec(socket_name(b, role))),
            "        %s a;" % b.spec(a),
            "        if (m_owner == null || m_owner.get_parent() == null)",
            '            $fatal(1, "%s.connect: the port has no owner with a parent", m_name);',
            '        a = new({api.get_name(), "_abs"}, m_owner.get_parent());',
            "        a.serve(api);",
            "        a.sp.link(this);",
            "        return a;",
            "    endfunction"]


def render(b: Bundle) -> List[str]:
    """Package items, after the bridges: sockets, abstractors, handles."""
    return ([render_socket(b, r) for r in b.roles]
            + [render_observers(b)]
            + [render_abs(b, r) for r in b.roles]
            + [render_handle(b, r) for r in b.roles])
