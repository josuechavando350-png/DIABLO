"""Tests de la integración end-to-end (brain/)."""

import shutil
from pathlib import Path

import pytest

from core import AuditLog, ScopeGuard
from watch import ChainEvent, MockChainSource
from brain import ForgeValidator, FunctionValidator, Pipeline, ValidationResult

REPO = Path(__file__).resolve().parents[1]


def test_pipeline_end_to_end_deterministic(tmp_path):
    """Observador → validación → Finding → reporte → bitácora, determinista."""
    guard = ScopeGuard(in_scope=["0xvault01"], out_scope=[], rps=1.0)
    audit = AuditLog()
    src = MockChainSource(
        [
            ChainEvent("deploy", "0xvault01", 1, "local"),  # in-scope
            ChainEvent("deploy", "0xevil02", 2, "local"),  # out-of-scope (default-deny)
        ]
    )

    def validate(target, event):
        return ValidationResult(
            breaks=True, invariant="k=r0*r1 nunca decrece", poc_ref="AmmExploit.t.sol"
        )

    pipe = Pipeline(guard, src, FunctionValidator(validate), audit_log=audit, report_dir=tmp_path)
    reports = pipe.run_once()

    # Solo el contrato in-scope produjo un reporte; el out-of-scope fue bloqueado.
    assert len(reports) == 1
    assert len(pipe.observer.seen_in_scope) == 1
    assert len(pipe.observer.skipped_out_of_scope) == 1

    finding, md, path = reports[0]
    assert finding.id == "NX-001"
    assert path.exists()
    assert "## Pasos para reproducir" in md
    assert "k=r0*r1 nunca decrece" in md
    # La cadena registró observaciones + validación y sigue íntegra.
    assert audit.verify().ok


def test_pipeline_no_report_when_invariant_holds(tmp_path):
    guard = ScopeGuard(in_scope=["0xvault01"], out_scope=[], rps=1.0)
    src = MockChainSource([ChainEvent("deploy", "0xvault01", 1)])
    validator = FunctionValidator(lambda t, e: ValidationResult(breaks=False, invariant="k"))
    pipe = Pipeline(guard, src, validator, report_dir=tmp_path)
    assert pipe.run_once() == []
    assert pipe.findings == []


def test_pipeline_with_real_forge_validator(tmp_path):
    """End-to-end REAL: el fork-validador ejecuta un PoC del motor en el EVM."""
    forge = shutil.which("forge") or str(Path.home() / ".foundry" / "bin" / "forge")
    if not Path(forge).exists():
        pytest.skip("forge no disponible en este entorno")

    guard = ScopeGuard(in_scope=["0xvault01"], out_scope=[], rps=1.0)
    audit = AuditLog()
    src = MockChainSource([ChainEvent("deploy", "0xvault01", 1, "local")])
    validator = ForgeValidator(
        REPO / "engines" / "invariants",
        match_test="test_PoC_V4_donation_breaks_strict_accounting",
        invariant="totalAssets() == totalSupply()",
        poc_ref="engines/invariants/test/exploits/VaultV4Exploit.t.sol",
    )
    pipe = Pipeline(guard, src, validator, audit_log=audit, report_dir=tmp_path)
    reports = pipe.run_once()

    assert len(reports) == 1, "el PoC real debería confirmar la ruptura de la invariante"
    finding, md, path = reports[0]
    assert "totalAssets" in md
    assert path.exists()
    assert audit.verify().ok
