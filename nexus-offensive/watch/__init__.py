"""Capa 1 · Observador (watch/).

Vigila una cadena (vía un RPC) buscando despliegues/upgrades de contratos
in-scope y, por cada uno, pasa por la jaula (`ScopeGuard.assert_allowed`) antes
de disparar el motor de invariantes.

El RPC real queda PENDIENTE DE INPUT DEL USUARIO; las pruebas usan
`MockChainSource` o un `transport` inyectado (100% local, sin red).
"""

from .events import ChainEvent
from .observer import Observer
from .sources import ChainSource, JsonRpcChainSource, MockChainSource, PENDING_RPC_URL, RpcError

__all__ = [
    "ChainEvent",
    "Observer",
    "ChainSource",
    "MockChainSource",
    "JsonRpcChainSource",
    "PENDING_RPC_URL",
    "RpcError",
]
