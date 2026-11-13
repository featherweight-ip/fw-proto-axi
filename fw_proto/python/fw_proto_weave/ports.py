"""Struct-port derivatives of a bundle (design §4.5, §4.3 "role link types"):

    <proto>_sp #(P)          the field table, built in the constructor: for each
                             channel its payload members (<ch><member>, absent
                             ones dropped by fw_opt) and the family's control
                             fields (fw_rv_ch: <ch>valid, <ch>ready)
    <proto>_<role>_sp #(P)   one per role, with the typed link() to the other
                             role and bind_inner() to the same role one level in;
                             with the xtor option also connect(<role>_socket),
                             which inserts the abstractor (abs.py)

The runtime they extend (fw_sp_base, fw_rv_ch::add_ctl) is fw_proto_pkg.

The SV text is in ``templates/ports/``; here are the names and the views the
templates read.
"""
from typing import List

from .bundle import Bundle


def sp_name(b: Bundle, role: str = None) -> str:
    return "%s_%s_sp" % (b.proto, role) if role else "%s_sp" % b.proto


def _opt_cond(b: Bundle, opt) -> str:
    """``P.HAS_QOS != 0`` for ``fw_opt = "HAS_QOS"``; an expression is used as is."""
    o = str(opt).strip().strip('"')
    if all(ch.isalnum() or ch == "_" for ch in o) and b.struct_param:
        return "%s.%s != 0" % (b.struct_param, o)
    return "(%s) != 0" % o


class MemberView:
    """One payload member: ``cond`` is its fw_opt condition (None if always
    present), ``guard`` the ``if (cond) `` that prefixes a statement on it."""

    def __init__(self, b: Bundle, m):
        self.name = m.name
        opt = m.attrs.get("fw_opt")
        self.cond = _opt_cond(b, opt) if opt else None
        self.guard = "if (%s) " % self.cond if opt else ""


class _SpChan:
    def __init__(self, b: Bundle, c):
        self.name, self.payload_type, self.family = c.name, c.payload_type, c.family
        self.dir = "FW_FWD" if c.fwd else "FW_REV"
        self.members = [MemberView(b, m) for m in c.members]


class SpView:
    """What ports/sp.sv.j2 reads."""

    def __init__(self, b: Bundle):
        self.name, self.decl_name, self.header = sp_name(b), b.decl_name, b.header
        self.proto, self.struct_param = b.proto, b.struct_param
        self.chans = [_SpChan(b, c) for c in b.channels]


class RoleSpView:
    """What ports/role_sp.sv.j2 reads for one role. connect() (``xtor``) is
    served by an abstractor of the other role."""

    def __init__(self, b: Bundle, i: int, xtor: bool):
        from . import abs as abs_
        self.role, self.other, self.index = b.roles[i], b.roles[1 - i], i
        self.name, self.decl_name, self.header = sp_name(b, self.role), b.decl_name, b.header
        self.spec, self.base_spec = b.spec(self.name), b.spec(sp_name(b))
        self.other_spec = b.spec(sp_name(b, self.other))
        self.xtor = xtor
        self.abs_spec = b.spec(abs_.abs_name(b, self.other))
        self.socket_spec = b.spec(abs_.socket_name(b, self.role))


def render_sp(d, b: Bundle) -> str:
    return d.render("ports/sp.sv.j2", v=SpView(b))


def render_role_sps(d, b: Bundle, xtor: bool = False) -> List[str]:
    """With ``xtor``, each role also gets connect(), which inserts an abs.py abstractor."""
    from . import abs as abs_
    items = []
    if len(b.roles) != 2:
        return items
    items.append("typedef class %s;" % sp_name(b, b.roles[1]))
    if xtor:
        items += ["typedef class %s;" % abs_.abs_name(b, r) for r in b.roles]
        items += ["typedef class %s;" % abs_.socket_name(b, r) for r in b.roles]
    items += [d.render("ports/role_sp.sv.j2", v=RoleSpView(b, i, xtor))
              for i in range(len(b.roles))]
    return items
