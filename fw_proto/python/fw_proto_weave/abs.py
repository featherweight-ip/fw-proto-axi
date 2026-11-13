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

The SV text is in ``templates/abs/``; here are the names and the view objects the
templates read. connect() stays Python text until ports.py moves to templates.
"""
from typing import List

from .bundle import Bundle
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


class AbsView:
    """What the abs/ templates read for one role of a bundle."""

    def __init__(self, b: Bundle, role: str):
        req, rsp = api_names(b)
        first = role == b.roles[0]
        self.role, self.other = role, _other(b, role)
        self.header = b.header
        self.req_spec, self.rsp_spec = b.spec(req), b.spec(rsp)
        # socket: the first role's is an fw_socket (calls req, provides rsp), the
        # second's its fw_mirror
        self.socket = socket_name(b, role)
        self.socket_base = "fw_socket" if first else "fw_mirror"
        self.calls, self.provides = (req, rsp) if first else (rsp, req)
        self.provides_spec = b.spec(self.provides)
        # abs and its handle
        self.sends, recvs = _apis(b, role)
        self.sends_spec = b.spec(self.sends)
        self.abs, self.handle = abs_name(b, role), handle_name(b, role)
        self.xtor = xtor_name(b, role)
        self.other_sp = "%s_%s_sp" % (b.proto, self.other)
        self.sp_spec = b.spec("%s_%s_sp" % (b.proto, role))
        self.peer_socket_spec = b.spec(socket_name(b, self.other))
        self.send_chans = [c for c in b.channels if c.fwd == first]
        clk, rst, _ = _clock_reset(b)
        self.clk_rst = ".%s(clock), .%s(%sreset)" % (clk, rst, "!" if b.reset_n else "")
        self.s_var, self.r_var = _api_var(b, self.sends), _api_var(b, recvs)    # req / rsp
        self.bridge = xtor_name(b, role) + "_bridge"
        self.bridge_spec = b.spec(self.bridge)
        self.s_proxy_spec = b.spec(self.sends + "_proxy")
        self.r_proxy_spec = b.spec(recvs + "_proxy")
        self.vif = "virtual %s_if %s" % (self.xtor, b.params_ref)
        self.observers = observers_name(b)
        self.observers_spec = b.spec(self.observers)
        self.rq, self.rs = _api_var(b, req), _api_var(b, rsp)


class ObserversView:
    """What abs/observers.sv.j2 reads."""

    def __init__(self, b: Bundle):
        req, rsp = api_names(b)
        self.name, self.header = observers_name(b), b.header
        self.rq, self.rs = _api_var(b, req), _api_var(b, rsp)
        self.lreq, self.lrsp = b.spec(req + "_listener"), b.spec(rsp + "_listener")
        self.preq, self.prsp = b.spec(req + "_proxy"), b.spec(rsp + "_proxy")


def render_socket(d, b: Bundle, role: str) -> str:
    return d.render("abs/socket.sv.j2", v=AbsView(b, role))


def render_abs(d, b: Bundle, role: str) -> str:
    """The description object whose pins play ``role``."""
    return d.render("abs/abs.sv.j2", v=AbsView(b, role))


def render_observers(d, b: Bundle) -> str:
    """The registry that joins listeners registered by path to the handles."""
    return d.render("abs/observers.sv.j2", o=ObserversView(b))


def render_handle(d, b: Bundle, role: str) -> str:
    """The run-time handle of ``render_abs``."""
    return d.render("abs/handle.sv.j2", v=AbsView(b, role))


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


def render(d, b: Bundle) -> List[str]:
    """Package items, after the bridges: sockets, abstractors, handles."""
    return ([render_socket(d, b, r) for r in b.roles]
            + [render_observers(d, b)]
            + [render_abs(d, b, r) for r in b.roles]
            + [render_handle(d, b, r) for r in b.roles])
