"""The API model the fw_proto generators work from.

An ``Api`` is an interface class to derive from: either a hand-written
``(* fw_api *)`` class (read through sv-weave's ``SvDecl``, as written) or one
synthesized from a ``(* fw_proto_bundle *)`` class (``bundle.py``). Generators
only see ``Api`` objects, so both kinds get identical derivatives.
"""
import dataclasses as dc
from typing import Dict, List, Optional

from sv_weave.api import SvDecl, SvDeclArg, SvDeclMethod

ATTR_API = "fw_api"
ATTR_LISTENER = "fw_listener"
ATTR_DEFAULT = "fw_default"
ATTR_BUNDLE = "fw_proto_bundle"


@dc.dataclass
class Api:
    name: str                          # interface class name
    header: str                        # "#(axi4_param_t P = ...)" or ""
    param_names: List[str]
    typedefs: List[str]                # names of the class-scope typedefs
    methods: List[SvDeclMethod]
    attrs: Dict
    kind: str = "api"                  # "api" | "listener"
    decl_text: Optional[str] = None    # SV of the interface class when synthesized

    @property
    def params_ref(self) -> str:
        return "#(%s)" % ", ".join(self.param_names) if self.param_names else ""

    @property
    def spec(self) -> str:
        """The interface class as named from a derived class: ``x_if #(P)``."""
        return ("%s %s" % (self.name, self.params_ref)).strip()

    def header_plus(self, extra: str) -> str:
        """The parameter header with one more parameter appended."""
        if not self.header:
            return "#(%s)" % extra
        return self.header[:-1].rstrip() + ", %s)" % extra

    def typedef_block(self, indent: str = "    ") -> List[str]:
        """Re-declares the API's typedefs in a class that implements it:
        interface-class typedefs are not inherited by implementing classes."""
        return ["%stypedef %s::%s %s;" % (indent, self.spec, t, t) for t in self.typedefs]

    def default_of(self, m: SvDeclMethod) -> str:
        """``empty`` or ``error``: what an unimplemented method does in ``<if>_base``."""
        d = m.attrs.get(ATTR_DEFAULT) or self.attrs.get(ATTR_DEFAULT)
        if d:
            return str(d)
        return "empty" if self.kind == "listener" else "error"


def api_from_decl(decl: SvDecl) -> Api:
    kind = "listener" if decl.attrs.get(ATTR_LISTENER) else "api"
    return Api(decl.name, decl.header, list(decl.param_names),
               [t.name for t in decl.typedefs], list(decl.methods), dict(decl.attrs), kind)


def method(name: str, kind: str, args: List[SvDeclArg], ret: Optional[str] = None,
           attrs: Optional[Dict] = None) -> SvDeclMethod:
    """A synthesized method (for derived interface classes)."""
    return SvDeclMethod(name, kind, ret, args, ["pure", "virtual"], dict(attrs or {}), "")


def class_decls(model):
    """(package, SvDecl) for every class declared in a package, generic or not,
    in declaration order: by file (in the order files first appear, as a
    package that `includes its classes has them in several), then by line."""
    out = []
    for p in model.packages():
        seen = [g for g in p.generics if g.decl is not None]
        seen += [c for c in p.classes if not c.is_specialization and c.decl is not None]
        files: List[str] = []
        for x in seen:
            f = x.loc.file if x.loc else ""
            if f not in files:
                files.append(f)

        def key(x):
            return (files.index(x.loc.file if x.loc else ""), x.loc.line if x.loc else 0)
        out.extend((p.name, x.decl) for x in sorted(seen, key=key))
    return out
