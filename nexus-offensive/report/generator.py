"""Generador de borradores de reporte en Markdown a partir de un Finding."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone

from core.models import Finding, Severity

# Justificación por defecto de cada severidad (escala tipo Immunefi).
_SEVERITY_RATIONALE = {
    Severity.CRITICAL: "Pérdida directa de fondos o congelamiento permanente de activos.",
    Severity.HIGH: "Pérdida de fondos bajo condiciones específicas o daño grave al protocolo.",
    Severity.MEDIUM: "Impacto acotado: afecta a un subconjunto de usuarios o requiere condiciones.",
    Severity.LOW: "Impacto menor o difícil de explotar en la práctica.",
    Severity.INFO: "Observación sin impacto directo en fondos.",
}


def severity_rationale(severity: Severity) -> str:
    return _SEVERITY_RATIONALE.get(severity, "")


@dataclass
class ReportDraft:
    """Todo lo necesario para redactar un reporte a partir de un Finding."""

    finding: Finding
    summary: str
    impact: str
    reproduction_steps: list[str] = field(default_factory=list)
    poc_code: str | None = None
    poc_language: str = "solidity"
    recommendation: str = ""
    program: str | None = None
    references: list[str] = field(default_factory=list)

    def to_markdown(self) -> str:
        return render_markdown(self)


def _bullets(items: list[str]) -> str:
    return "\n".join(f"- {it}" for it in items) if items else "_(sin datos)_"


def _numbered(items: list[str]) -> str:
    return "\n".join(f"{i}. {s}" for i, s in enumerate(items, 1)) if items else "_(sin pasos)_"


def render_markdown(draft: ReportDraft) -> str:
    """Renderiza el borrador de reporte en Markdown."""
    f = draft.finding
    sev = f.severity
    sev_label = sev.value.upper() if isinstance(sev, Severity) else str(sev)
    target = f.target
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    lines: list[str] = []
    lines.append(f"# {f.title}")
    lines.append("")
    lines.append(f"- **ID del hallazgo:** `{f.id}`")
    lines.append(f"- **Severidad:** {sev_label}")
    if draft.program:
        lines.append(f"- **Programa:** {draft.program}")
    lines.append(f"- **Target:** `{target.value}`" + (f" ({target.kind})" if target.kind else ""))
    if target.chain:
        lines.append(f"- **Cadena:** {target.chain}")
    lines.append(f"- **Fecha del borrador:** {now}")
    lines.append("")

    lines.append("## Resumen")
    lines.append(draft.summary or f.description or "_(pendiente)_")
    lines.append("")

    lines.append("## Severidad")
    lines.append(f"**{sev_label}** — {severity_rationale(sev) if isinstance(sev, Severity) else ''}")
    lines.append("")

    lines.append("## Impacto")
    lines.append(draft.impact or "_(pendiente)_")
    lines.append("")

    if f.invariant:
        lines.append("## Invariante violada")
        lines.append(f"La siguiente propiedad, que debería cumplirse siempre, se rompe:")
        lines.append("")
        lines.append(f"> {f.invariant}")
        lines.append("")

    lines.append("## Pasos para reproducir")
    lines.append(_numbered(draft.reproduction_steps))
    lines.append("")

    lines.append("## Prueba de concepto (PoC)")
    if draft.poc_code:
        lines.append(f"```{draft.poc_language}")
        lines.append(draft.poc_code.rstrip())
        lines.append("```")
    elif f.poc_ref:
        lines.append(f"PoC: `{f.poc_ref}`")
    else:
        lines.append("_(PoC pendiente)_")
    lines.append("")

    lines.append("## Recomendación")
    lines.append(draft.recommendation or "_(pendiente)_")
    lines.append("")

    if draft.references:
        lines.append("## Referencias")
        lines.append(_bullets(draft.references))
        lines.append("")

    lines.append("---")
    lines.append("_Borrador generado por NEXUS Offensive · Capa 5 (Reporte). "
                 "Revisar, validar y firmar antes de enviar._")
    return "\n".join(lines) + "\n"
