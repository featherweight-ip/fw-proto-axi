"""The ``fw-proto`` weaver: derives, into ``<pkg>_woven``, for every API
(``(* fw_api *)`` interface classes, and the channel APIs of every
``(* fw_proto_bundle *)`` class):

    <api>_listener, <api>_listener_base, <api>_listener_fanout,
    <api>_base, <api>_proxy, <api>_imp

and for every bundle, after its channel APIs:

    <api>_inbox (per channel API), <proto>_sp, <proto>_<role>_sp, <proto>_payloads

and, into ``<fw_defs_pkg>_woven`` when the bundle names its class-free package
(``fw_defs_pkg``), the payload widths ``<proto>_<payload>_bits(P)``.

Options:
    include: [names]   also treat these interface classes as APIs (no attribute needed)
    derive:  [kinds]   subset of listener, base, proxy, imp, bundle (default: all)
    xtor:    bool      also the pin-level transactors of every bundle (xtors.py): the
                       <proto>_<role>_xtor_core (synthesizable) and <proto>_<role>_xtor
                       modules and interfaces, as files, and their bridges, in
                       <pkg>_woven. Needs fw-hdl's rv kit and fw_defs_pkg (default: off).
                       With it, the abstractor glue too (abs.py): <proto>_<role>_socket,
                       _abs, _abs_h, and connect() on the role ports
"""
from sv_weave.plugin import Weaver

from .bases import render_base
from . import abs as abs_
from . import xtors
from .bundle import bundle_of, channel_apis
from .endpoints import render_inbox, render_payloads
from .imps import render_imp
from .listeners import listener_of, render_listener
from .model import ATTR_API, ATTR_BUNDLE, api_from_decl, class_decls
from .ports import render_role_sps, render_sp
from .proxies import render_fanout, render_proxy

KINDS = ("listener", "base", "proxy", "imp", "bundle")
RUNTIME_PKG = "fw_proto_pkg"


def derive(api, kinds=KINDS):
    """SV items, in declaration order, for one API."""
    items = []
    if api.decl_text:
        items.append(api.decl_text)
    if "listener" in kinds or "proxy" in kinds:
        lst = listener_of(api)
        items.append(render_listener(lst))
        if "base" in kinds:
            items.append(render_base(lst))
        items.append(render_fanout(api, lst))
    if "base" in kinds:
        items.append(render_base(api))
    if "proxy" in kinds:
        items.append(render_proxy(api))
    if "imp" in kinds:
        items.append(render_imp(api))
    return items


def derive_bundle(bundle, apis, kinds=KINDS, xtor=False):
    """SV items for one bundle's own derivatives (after its channel APIs')."""
    if "bundle" not in kinds:
        return []
    items = []
    if "base" in kinds:
        items += [render_inbox(a, bundle.channels) for a in apis]
    items.append(render_sp(bundle))
    items += render_role_sps(bundle, xtor)
    items.append(render_payloads(bundle))
    return items


def apis_of(model, include=(), err=None, kinds=KINDS, xtor=False):
    """[(package, Api or None, [SV items])] in declaration order. An Api's items are
    its derivatives; a bundle adds a last entry (Api None) for its own."""
    err = err or (lambda m: None)
    decls = class_decls(model)
    by_name = {d.name: d for _, d in decls}
    out = []
    for pkg, decl in decls:
        if decl.attrs.get(ATTR_BUNDLE):
            apis = channel_apis(decl, err)
            out.extend((pkg, a, derive(a, kinds)) for a in apis)
            out.append((pkg, None, derive_bundle(bundle_of(decl, err, by_name), apis, kinds,
                                                        xtor)))
        elif decl.is_interface and (decl.attrs.get(ATTR_API) or decl.name in include):
            a = api_from_decl(decl)
            out.append((pkg, a, derive(a, kinds)))
    return out


def bundles_of(model, err=None):
    """[(package, Bundle)] in declaration order."""
    err = err or (lambda m: None)
    decls = class_decls(model)
    by_name = {d.name: d for _, d in decls}
    return [(pkg, bundle_of(decl, err, by_name)) for pkg, decl in decls
            if decl.attrs.get(ATTR_BUNDLE)]


class FwProtoWeaver(Weaver):
    name = "fw-proto"
    version = "0.1"

    def subscribe(self, bus):
        bus.on_design(self.on_design)

    def on_design(self, d):
        include = list(d.options.get("include", []))
        kinds = tuple(d.options.get("derive", KINDS))
        xtor = bool(d.options.get("xtor", False))
        for pkg, api, items in apis_of(d.model, include, d.error, kinds, xtor):
            # A bundle's own derivatives build on the fw_proto runtime.
            imports = [RUNTIME_PKG] if api is None else []
            for text in items:
                d.add_item(pkg, text, imports=imports)
        bundles = bundles_of(d.model, d.error)
        # The class-free layer: payload widths, in the bundle's fw_defs_pkg.
        for pkg, b in bundles:
            if b.defs_pkg and xtors.check_defs(b, d.error):
                d.add_item(b.defs_pkg, xtors.render_bits_fns(b))
        if xtor:
            for pkg, b in bundles:
                if not xtors.check(b, d.error) or not abs_.check(b, d.error):
                    continue
                for text in xtors.render_bridges(d, b):
                    d.add_item(pkg, text)
                for text in abs_.render(b):
                    d.add_item(pkg, text, imports=["fw_hdl_pkg", RUNTIME_PKG])
                for name, text in xtors.render_files(d, b, pkg):
                    d.add_file(name, text)
