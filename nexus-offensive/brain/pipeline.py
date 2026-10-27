"""Capa integradora · brain — encadena observador → motor → fork-validador → reporte.

Flujo: el Observador (Capa 1) detecta un contrato in-scope (pasando por la
jaula), el motor/fork-validador confirma si una invariante se rompe (ejecutando
el PoC en el EVM), y si se rompe se genera un Finding y un borrador de reporte
(Capa 5). Todo queda en la bitácora inmutable (Capa 0).
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core import AuditLog, ScopeGuard, Target  # noqa: E402
from core.models import Finding, Severity  # noqa: E402
from report import ReportDraft, render_markdown  # noqa: E402
from watch import ChainEvent, MockChainSource, Observer  # noqa: E402
from watch.sources import ChainSource  # noqa: E402


@dataclass
class ValidationResult:
    breaks: bool
    invariant: str
    detail: dict = field(default_factory=dict)
    poc_ref: str = ""


class FunctionValidator:
    """Validador determinista a partir de un callable (para tests/demos)."""

    def __init__(self, fn: Callable[[Target, ChainEvent], ValidationResult]) -> None:
        self._fn = fn

    def validate(self, target: Target, event: ChainEvent) -> ValidationResult:
        return self._fn(target, event)


def _find_bin(name: str) -> str:
    return shutil.which(name) or str(Path.home() / ".foundry" / "bin" / name)


def _find_solc() -> str | None:
    env = os.environ.get("NEXUS_SOLC")
    if env and Path(env).exists():
        return env
    solc_dir = Path.home() / ".foundry" / "solc"
    cands = sorted(solc_dir.glob("solc-*")) if solc_dir.exists() else []
    return str(cands[-1]) if cands else None


class ForgeValidator:
    """Validador REAL: ejecuta un PoC de Foundry en el EVM. Que el test PoC pase
    significa que la invariante se rompió (el exploit se reprodujo)."""

    def __init__(
        self,
        project_dir: str | Path,
        match_test: str,
        invariant: str,
        *,
        solc: str | None = None,
        poc_ref: str = "",
    ) -> None:
        self.project_dir = Path(project_dir)
        self.match_test = match_test
        self.invariant = invariant
        self.solc = solc or _find_solc()
        self.poc_ref = poc_ref or match_test

    def validate(self, target: Target, event: ChainEvent) -> ValidationResult:
        forge = _find_bin("forge")
        cmd = [forge, "test", "--match-test", self.match_test]
        if self.solc:
            cmd += ["--use", self.solc]
        proc = subprocess.run(cmd, cwd=self.project_dir, capture_output=True, text=True)
        passed = bool(re.search(r"\[PASS\]\s+" + re.escape(self.match_test), proc.stdout))
        return ValidationResult(
            breaks=passed,
            invariant=self.invariant,
            detail={"match_test": self.match_test, "exit": proc.returncode},
            poc_ref=self.poc_ref,
        )


class Pipeline:
    """Encadena observador → validación → reporte, con jaula y bitácora."""

    def __init__(
        self,
        scope_guard: ScopeGuard,
        source: ChainSource,
        validator,
        *,
        audit_log: AuditLog | None = None,
        report_dir: str | Path | None = None,
        severity: Severity = Severity.HIGH,
    ) -> None:
        self.validator = validator
        self.audit = audit_log
        self.report_dir = Path(report_dir) if report_dir else None
        if self.report_dir:
            self.report_dir.mkdir(parents=True, exist_ok=True)
        self.severity = severity
        self.findings: list[Finding] = []
        self.reports: list[tuple[Finding, str, Path | None]] = []
        self.observer = Observer(scope_guard, source, self._handle, audit_log=audit_log)

    def _handle(self, event: ChainEvent):
        target = Target(value=event.address, kind="contract", chain=event.chain)
        result = self.validator.validate(target, event)
        if self.audit is not None:
            self.audit.append(
                "brain.validate",
                {"address": event.address, "invariant": result.invariant, "breaks": result.breaks},
            )
        if not result.breaks:
            return result

        fid = f"NX-{len(self.findings) + 1:03d}"
        finding = Finding(
            id=fid,
            title=f"Invariante violada en {event.address}",
            severity=self.severity,
            target=target,
            description=f"El fork-validador reprodujo la ruptura de la invariante: {result.invariant}",
            invariant=result.invariant,
            poc_ref=result.poc_ref,
        )
        draft = ReportDraft(
            finding=finding,
            summary=f"Se detectó y validó en un fork que el contrato {event.address} "
            f"viola la invariante «{result.invariant}».",
            impact="Un atacante puede explotar la condición para drenar o bloquear fondos del protocolo.",
            reproduction_steps=[
                "El observador detectó el contrato in-scope (jaula: ALLOW).",
                "El fork-validador ejecutó el PoC en el EVM y reprodujo la ruptura.",
                f"Ver PoC: `{result.poc_ref}`.",
            ],
            recommendation="Corregir la lógica para preservar la invariante y re-validar en fork.",
        )
        md = render_markdown(draft)
        path = None
        if self.report_dir:
            path = self.report_dir / f"{fid}.md"
            path.write_text(md, encoding="utf-8")
        self.findings.append(finding)
        self.reports.append((finding, md, path))
        return result

    def run_once(self):
        self.observer.run_once()
        return self.reports
