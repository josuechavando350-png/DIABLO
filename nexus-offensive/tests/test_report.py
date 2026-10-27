"""Tests de la Capa 5 (Reporte)."""

from core.models import Finding, Severity, Target
from report import ReportDraft, render_markdown, severity_rationale


def _finding() -> Finding:
    return Finding(
        id="NX-001",
        title="Reentrancy drena la bóveda",
        severity=Severity.CRITICAL,
        target=Target("0xabc", kind="contract", chain="ethereum"),
        invariant="address(vault).balance >= sum(balances)",
        poc_ref="twin/test/Exploit.t.sol",
    )


def test_render_has_all_sections():
    draft = ReportDraft(
        finding=_finding(),
        summary="La función withdraw envía ETH antes de poner el saldo a cero.",
        impact="Un atacante vacía la bóveda completa en una sola transacción.",
        reproduction_steps=["Depositar 1 ETH", "Llamar withdraw en bucle", "Vaciar la bóveda"],
        poc_code="function attack() external { pool.withdraw(); }",
        recommendation="Aplicar checks-effects-interactions o un guard de reentrada.",
        program="immunefi-ejemplo",
    )
    md = render_markdown(draft)
    for section in [
        "# Reentrancy drena la bóveda",
        "## Resumen",
        "## Severidad",
        "## Impacto",
        "## Invariante violada",
        "## Pasos para reproducir",
        "## Prueba de concepto (PoC)",
        "## Recomendación",
    ]:
        assert section in md, f"falta la sección {section}"
    assert "CRITICAL" in md
    assert "NX-001" in md
    assert "immunefi-ejemplo" in md
    assert "1. Depositar 1 ETH" in md
    assert "```solidity" in md


def test_severity_rationale_defined_for_all():
    for sev in Severity:
        assert severity_rationale(sev) != ""


def test_to_markdown_method_matches_function():
    draft = ReportDraft(finding=_finding(), summary="x", impact="y")
    assert draft.to_markdown() == render_markdown(draft)
