"""Fuentes de eventos de cadena para el observador.

- `MockChainSource`: fuente sintética para pruebas (100% local, sin red).
- `JsonRpcChainSource`: fuente real contra un RPC JSON-RPC. El `transport`
  (la capa que abre el socket) es inyectable, así que la lógica de parseo se
  prueba sin red. El RPC real y su autorización quedan PENDIENTE DE INPUT.
"""

from __future__ import annotations

import json
from abc import ABC, abstractmethod
from typing import Callable

from .events import ChainEvent


class ChainSource(ABC):
    @abstractmethod
    def poll(self) -> list[ChainEvent]:
        """Devuelve los eventos nuevos desde la última llamada."""
        raise NotImplementedError


class MockChainSource(ChainSource):
    """Fuente de eventos pre-cargada, para tests y demos locales."""

    def __init__(self, events: list[ChainEvent], batch_size: int | None = None) -> None:
        self._events = list(events)
        self._batch = batch_size
        self._cursor = 0

    def poll(self) -> list[ChainEvent]:
        if self._cursor >= len(self._events):
            return []
        if self._batch is None:
            out = self._events[self._cursor:]
            self._cursor = len(self._events)
        else:
            out = self._events[self._cursor:self._cursor + self._batch]
            self._cursor += len(out)
        return out


class RpcError(RuntimeError):
    pass


# PENDIENTE DE INPUT DEL USUARIO: un RPC de archivo real + su autorización.
PENDING_RPC_URL = "PENDIENTE_DE_INPUT_DEL_USUARIO"


def _urllib_transport(url: str, payload: dict) -> dict:  # pragma: no cover - necesita red real
    """Transporte HTTP real (urllib). Solo se usa con un RPC real (PENDIENTE)."""
    import urllib.request

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


class JsonRpcChainSource(ChainSource):
    """Observa un RPC real buscando despliegues de contratos.

    `transport(url, payload) -> dict` abre el socket; por defecto urllib. Para
    las pruebas se inyecta un transporte falso (sin red). Un RPC real debe ser
    provisto por el usuario y estar autorizado — **PENDIENTE DE INPUT**.
    """

    def __init__(
        self,
        rpc_url: str = PENDING_RPC_URL,
        *,
        chain: str | None = None,
        transport: Callable[[str, dict], dict] | None = None,
        start_block: int | None = None,
    ) -> None:
        self.rpc_url = rpc_url
        self.chain = chain
        self._transport = transport or _urllib_transport
        self._next_block = start_block

    def _rpc(self, method: str, params: list):
        if self.rpc_url == PENDING_RPC_URL and self._transport is _urllib_transport:
            raise RpcError(
                "RPC no configurado (PENDIENTE DE INPUT DEL USUARIO). "
                "Provee un rpc_url real autorizado o inyecta un transport de prueba."
            )
        resp = self._transport(self.rpc_url, {"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
        if resp.get("error"):
            raise RpcError(str(resp["error"]))
        return resp["result"]

    def poll(self) -> list[ChainEvent]:
        latest = int(self._rpc("eth_blockNumber", []), 16)
        if self._next_block is None:
            self._next_block = latest
        events: list[ChainEvent] = []
        while self._next_block <= latest:
            block = self._rpc("eth_getBlockByNumber", [hex(self._next_block), True])
            for tx in block.get("transactions", []):
                if tx.get("to") in (None, "", "0x"):  # creación de contrato
                    receipt = self._rpc("eth_getTransactionReceipt", [tx["hash"]])
                    addr = receipt.get("contractAddress") if receipt else None
                    if addr:
                        events.append(
                            ChainEvent("deploy", addr, self._next_block, self.chain, {"tx": tx["hash"]})
                        )
            self._next_block += 1
        return events
