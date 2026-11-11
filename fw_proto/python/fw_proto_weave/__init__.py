"""fw_proto weavers for sv-weave: derive listeners, base classes, proxies, imps
and channel APIs from a protocol's core specification."""
from .binding import FwProtoBinding
from .weaver import FwProtoWeaver

__all__ = ["FwProtoBinding", "FwProtoWeaver"]
