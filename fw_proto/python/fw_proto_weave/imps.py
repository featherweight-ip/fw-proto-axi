"""``<api>_imp #(<params>, type IMP)``: implements an API by forwarding every
method to an ``IMP`` object that has the same methods. Replaces the ``_IMP``
macros for components with one export per API type (design §4.4, step 1)."""
from .model import Api
from .sv import RET, end_of, proto


def imp_name(api: Api) -> str:
    return api.name + "_imp"


def render_imp(api: Api) -> str:
    out = ["// Implements %s by forwarding to m_imp (any class with the same methods)."
           % api.name,
           "class %s %s implements %s;" % (imp_name(api), api.header_plus("type IMP = int"),
                                           api.spec)]
    out += api.typedef_block()
    out += ["    IMP m_imp;",
            "    function new(IMP imp);",
            "        m_imp = imp;",
            "    endfunction"]
    for m in api.methods:
        call = "m_imp.%s(%s);" % (m.name, ", ".join(a.name for a in m.args))
        out.append("    virtual %s;" % proto(m))
        out.append("        %s%s" % ("" if m.is_task or m.is_void else "return ", call))
        out.append("    " + end_of(m))
    out.append("endclass")
    return "\n".join(out)
