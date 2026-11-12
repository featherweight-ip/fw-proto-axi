"""Small SV text helpers shared by the generators."""
import re
from typing import List

from sv_weave.api import SvDeclArg, SvDeclMethod

_SIMPLE_TYPE = re.compile(r"^[A-Za-z_][\w$]*(::[A-Za-z_][\w$]*)*$")


def zero_of(type_text: str, dims: str = "") -> str:
    """A zero value for a variable of this type: a cast for a named type (so enums
    are assigned legally), '0 for an integral type spelled with ranges, {} for a
    queue or dynamic array."""
    if dims:
        if dims.replace(" ", "") in ("[$]", "[]"):
            return "{}"
        return "'{default: '0}"
    if _SIMPLE_TYPE.match(type_text):
        return "%s'(0)" % type_text
    return "'0"


def as_inputs(args: List[SvDeclArg]) -> List[SvDeclArg]:
    """The same arguments, all ``input`` and without defaults (listener signatures)."""
    return [SvDeclArg(a.name, "input", a.type, a.dims, None) for a in args]


def call_args(m: SvDeclMethod) -> str:
    return ", ".join(a.name for a in m.args)


def proto(m: SvDeclMethod, name: str = None, args: List[SvDeclArg] = None) -> str:
    n = name or m.name
    a = ", ".join(x.declare() for x in (m.args if args is None else args))
    if m.is_task:
        return "task %s(%s)" % (n, a)
    return "function %s %s(%s)" % (m.ret or "void", n, a)


def end_of(m: SvDeclMethod) -> str:
    return "endtask" if m.is_task else "endfunction"


RET = "__ret"


def args_unused(text: str) -> str:
    """Wraps a class whose methods do not read their arguments (pure virtual
    methods, default bodies), so a -Wall lint does not report each argument."""
    return ("/* verilator lint_off UNUSEDSIGNAL */\n" + text.rstrip("\n")
            + "\n/* verilator lint_on UNUSEDSIGNAL */")

