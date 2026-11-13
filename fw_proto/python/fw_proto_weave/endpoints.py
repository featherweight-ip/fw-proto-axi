"""Endpoint and payload helpers derived from a bundle (design §2 table):

    <api>_inbox #(P)       for each channel API: extends <api>_base, queues every
                           beat in a per-channel fw_inbox (<ch>_in), with clear()
                           and idle() over all of them. A scripted endpoint of the
                           receiving role is one of these.
    <proto>_payloads #(P)  static <name>_sprint(v), <name>_compare(a, b, diff) and
                           <name>_mask(v) per payload struct; absent fields (fw_opt)
                           are skipped, and zeroed by _mask (what the pins carry).

The SV text is in ``templates/endpoints/``; here are the views the templates read.
"""
from typing import List

from .bundle import Bundle, Channel
from .model import Api
from .ports import MemberView


class _Method:
    def __init__(self, m):
        self.name, self.type = m.name, m.args[0].type


class InboxView:
    """What endpoints/inbox.sv.j2 reads. clear() and idle() cover the methods
    that are channels."""

    def __init__(self, api: Api, chans: List[Channel]):
        names = {c.name for c in chans}
        self.api, self.name = api.name, api.name + "_inbox"
        self.header, self.params_ref = api.header, api.params_ref
        self.methods = [_Method(m) for m in api.methods]
        ins = ["%s_in" % m.name for m in api.methods if m.name in names]
        self.clears = ["%s.clear();" % i for i in ins]
        self.idles = ["%s.size() == 0" % i for i in ins]


class _Payload:
    """One payload struct: ``n`` its short name (axi4_aw_t -> axi4_aw), ``t`` its type."""

    def __init__(self, b: Bundle, c: Channel):
        n = c.payload_name
        self.n, self.t = (n[:-2] if n.endswith("_t") else n), c.payload
        self.members = [MemberView(b, m) for m in c.members]
        self.opts = [m for m in self.members if m.cond]


class PayloadsView:
    """What endpoints/payloads.sv.j2 reads: each payload struct once."""

    def __init__(self, b: Bundle):
        self.proto, self.decl_name, self.header = b.proto, b.decl_name, b.header
        seen = set()
        self.payloads = []
        for c in b.channels:
            if c.members and c.payload not in seen:
                seen.add(c.payload)
                self.payloads.append(_Payload(b, c))


def render_inbox(d, api: Api, chans: List[Channel]) -> str:
    return d.render("endpoints/inbox.sv.j2", v=InboxView(api, chans))


def render_payloads(d, b: Bundle) -> str:
    return d.render("endpoints/payloads.sv.j2", v=PayloadsView(b))
