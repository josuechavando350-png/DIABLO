"""Capa 4 · Copiloto de criterio — SOLO interfaz.

Estructura para que un LLM proponga HIPÓTESIS de invariantes sobre un contrato.
El copiloto nunca dispara nada solo: solo sugiere; el humano decide. Aquí NO se
conecta ninguna API — la API key y el transporte de red quedan PENDIENTE DE
INPUT DEL USUARIO. La lógica de armado del prompt y de parseo SÍ está
implementada y probada (con un transporte inyectado).
"""

from __future__ import annotations

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Callable


@dataclass
class ContractContext:
    """Lo que se le da al copiloto para razonar sobre un contrato."""

    name: str
    family_hint: str | None = None  # p.ej. "AMM", "Vault", "FlashLoan", "Oracle"
    functions: list[str] = field(default_factory=list)
    source_excerpt: str | None = None
    notes: str | None = None


@dataclass
class InvariantHypothesis:
    """Una invariante propuesta por el copiloto (a validar por el humano)."""

    family: str
    invariant: str  # la propiedad en lenguaje claro
    rationale: str  # por qué debería cumplirse
    confidence: float = 0.5  # 0..1


class CopilotNotConfigured(RuntimeError):
    """Se intentó usar el LLM sin API key / transporte (PENDIENTE DE INPUT)."""


class InvariantCopilot(ABC):
    @abstractmethod
    def propose_invariants(self, context: ContractContext) -> list[InvariantHypothesis]:
        raise NotImplementedError


class StubCopilot(InvariantCopilot):
    """Copiloto OFFLINE determinista (sin LLM): sugiere invariantes canónicas
    de la familia indicada, reusando el catálogo de la Capa 2. Útil para probar
    el pipeline sin ninguna API."""

    _CATALOG = {
        "AMM": [
            ("El producto constante k=r0*r1 nunca decrece por un swap.", "Con fee, cada swap debe aumentar k."),
            ("Las reservas están respaldadas por los balances reales.", "Evita fugas de contabilidad."),
        ],
        "Lending": [
            ("Ninguna posición presta por encima de su colateral.", "Salud por posición: deuda <= colateral*LTV."),
            ("Solvencia global: colateral total >= deuda total.", "El sistema puede cubrir la deuda."),
        ],
        "Vault": [
            ("La suma de lo redimible nunca excede los activos.", "El redondeo favorece al vault."),
            ("Contabilidad estricta: activos == shares (si es 1:1).", "Una donación no debe romper la contabilidad."),
        ],
        "FlashLoan": [
            ("Tras un flash loan el balance no disminuye.", "Todo préstamo debe repagarse."),
            ("El pool no otorga allowance ni hace llamadas arbitrarias.", "Evita approve abuse / llamada arbitraria."),
        ],
        "Oracle": [
            ("El colateral se valúa con un precio resistente a manipulación.", "TWAP/snapshot, no spot de AMM."),
        ],
    }

    def propose_invariants(self, context: ContractContext) -> list[InvariantHypothesis]:
        fam = context.family_hint or ""
        entries = self._CATALOG.get(fam, [])
        return [
            InvariantHypothesis(family=fam or "desconocida", invariant=inv, rationale=why, confidence=0.6)
            for inv, why in entries
        ]


# Prompt del sistema que se usaría con el LLM (documentado, no se envía aquí).
SYSTEM_PROMPT = (
    "Eres un asistente de seguridad DeFi. Dado el contexto de un contrato, "
    "propón entre 1 y 5 INVARIANTES: propiedades que SIEMPRE deberían cumplirse. "
    "Responde SOLO con una lista JSON de objetos "
    '{"family": str, "invariant": str, "rationale": str, "confidence": number}. '
    "No ejecutes nada; solo sugieres. El humano valida con el fork-validador."
)


class LLMCopilot(InvariantCopilot):
    """Copiloto respaldado por un LLM. NO conecta ninguna API por sí mismo.

    `send_fn(prompt, api_key, model) -> str` es el transporte que abriría el
    socket a la API; se inyecta. Sin `api_key` ni `send_fn`, `propose_invariants`
    lanza `CopilotNotConfigured` (PENDIENTE DE INPUT DEL USUARIO).

    Cómo se conectaría (PENDIENTE DE INPUT):
      - Proveer la API key (Anthropic/OpenAI/etc.) por variable de entorno.
      - Inyectar un `send_fn` que llame al endpoint de mensajes del proveedor
        con SYSTEM_PROMPT + build_prompt(context) y devuelva el texto de la
        respuesta. Nada de esto se hace aquí para no usar credenciales reales.
    """

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "claude-opus-4-8",
        send_fn: Callable[[str, str, str], str] | None = None,
    ) -> None:
        self.api_key = api_key
        self.model = model
        self._send = send_fn

    def build_prompt(self, context: ContractContext) -> str:
        parts = [f"Contrato: {context.name}"]
        if context.family_hint:
            parts.append(f"Familia (pista): {context.family_hint}")
        if context.functions:
            parts.append("Funciones: " + ", ".join(context.functions))
        if context.source_excerpt:
            parts.append("Fragmento de código:\n" + context.source_excerpt)
        if context.notes:
            parts.append("Notas: " + context.notes)
        return "\n".join(parts)

    def _parse(self, raw: str) -> list[InvariantHypothesis]:
        data = json.loads(raw)
        out = []
        for item in data:
            out.append(
                InvariantHypothesis(
                    family=item.get("family", ""),
                    invariant=item["invariant"],
                    rationale=item.get("rationale", ""),
                    confidence=float(item.get("confidence", 0.5)),
                )
            )
        return out

    def propose_invariants(self, context: ContractContext) -> list[InvariantHypothesis]:
        if not self.api_key or self._send is None:
            raise CopilotNotConfigured(
                "LLMCopilot sin configurar (PENDIENTE DE INPUT DEL USUARIO): "
                "falta la API key y/o el transporte `send_fn`. Ver docstring."
            )
        raw = self._send(SYSTEM_PROMPT + "\n\n" + self.build_prompt(context), self.api_key, self.model)
        return self._parse(raw)
