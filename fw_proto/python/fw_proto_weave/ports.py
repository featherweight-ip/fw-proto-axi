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


def render_sp(b: Bundle) -> str:
    name = sp_name(b)
    out = ["// The pin-level field table of %s: name, width and direction of every"
           % b.decl_name,
           "// field, with absent fields (fw_opt) dropped. Extended once per role.",
           "virtual class %s %s extends fw_sp_base;" % (name, b.header)]
    out += ["    function new(string name, int unsigned role, fw_realized owner = null);",
            "        super.new(name, role, owner);",
            "        build_fields();",
            "    endfunction",
            "",
            "    virtual function string proto();",
            '        return "%s";' % b.proto,
            "    endfunction",
            "",
            "    virtual function string param_lit();"]
    if b.struct_param:
        out.append('        return $sformatf("%%0d\'h%%0h", $bits(%s), %s);'
                   % (b.struct_param, b.struct_param))
    else:
        out.append('        return "";')
    out += ["    endfunction",
            "",
            "    protected function void build_fields();"]
    # One variable per payload, read only by $bits.
    out.append("        /* verilator lint_off UNUSEDSIGNAL */")
    for c in b.channels:
        out.append("        %s %s;" % (c.payload_type, c.name))
    out.append("        /* verilator lint_on UNUSEDSIGNAL */")
    for c in b.channels:
        d = "FW_FWD" if c.fwd else "FW_REV"
        for m in c.members:
            add = 'add_field("%s%s", $bits(%s.%s), %s);' % (c.name, m.name, c.name, m.name, d)
            opt = m.attrs.get("fw_opt")
            if opt:
                out.append("        if (%s) %s" % (_opt_cond(b, opt), add))
            else:
                out.append("        " + add)
        out.append('        %s #(%s)::add_ctl(this, "%s", %s);' % (c.family, c.payload_type,
                                                                     c.name, d))
    out += ["    endfunction", "endclass"]
    return "\n".join(out)


def render_role_sps(b: Bundle, xtor: bool = False) -> List[str]:
    """With ``xtor``, each role also gets connect(), from abs.py."""
    from . import abs as abs_
    items = []
    if len(b.roles) != 2:
        return items
    items.append("typedef class %s;" % sp_name(b, b.roles[1]))
    if xtor:
        items += ["typedef class %s;" % abs_.abs_name(b, r) for r in b.roles]
        items += ["typedef class %s;" % abs_.socket_name(b, r) for r in b.roles]
    for i, role in enumerate(b.roles):
        other = b.roles[1 - i]
        name = sp_name(b, role)
        out = ["// The %s side of %s. link() joins it to the %s side (one bundle of"
               % (role, b.decl_name, other),
               "// nets); bind_inner() makes a child's %s port this one, one level in." % role,
               "class %s %s extends %s;" % (name, b.header, b.spec(sp_name(b))),
               "    function new(string name, fw_realized owner = null);",
               "        super.new(name, %d, owner);" % i,
               "    endfunction",
               "",
               "    virtual function string role_name();",
               '        return "%s";' % role,
               "    endfunction",
               "",
               "    function void link(%s peer);" % b.spec(sp_name(b, other)),
               "        do_link(peer);",
               "    endfunction",
               "",
               "    function void bind_inner(%s child);" % b.spec(name),
               "        do_bind_inner(child);",
               "    endfunction"]
        if xtor:
            out += [""] + abs_.connect_method(b, role)
        out.append("endclass")
        items.append("\n".join(out))
    return items
