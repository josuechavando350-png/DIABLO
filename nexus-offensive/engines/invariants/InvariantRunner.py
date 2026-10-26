#!/usr/bin/env python3
"""NEXUS Offensive · Capa 2 — InvariantRunner (motor de invariantes).

Harness genérico que aplica el set de invariantes de cada familia DeFi y
reporta, por familia: qué invariantes se SOSTIENEN bajo fuzzing honesto y qué
PoCs ROMPEN la invariante clave (demostrando que el motor la detecta).

EXTENSIBILIDAD
--------------
El runner itera sobre `families.FAMILIES` (registro declarativo). Agregar una
familia nueva = agregar su interfaz + su set de invariantes en Solidity y una
entrada en `families.py`. ESTE ARCHIVO NO SE TOCA.

En Solidity, el set de invariantes es abstracto y genérico sobre la interfaz
de la familia (p.ej. `AmmInvariants` opera solo vía `IAmm`): para aplicarlo a
CUALQUIER contrato que implemente la interfaz, basta un test concreto de ~6
líneas que fije `amm`/`handler` y registre el handler como targetContract.

LA JAULA PRIMERO (regla invariable)
-----------------------------------
Para correr contra una dirección REAL hay que forkear mainnet. Eso no se hace
sin pasar antes por `ScopeGuard.assert_allowed(address)`. El gancho vive en
`assert_in_scope_before_fork()` (mismo patrón del twin/) y se invoca en el modo
`--target/--fork-url`. El set de juguete corre 100% local.

Ejemplos:
    python InvariantRunner.py                 # todas las familias (local)
    python InvariantRunner.py --family AMM     # una familia
    python InvariantRunner.py --demo-gate 0xabc...   # enseña el gancho
    python InvariantRunner.py --target 0xC0ntract --fork-url https://RPC \\
        --scope ../../config/scope.<programa>.yaml
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ENGINE_DIR = Path(__file__).resolve().parent
REPO_ROOT = ENGINE_DIR.parents[1]  # nexus-offensive/
DEFAULT_SCOPE = REPO_ROOT / "config" / "scope.ejemplo.yaml"

sys.path.insert(0, str(REPO_ROOT))
from core import ScopeGuard, Target  # noqa: E402

sys.path.insert(0, str(ENGINE_DIR))
from families import FAMILIES  # noqa: E402


# ---- gancho de la jaula ----------------------------------------------------
def assert_in_scope_before_fork(address: str, scope_path: str | Path) -> None:
    """Deniega forkear una dirección fuera de alcance (lanza PermissionError)."""
    guard = ScopeGuard.from_yaml(scope_path)
    guard.assert_allowed(Target(value=address, kind="contract"))


# ---- binarios --------------------------------------------------------------
def _find_forge() -> str:
    forge = shutil.which("forge") or str(Path.home() / ".foundry" / "bin" / "forge")
    if not Path(forge).exists():
        sys.exit("ERROR: no encuentro 'forge'. Instala Foundry (ver README).")
    return forge


def _find_solc() -> str | None:
    env = os.environ.get("NEXUS_SOLC")
    if env and Path(env).exists():
        return env
    solc_dir = Path.home() / ".foundry" / "solc"
    cands = sorted(solc_dir.glob("solc-*")) if solc_dir.exists() else []
    return str(cands[-1]) if cands else None


# ---- forge + parseo --------------------------------------------------------
def run_forge(fork_url: str | None = None) -> str:
    cmd = [_find_forge(), "test", "-vv"]
    solc = _find_solc()
    if solc:
        cmd += ["--use", solc]
    if fork_url:
        cmd += ["--fork-url", fork_url]
    proc = subprocess.run(cmd, cwd=ENGINE_DIR, capture_output=True, text=True)
    return proc.stdout + "\n" + proc.stderr


_RESULT_RE = re.compile(r"^\[(PASS|FAIL[^\]]*|SKIP)\]\s+([A-Za-z0-9_]+)")


def parse_results(text: str) -> dict[str, str]:
    """{nombre_test: 'Success'|'Failure'|'Skipped'} de `forge test -vv`."""
    results: dict[str, str] = {}
    for line in text.splitlines():
        m = _RESULT_RE.match(line.strip())
        if m:
            tag = m.group(1)
            status = "Success" if tag == "PASS" else ("Skipped" if tag == "SKIP" else "Failure")
            results[m.group(2)] = status
    return results


# ---- reporte ---------------------------------------------------------------
def report(results: dict[str, str], families: list[dict]) -> int:
    line = "─" * 70
    print(line)
    print("NEXUS Offensive · Capa 2 · motor de invariantes por familia")
    print(line)

    all_ok = True
    for fam in families:
        held = [inv for inv in fam["invariants"] if results.get(inv["test"]) == "Success"]
        broken_inv = [inv for inv in fam["invariants"] if results.get(inv["test"]) not in (None, "Success")]
        detected = [ex for ex in fam["exploits"] if results.get(ex["test"]) == "Success"]

        held_ok = len(held) == len(fam["invariants"])
        exploits_ok = len(detected) == len(fam["exploits"])
        fam_ok = held_ok and exploits_ok
        all_ok = all_ok and fam_ok

        print(f"\n■ {fam['name']}  (interfaz {fam['interface']})")
        print(f"    invariantes sostenidas (fuzzing honesto): {len(held)}/{len(fam['invariants'])}")
        for inv in fam["invariants"]:
            status = results.get(inv["test"], "NotFound")
            mark = "✓" if status == "Success" else "✗"
            print(f"      {mark} {inv['id']}  {inv['desc']}")
        print(f"    PoCs que rompen invariante clave: {len(detected)}/{len(fam['exploits'])}")
        for ex in fam["exploits"]:
            status = results.get(ex["test"], "NotFound")
            mark = "✓" if status == "Success" else "✗"
            print(f"      {mark} rompe {ex['breaks']}: {ex['desc']}")
        print(f"    => {'OK' if fam_ok else 'FALLO'}")

    print("\n" + line)
    print(f"RESULTADO GLOBAL: {'TODO VERDE' if all_ok else 'HAY FALLOS'}")
    print(line)
    return 0 if all_ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="NEXUS Offensive · InvariantRunner (Capa 2)")
    parser.add_argument("--family", help="Correr solo una familia (p.ej. AMM, Lending, Vault4626, Staking)")
    parser.add_argument("--target", help="Dirección de contrato real a validar (requiere --fork-url)")
    parser.add_argument("--fork-url", help="RPC de archivo para forkear mainnet")
    parser.add_argument("--scope", default=str(DEFAULT_SCOPE), help="YAML de scope de la jaula")
    parser.add_argument("--demo-gate", metavar="ADDR", help="Solo demuestra el gancho de la jaula y sale")
    args = parser.parse_args()

    if args.demo_gate:
        print(f"Probando el gancho de la jaula contra: {args.demo_gate}  (scope: {args.scope})")
        try:
            assert_in_scope_before_fork(args.demo_gate, args.scope)
            print("→ ALLOW: in-scope. Se permitiría forkear.")
            return 0
        except PermissionError as exc:
            print(f"→ DENY: {exc}\n  (No se forkea. La jaula bloqueó el acceso.)")
            return 2

    if args.target:
        if not args.fork_url:
            sys.exit("ERROR: --target requiere --fork-url (no se valida un contrato real sin fork).")
        print(f"Jaula: verificando scope de {args.target} antes de forkear...")
        try:
            assert_in_scope_before_fork(args.target, args.scope)
        except PermissionError as exc:
            print(f"→ DENY: {exc}\nABORTADO: fuera de alcance. No se abrió ningún fork.")
            return 2
        print("→ ALLOW: in-scope. Forkeando y aplicando invariantes...")
        results = parse_results(run_forge(fork_url=args.fork_url))
        return report(results, FAMILIES)

    families = FAMILIES
    if args.family:
        families = [f for f in FAMILIES if f["name"].lower() == args.family.lower()]
        if not families:
            names = ", ".join(f["name"] for f in FAMILIES)
            sys.exit(f"ERROR: familia '{args.family}' no existe. Disponibles: {names}")

    results = parse_results(run_forge())
    if not results:
        sys.exit("ERROR: forge no devolvió resultados. ¿Compila el proyecto?")
    return report(results, families)


if __name__ == "__main__":
    raise SystemExit(main())
