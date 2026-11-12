"""Derivatives of a ``(* fw_proto_bundle = "<proto>", fw_roles = "a,b" *)`` class.

Here: the bundle model and the channel APIs (design §4.3). ``<proto>_req_if``
has one task per ``(* fw_fwd *)`` channel and ``<proto>_rsp_if`` one per
``(* fw_rev *)`` channel; each takes the channel's payload and returns when the
beat is accepted. Both are APIs, so they get the same base, listener, proxy and
imp derivatives as a hand-written one. The struct ports are in ``ports.py``, the
endpoints and payload helpers in ``endpoints.py``.
"""
import dataclasses as dc
import re
from typing import Dict, List, Optional

from sv_weave.api import SvDecl, SvDeclArg, SvDeclMember

from .model import ATTR_API, ATTR_BUNDLE, Api, method
from .sv import args_unused

ATTR_FWD, ATTR_REV, ATTR_ROLES = "fw_fwd", "fw_rev", "fw_roles"
ATTR_CLOCK, ATTR_RESET, ATTR_RESET_N = "fw_clock", "fw_reset", "fw_reset_n"
ATTR_DEFS_PKG = "fw_defs_pkg"
_CH = re.compile(r"^(?P<family>[A-Za-z_]\w*)\s*#\s*\((?P<payload>.*)\)$")


@dc.dataclass
class Channel:
    name: str
    family: str                        # e.g. fw_rv_ch
    payload: str                       # payload type, resolved past bundle typedefs
    payload_name: str                  # its last component, e.g. aw_t
    fwd: bool
    members: List[SvDeclMember] = dc.field(default_factory=list)   # of a packed struct payload

    @property
    def payload_type(self) -> str:
        return self.payload


@dc.dataclass
class Bundle:
    decl_name: str
    proto: str                         # e.g. axi4
    roles: List[str]                   # e.g. [mgr, sub]; roles[0] sends the fwd channels
    header: str
    param_names: List[str]
    channels: List[Channel]
    clock: str = "clock"               # fw_clock
    reset: str = "reset"               # fw_reset (active high)
    reset_n: str = ""                  # fw_reset_n (active low); wins over reset
    defs_pkg: str = ""                 # fw_defs_pkg: the class-free package of its parameters

    @property
    def struct_param(self) -> Optional[str]:
        """The parameter fw_opt names members of (the only one, if there is one)."""
        return self.param_names[0] if len(self.param_names) == 1 else None

    @property
    def params_ref(self) -> str:
        return "#(%s)" % ", ".join(self.param_names) if self.param_names else ""

    def spec(self, name: str) -> str:
        return ("%s %s" % (name, self.params_ref)).strip()


def _resolve(decl: SvDecl, type_text: str) -> str:
    """``t::aw_t`` where ``t`` is a bundle typedef -> ``<t's type>::aw_t``."""
    head, sep, rest = type_text.partition("::")
    td = decl.typedef(head.strip()) if sep else None
    return "%s::%s" % (td.type, rest) if td is not None else type_text


def _members(payload: str, decls: Dict[str, SvDecl]) -> List[SvDeclMember]:
    """Members of ``<class> #(...)::<typedef>`` when it is a struct declared in a
    class this run has read."""
    cls, sep, tn = payload.rpartition("::")
    if not sep:
        return []
    d = decls.get(cls.split("#")[0].strip())
    td = d.typedef(tn.strip()) if d is not None else None
    return list(td.members) if td is not None and td.struct_kind else []


def channels(decl: SvDecl, err, decls: Optional[Dict[str, SvDecl]] = None) -> List[Channel]:
    out = []
    for p in decl.properties:
        fwd, rev = bool(p.attrs.get(ATTR_FWD)), bool(p.attrs.get(ATTR_REV))
        if not (fwd or rev):
            continue
        if fwd == rev:
            err("%s.%s: exactly one of fw_fwd / fw_rev" % (decl.name, p.name))
            continue
        m = _CH.match(p.type)
        if m is None:
            err("%s.%s: a channel is <family> #(<payload>), not '%s'" % (decl.name, p.name, p.type))
            continue
        payload = _resolve(decl, m.group("payload").strip())
        out.append(Channel(p.name, m.group("family"), payload,
                           payload.split("::")[-1].strip(), fwd, _members(payload, decls or {})))
    return out


def proto_of(decl: SvDecl) -> str:
    proto = decl.attrs.get(ATTR_BUNDLE)
    if not isinstance(proto, str):
        proto = decl.name[:-len("_bundle")] if decl.name.endswith("_bundle") else decl.name
    return proto


def roles_of(decl: SvDecl) -> List[str]:
    return [r.strip() for r in str(decl.attrs.get(ATTR_ROLES, "init,targ")).split(",")]


def bundle_of(decl: SvDecl, err, decls: Dict[str, SvDecl]) -> Bundle:
    a = decl.attrs
    b = Bundle(decl.name, proto_of(decl), roles_of(decl), decl.header,
               list(decl.param_names), channels(decl, err, decls),
               clock=str(a.get(ATTR_CLOCK, "clock")), reset=str(a.get(ATTR_RESET, "reset")),
               reset_n=str(a.get(ATTR_RESET_N, "")), defs_pkg=str(a.get(ATTR_DEFS_PKG, "")))
    for c in b.channels:
        if not c.members:
            err("%s.%s: payload %s is not a packed struct this run has read; no field table"
                % (decl.name, c.name, c.payload))
    return b


def channel_apis(decl: SvDecl, err) -> List[Api]:
    proto = proto_of(decl)
    roles = roles_of(decl)
    chs = channels(decl, err)
    apis = []
    for suffix, fwd, sender in (("req", True, roles[0]), ("rsp", False, roles[-1])):
        sel = [c for c in chs if c.fwd == fwd]
        if not sel:
            continue
        tnames = []
        for c in sel:
            if c.payload_name not in tnames:
                tnames.append(c.payload_name)
        methods = [method(c.name, "task", [SvDeclArg("t", "input", c.payload_name)])
                   for c in sel]
        api = Api("%s_%s_if" % (proto, suffix), decl.header, list(decl.param_names), tnames,
                  methods, {ATTR_API: True})
        lines = ["// %s channels of %s, called by the %s: one task per channel, returning"
                 % ("Forward" if fwd else "Reverse", decl.name, sender.strip()),
                 "// when the beat is accepted.",
                 "(* %s *)" % ATTR_API,
                 ("interface class %s %s;" % (api.name, api.header)).replace("  ", " ")]
        seen = set()
        for c in sel:
            if c.payload_name not in seen:
                seen.add(c.payload_name)
                lines.append("    typedef %s %s;" % (c.payload, c.payload_name))
        for m in methods:
            lines.append("    pure virtual task %s(input %s t);" % (m.name, m.args[0].type))
        lines.append("endclass")
        api.decl_text = args_unused("\n".join(lines))
        apis.append(api)
    return apis
