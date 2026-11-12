"""``<api>_listener``: ``<m>_pre(inputs)`` / ``<m>_post(inputs, outputs[, ret])``
for every method of an API, all void functions (design §4.1)."""
from typing import List

from sv_weave.api import SvDeclArg

from .model import ATTR_LISTENER, Api, method
from .sv import RET, args_unused, as_inputs


def listener_name(api: Api) -> str:
    return api.name + "_listener"


def post_args(m) -> List[SvDeclArg]:
    args = as_inputs(m.args)
    if not m.is_task and not m.is_void:
        args.append(SvDeclArg(RET, "input", m.ret))
    return args


def listener_of(api: Api) -> Api:
    """The listener interface as an Api (so bases and fan-outs derive from it)."""
    methods = []
    for m in api.methods:
        methods.append(method(m.name + "_pre", "function", as_inputs(m.inputs), "void"))
        methods.append(method(m.name + "_post", "function", post_args(m), "void"))
    lst = Api(listener_name(api), api.header, list(api.param_names), [], methods,
              {ATTR_LISTENER: True}, kind="listener")
    lst.source = api
    return lst


def render_listener(lst: Api) -> str:
    api = lst.source
    out = ["// Listener of %s: <m>_pre when a call is made, <m>_post when it completes."
           % api.name,
           "(* %s *)" % ATTR_LISTENER,
           ("interface class %s %s;" % (lst.name, lst.header)).replace("  ", " ")]
    out += api.typedef_block()
    for m in lst.methods:
        out.append("    pure virtual %s;" % _proto(m))
    out.append("endclass")
    return args_unused("\n".join(out))


def _proto(m) -> str:
    from .sv import proto
    return proto(m)
