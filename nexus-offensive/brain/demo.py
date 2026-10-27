#!/usr/bin/env python3
"""Demo end-to-end de NEXUS Offensive (100% local).

Observa un "deploy" in-scope, valida en un fork (EVM) con un PoC real del motor
(Capa 2), y genera un borrador de reporte. Un segundo evento out-of-scope es
bloqueado por la jaula y no se toca.

Uso:
    python brain/demo.py [directorio_de_reportes]
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core import AuditLog, ScopeGuard  # noqa: E402
from watch import ChainEvent, MockChainSource  # noqa: E402
from brain import ForgeValidator, Pipeline  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
IN_SCOPE_ADDR = "0x00000000000000000000000000000000vault01"
OUT_SCOPE_ADDR = "0x000000000000000000000000000000000evil02"


def main() -> int:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="nexus-reports-"))

    guard = ScopeGuard(in_scope=[IN_SCOPE_ADDR], out_scope=[], rps=1.0, program="demo-local")
    audit = AuditLog()

    source = MockChainSource(
        [
            ChainEvent("deploy", IN_SCOPE_ADDR, 1, "local"),  # in-scope → se valida
            ChainEvent("deploy", OUT_SCOPE_ADDR, 2, "local"),  # out-of-scope → bloqueado
        ]
    )

    validator = ForgeValidator(
        REPO / "engines" / "invariants",
        match_test="test_PoC_V4_donation_breaks_strict_accounting",
        invariant="totalAssets() == totalSupply() (contabilidad estricta del vault)",
        poc_ref="engines/invariants/test/exploits/VaultV4Exploit.t.sol",
    )

    pipe = Pipeline(guard, source, validator, audit_log=audit, report_dir=out_dir)
    reports = pipe.run_once()

    print("── NEXUS Offensive · demo end-to-end ──")
    print(f"observados in-scope : {len(pipe.observer.seen_in_scope)}")
    print(f"bloqueados por jaula: {len(pipe.observer.skipped_out_of_scope)} (out-of-scope)")
    print(f"reportes generados  : {len(reports)}")
    print(f"bitacora integra    : {audit.verify().ok}")
    for finding, _md, path in reports:
        print(f"  -> {finding.id} [{finding.severity.value}] {finding.title}")
        print(f"     reporte: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
