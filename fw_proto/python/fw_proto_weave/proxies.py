"""``<api>_proxy`` (forward to a target, calling listeners around each call) and
``<api>_listener_fanout`` (one listener feeding several) (design §4.2)."""
from .listeners import listener_name
from .model import Api
from .sv import RET, end_of, proto


def proxy_name(api: Api) -> str:
    return api.name + "_proxy"


def fanout_name(api: Api) -> str:
    return api.name + "_listener_fanout"


def _listener_spec(api: Api) -> str:
    return ("%s %s" % (listener_name(api), api.params_ref)).strip()


def _list_mgmt(api: Api):
    ls = _listener_spec(api)
    return [
        "    %s m_listeners[$];" % ls,
        "    function void add_listener(%s l);" % ls,
        "        m_listeners.push_back(l);",
        "    endfunction",
        "    function void remove_listener(%s l);" % ls,
        "        foreach (m_listeners[i]) if (m_listeners[i] == l) begin",
        "            m_listeners.delete(i);",
        "            return;",
        "        end",
        "    endfunction",
    ]


def render_proxy(api: Api) -> str:
    out = ["// Implements %s by forwarding to m_target; listeners see each call." % api.name,
           ("class %s %s implements %s;" % (proxy_name(api), api.header, api.spec))
           .replace("  ", " ")]
    out += api.typedef_block()
    out.append("    %s m_target;" % api.spec)
    out += _list_mgmt(api)
    out += ["    function new(%s target = null);" % api.spec,
            "        m_target = target;",
            "    endfunction"]
    for m in api.methods:
        ins = ", ".join(a.name for a in m.inputs)
        post = [a.name for a in m.args]
        ret = not m.is_task and not m.is_void
        out.append("    virtual %s;" % proto(m))
        if ret:
            out.append("        %s %s;" % (m.ret, RET))
            post.append(RET)
        out.append("        foreach (m_listeners[i]) m_listeners[i].%s_pre(%s);" % (m.name, ins))
        call = "m_target.%s(%s);" % (m.name, ", ".join(a.name for a in m.args))
        out.append("        %s%s" % ("%s = " % RET if ret else "", call))
        out.append("        foreach (m_listeners[i]) m_listeners[i].%s_post(%s);"
                   % (m.name, ", ".join(post)))
        if ret:
            out.append("        return %s;" % RET)
        out.append("    " + end_of(m))
    out.append("endclass")
    return "\n".join(out)


def render_fanout(api: Api, lst: Api) -> str:
    out = ["// A listener of %s that forwards every call to m_listeners." % api.name,
           ("class %s %s implements %s;" % (fanout_name(api), api.header, _listener_spec(api)))
           .replace("  ", " ")]
    out += api.typedef_block()
    out += _list_mgmt(api)
    for m in lst.methods:
        out.append("    virtual %s;" % proto(m))
        out.append("        foreach (m_listeners[i]) m_listeners[i].%s(%s);"
                   % (m.name, ", ".join(a.name for a in m.args)))
        out.append("    endfunction")
    out.append("endclass")
    return "\n".join(out)
