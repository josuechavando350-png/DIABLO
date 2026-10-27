"""Capa 4 · Copiloto de criterio (copilot/) — solo interfaz.

Expone la interfaz para que un LLM proponga hipótesis de invariantes. NO
conecta ninguna API (la key y el transporte son PENDIENTE DE INPUT DEL
USUARIO). `StubCopilot` permite usar el pipeline offline, sin LLM.
"""

from .interface import (
    ContractContext,
    CopilotNotConfigured,
    InvariantCopilot,
    InvariantHypothesis,
    LLMCopilot,
    StubCopilot,
    SYSTEM_PROMPT,
)

__all__ = [
    "ContractContext",
    "CopilotNotConfigured",
    "InvariantCopilot",
    "InvariantHypothesis",
    "LLMCopilot",
    "StubCopilot",
    "SYSTEM_PROMPT",
]
