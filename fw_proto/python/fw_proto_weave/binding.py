"""A binding with no root classes: fw_proto weavers only add package-level code
(``on_design``), so no class is a woven target. sv-weave requires a binding."""
from sv_weave.plugin import Binding


class FwProtoBinding(Binding):
    name = "fw-proto"
    version = "0.1"
    roots = ()
