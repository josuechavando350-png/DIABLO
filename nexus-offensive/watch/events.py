"""Eventos de cadena que observa la Capa 1."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class ChainEvent:
    """Un evento on-chain relevante: despliegue, upgrade o transacción."""

    kind: str  # "deploy" | "upgrade" | "tx"
    address: str  # contrato involucrado
    block: int
    chain: str | None = None
    data: dict = field(default_factory=dict)
