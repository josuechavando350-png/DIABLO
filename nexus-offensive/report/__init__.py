"""Capa 5 · Reporte — generador de borradores de reporte de vulnerabilidad.

Toma un `Finding` (de la Capa 0) más el contexto del hallazgo (impacto, pasos
de reproducción, PoC, invariante violada) y produce un borrador de reporte en
Markdown listo para que el humano lo revise, firme y envíe.
"""

from .generator import ReportDraft, render_markdown, severity_rationale

__all__ = ["ReportDraft", "render_markdown", "severity_rationale"]
