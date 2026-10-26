#!/usr/bin/env python3
"""NEXUS Offensive · Capa 3 (fork-validador) — runner del corte vertical mínimo.

Corre la suite Foundry del `twin/` y traduce el resultado a un veredicto
claro para el humano:

    ROMPE / NO ROMPE   +   invariante violada SÍ/NO   +   drena fondos SÍ/NO

====================================================================
LA JAULA PRIMERO  (regla invariable de todo el sistema)
====================================================================
Validar un contrato REAL exige forkear mainnet. Eso NUNCA se hace sin pasar
antes por `ScopeGuard.assert_allowed(address)`. El gancho vive en
`assert_in_scope_before_fork()` y se invoca en el modo `--target/--fork-url`.

El caso de JUGUETE de este corte vertical corre 100% local (despliega el
contrato en el EVM de Foundry, sin red real), así que no hay dirección de
mainnet que forkear y el gancho no llega a aplicarse — pero el código está
puesto y documentado para cuando lleguen las direcciones reales.

Ejemplos:
    # Caso de juguete (local, lo que demuestra el corte vertical):
    python run_validator.py

    # Enseñar el gancho de la jaula en acción (sin correr Foundry):
    python run_validator.py --demo-gate app.example.com
    python run_validator.py --demo-gate evil.attacker.net   # -> DENY

    # Diseño para contrato real (requiere RPC de archivo):
    python run_validator.py --target 0xabc... --fork-url https://... \\
        --scope ../config/scope.<programa>.yaml
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

TWIN_DIR = Path(__file__).resolve().parent
REPO_ROOT = TWIN_DIR.parent  # nexus-offensive/
DEFAULT_SCOPE = REPO_ROOT / "config" / "scope.ejemplo.yaml"

# Permite importar la Capa 0 (la jaula).
sys.path.insert(0, str(REPO_ROOT))

from core import AuditLog, ScopeGuard, Target  # noqa: E402

EXPLOIT_TEST = "test_PoC_reentrancy_drains_vault"
INVARIANT_TEST = "invariant_vaultIsSolvent"


# ---------------------------------------------------------------------------
# El gancho de la jaula — se llama ANTES de cualquier fork de dirección real.
# ---------------------------------------------------------------------------
def assert_in_scope_before_fork(address: str, scope_path: str | Path) -> None:
    """Puerta obligatoria: deniega forkear una dirección fuera de alcance.

    Lanza PermissionError si `address` no está explícitamente in-scope.
    Esta es la precondición de la Capa 3: no se abre un fork (ni, por tanto,
    ningún socket contra el RPC) sin autorización escrita reflejada en el scope.
    """
    guard = ScopeGuard.from_yaml(scope_path)
    guard.assert_allowed(Target(value=address, kind="contract"))


# ---------------------------------------------------------------------------
# Localización de binarios (forge / solc), tolerante a entornos offline.
# ---------------------------------------------------------------------------
def _find_forge() -> str:
    forge = shutil.which("forge") or str(Path.home() / ".foundry" / "bin" / "forge")
    if not Path(forge).exists():
        sys.exit("ERROR: no encuentro 'forge'. Instala Foundry (ver README).")
    return forge


def _find_solc() -> str | None:
    """solc local opcional (para entornos sin acceso a binaries.soliditylang.org)."""
    env = os.environ.get("NEXUS_SOLC")
    if env and Path(env).exists():
        return env
    solc_dir = Path.home() / ".foundry" / "solc"
    candidates = sorted(solc_dir.glob("solc-*")) if solc_dir.exists() else []
    return str(candidates[-1]) if candidates else None


# ---------------------------------------------------------------------------
# Ejecución de Foundry y parseo del veredicto.
# ---------------------------------------------------------------------------
def run_forge(fork_url: str | None = None) -> str:
    forge = _find_forge()
    cmd = [forge, "test", "-vv"]
    solc = _find_solc()
    if solc:
        cmd += ["--use", solc]
    if fork_url:
        cmd += ["--fork-url", fork_url]

    proc = subprocess.run(cmd, cwd=TWIN_DIR, capture_output=True, text=True)
    return proc.stdout + "\n" + proc.stderr


_RESULT_RE = re.compile(r"^\[(PASS|FAIL[^\]]*|SKIP)\]\s+([A-Za-z0-9_]+)")


def parse_results(text: str) -> dict[str, dict]:
    """Extrae {nombre_test: {status, logs}} de la salida `forge test -vv`."""
    results: dict[str, dict] = {}
    current: str | None = None
    in_logs = False
    for line in text.splitlines():
        s = line.strip()
        m = _RESULT_RE.match(s)
        if m:
            tag = m.group(1)
            status = "Success" if tag == "PASS" else ("Skipped" if tag == "SKIP" else "Failure")
            current = m.group(2)
            results[current] = {"status": status, "logs": []}
            in_logs = False
            continue
        if s == "Logs:":
            in_logs = True
            continue
        if in_logs:
            if s == "" or s.startswith(("Suite result", "Traces:", "Ran ")):
                in_logs = False
            elif current:
                results[current]["logs"].append(s)
    return results


def _status_of(results: dict[str, dict], needle: str) -> tuple[str, list[str]]:
    for name, result in results.items():
        if needle in name:
            return result["status"], result["logs"]
    return "NotFound", []


# ---------------------------------------------------------------------------
# Reporte
# ---------------------------------------------------------------------------
def report_verdict(results: dict[str, dict], *, target_label: str, scope_note: str) -> int:
    inv_status, _ = _status_of(results, INVARIANT_TEST)
    poc_status, poc_logs = _status_of(results, EXPLOIT_TEST)

    invariant_held = inv_status == "Success"
    poc_reproduced = poc_status == "Success"

    # El PoC asserta la violación y el drenaje; que PASE = quedó probado.
    invariant_violated = poc_reproduced
    drains_funds = poc_reproduced
    verdict = "ROMPE  (bug confirmado en el fork)" if poc_reproduced else "NO ROMPE"

    def si_no(b: bool) -> str:
        return "SÍ" if b else "NO"

    # Bitácora inmutable (Capa 0): deja rastro de la validación.
    audit = AuditLog(path=str(TWIN_DIR / "validation-audit.log"))
    audit.append(
        "twin.validate",
        {
            "target": target_label,
            "invariant_held_honest": invariant_held,
            "poc_reproduced": poc_reproduced,
            "verdict": "BREAKS" if poc_reproduced else "SAFE",
        },
    )

    line = "─" * 62
    print(line)
    print("NEXUS Offensive · fork-validador · veredicto")
    print(line)
    print(f"  Target                  : {target_label}")
    print(f"  Jaula (ScopeGuard)      : {scope_note}")
    print(f"  Invariante (uso honesto): {'SOSTENIDA' if invariant_held else 'FALLÓ'}  [{inv_status}]")
    print(f"  PoC reentrancy          : {'REPRODUCIDO' if poc_reproduced else 'NO reproducido'}  [{poc_status}]")
    print(f"    → invariante violada  : {si_no(invariant_violated)}")
    print(f"    → drena fondos        : {si_no(drains_funds)}")
    print(line)
    print(f"  VEREDICTO               : {verdict}")
    print(line)
    if poc_logs:
        print("  Evidencia del PoC (console.log en el EVM):")
        for log in poc_logs:
            print(f"    | {log}")
        print(line)
    print(f"  Bitácora: {TWIN_DIR / 'validation-audit.log'}  (cadena íntegra: {audit.verify().ok})")
    print(line)

    return 0 if poc_reproduced else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="NEXUS Offensive fork-validator runner")
    parser.add_argument("--target", help="Dirección del contrato real a validar (requiere --fork-url)")
    parser.add_argument("--fork-url", help="RPC de archivo para forkear mainnet")
    parser.add_argument("--scope", default=str(DEFAULT_SCOPE), help="YAML de scope de la jaula")
    parser.add_argument("--demo-gate", metavar="ADDR", help="Solo demuestra el gancho de la jaula y sale")
    args = parser.parse_args()

    # Modo demo: enseña la puerta de la jaula (sin correr Foundry).
    if args.demo_gate:
        print(f"Probando el gancho de la jaula contra: {args.demo_gate}")
        print(f"Scope: {args.scope}")
        try:
            assert_in_scope_before_fork(args.demo_gate, args.scope)
            print("→ ALLOW: in-scope. Se permitiría forkear.")
            return 0
        except PermissionError as exc:
            print(f"→ DENY: {exc}")
            print("  (No se forkea. La jaula bloqueó el acceso.)")
            return 2

    # Modo contrato real: la jaula PRIMERO, luego el fork.
    if args.target:
        if not args.fork_url:
            sys.exit("ERROR: --target requiere --fork-url (no se valida un contrato real sin fork).")
        print(f"Jaula: verificando scope de {args.target} antes de forkear...")
        try:
            assert_in_scope_before_fork(args.target, args.scope)
        except PermissionError as exc:
            print(f"→ DENY: {exc}")
            print("ABORTADO: fuera de alcance. No se abrió ningún fork.")
            return 2
        print("→ ALLOW: in-scope. Forkeando y validando...")
        results = parse_results(run_forge(fork_url=args.fork_url))
        return report_verdict(
            results,
            target_label=f"{args.target} (fork de mainnet)",
            scope_note=f"assert_allowed OK ({args.scope})",
        )

    # Modo por defecto: caso de JUGUETE, 100% local.
    results = parse_results(run_forge(fork_url=None))
    if not results:
        sys.exit("ERROR: forge no devolvió resultados de test. ¿Compila el proyecto?")
    return report_verdict(
        results,
        target_label="VulnerableVault (juguete, local)",
        scope_note="N/A — sin fork de red real; el gancho no aplica al caso local",
    )


if __name__ == "__main__":
    raise SystemExit(main())
