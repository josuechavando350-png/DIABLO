"""Capa 1 · Observador — vigila deploys/upgrades in-scope y dispara el motor.

Regla invariable: antes de actuar sobre (forkear/validar) una dirección real,
llama a `ScopeGuard.assert_allowed()`. El observador filtra TODO evento por la
jaula (default-deny): solo los in-scope llegan al handler, y siempre pasando
antes por `assert_allowed`. Cada observación queda en la bitácora inmutable.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Callable

# Permite importar la Capa 0 (la jaula) cuando se usa fuera de pytest.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core import AuditLog, ScopeGuard, Target  # noqa: E402

from .events import ChainEvent  # noqa: E402
from .sources import ChainSource  # noqa: E402


class Observer:
    """Conecta una fuente de cadena con el motor, pasando por la jaula."""

    def __init__(
        self,
        scope_guard: ScopeGuard,
        source: ChainSource,
        on_in_scope: Callable[[ChainEvent], object],
        *,
        audit_log: AuditLog | None = None,
    ) -> None:
        self.guard = scope_guard
        self.source = source
        self.on_in_scope = on_in_scope
        self.audit = audit_log
        self.seen_in_scope: list[ChainEvent] = []
        self.skipped_out_of_scope: list[ChainEvent] = []

    def _target(self, ev: ChainEvent) -> Target:
        return Target(value=ev.address, kind="contract", chain=ev.chain)

    def run_once(self) -> list[tuple[ChainEvent, object]]:
        """Procesa un lote de eventos. Devuelve (evento, resultado) de los in-scope."""
        results: list[tuple[ChainEvent, object]] = []
        for ev in self.source.poll():
            target = self._target(ev)
            verdict = self.guard.check(target)
            if self.audit is not None:
                self.audit.append(
                    "watch.observe",
                    {
                        "kind": ev.kind,
                        "address": ev.address,
                        "block": ev.block,
                        "decision": verdict.decision.value,
                    },
                )
            if not verdict.allowed:
                self.skipped_out_of_scope.append(ev)
                continue
            # LA JAULA: no se forkea/valida una dirección sin autorización.
            self.guard.assert_allowed(target)
            self.seen_in_scope.append(ev)
            results.append((ev, self.on_in_scope(ev)))
        return results
