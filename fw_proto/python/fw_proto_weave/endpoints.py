"""Endpoint and payload helpers derived from a bundle (design §2 table):

    <api>_inbox #(P)       for each channel API: extends <api>_base, queues every
                           beat in a per-channel fw_inbox (<ch>_in), with clear()
                           and idle() over all of them. A scripted endpoint of the
                           receiving role is one of these.
    <proto>_payloads #(P)  static <name>_sprint(v), <name>_compare(a, b, diff) and
                           <name>_mask(v) per payload struct; absent fields (fw_opt)
                           are skipped, and zeroed by _mask (what the pins carry).
"""
from typing import List

from .bundle import Bundle, Channel
from .model import Api
from .ports import _opt_cond


def render_inbox(api: Api, chans: List[Channel]) -> str:
    by_name = {c.name: c for c in chans}
    name = api.name + "_inbox"
    out = ["// Queues every %s beat in a per-channel inbox, for scripted endpoints and"
           % api.name,
           "// tests. Setting <ch>_in.stall holds that channel (READY low).",
           "class %s %s extends %s_base %s;" % (name, api.header, api.name, api.params_ref)]
    for m in api.methods:
        out.append("    fw_inbox #(%s) %s_in = new;" % (m.args[0].type, m.name))
    out.append("")
    for m in api.methods:
        out += ["    virtual task %s(input %s t);" % (m.name, m.args[0].type),
                "        %s_in.put(t);" % m.name,
                "    endtask"]
    ins = ["%s_in" % m.name for m in api.methods if m.name in by_name]
    out += ["",
            "    function void clear();",
            "        %s" % " ".join("%s.clear();" % i for i in ins),
            "    endfunction",
            "",
            "    function bit idle();",
            "        return %s;" % " && ".join("%s.size() == 0" % i for i in ins),
            "    endfunction",
            "endclass"]
    return "\n".join(out)


def _short(c: Channel) -> str:
    n = c.payload_name
    return n[:-2] if n.endswith("_t") else n


def render_payloads(b: Bundle) -> str:
    out = ["// sprint/compare/mask for the payloads of %s. Absent fields (fw_opt) are"
           % b.decl_name,
           "// skipped by sprint and compare, and zeroed by mask.",
           "class %s_payloads %s;" % (b.proto, b.header)]
    seen = set()
    for c in b.channels:
        if not c.members or c.payload in seen:
            continue
        seen.add(c.payload)
        n, t = _short(c), c.payload
        out += ["    static function string %s_sprint(%s v);" % (n, t),
                '        string s = "";']
        for m in c.members:
            line = 's = {s, $sformatf(" %s=0x%%0h", v.%s)};' % (m.name, m.name)
            opt = m.attrs.get("fw_opt")
            out.append("        %s%s" % ("if (%s) " % _opt_cond(b, opt) if opt else "", line))
        out += ["        return (s.len() > 0) ? s.substr(1, s.len() - 1) : s;",
                "    endfunction", ""]
        out += ["    // 1 when equal; otherwise 0, with the differing fields in diff.",
                "    static function bit %s_compare(%s a, %s b, output string diff);" % (n, t, t),
                '        diff = "";']
        for m in c.members:
            line = ('if (a.%s !== b.%s) diff = {diff, $sformatf(" %s: 0x%%0h != 0x%%0h", '
                    'a.%s, b.%s)};' % (m.name, m.name, m.name, m.name, m.name))
            opt = m.attrs.get("fw_opt")
            out.append("        %s%s" % ("if (%s) " % _opt_cond(b, opt) if opt else "", line))
        out += ['        return diff == "";', "    endfunction", ""]
        opts = [m for m in c.members if m.attrs.get("fw_opt")]
        out += ["    // v with its absent fields zeroed: what a link with pins delivers.",
                "    static function %s %s_mask(%s v);" % (t, n, t),
                "        %s m = v;" % t]
        for m in opts:
            out.append("        if (!(%s)) m.%s = '0;" % (_opt_cond(b, m.attrs["fw_opt"]), m.name))
        out += ["        return m;", "    endfunction", ""]
    if out[-1] == "":
        out.pop()
    out.append("endclass")
    return "\n".join(out)
