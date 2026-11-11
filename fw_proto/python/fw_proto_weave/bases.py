"""``<if>_base``: a virtual class implementing an interface class with default
bodies, so a client overrides only what it needs (design §4, "Base class").

Listener methods default to empty; API methods report an error and zero their
outputs. ``(* fw_default = "empty" | "error" *)`` on the class or method overrides."""
from .model import Api
from .sv import RET, args_unused, end_of, proto, zero_of


def base_name(api: Api) -> str:
    return api.name + "_base"


def render_base(api: Api) -> str:
    tdefs = api.typedefs if api.kind == "api" else []
    src = getattr(api, "source", api)
    out = ["// %s with default bodies: override only the methods you need." % api.name,
           ("virtual class %s %s implements %s;" % (base_name(api), api.header, api.spec))
           .replace("  ", " ")]
    out += src.typedef_block() if api.kind == "listener" else api.typedef_block()
    for m in api.methods:
        out.append("    virtual %s;" % proto(m))
        if api.default_of(m) == "error":
            out.append('        $error("%s::%s: not implemented");' % (base_name(api), m.name))
        for a in m.outputs:
            out.append("        %s = %s;" % (a.name, zero_of(a.type, a.dims)))
        if not m.is_task and not m.is_void:
            out.append("        return %s;" % zero_of(m.ret))
        out.append("    " + end_of(m))
    out.append("endclass")
    return args_unused("\n".join(out))
