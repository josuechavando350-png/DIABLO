# twin/ — Fork-validador (corte vertical mínimo)

Capa 3 del proyecto. **El núcleo**: probar con certeza —ejecutando el PoC en
un fork del EVM— que un bug **drena fondos**, antes de reportar. Aquí no se
opina; o el PoC vacía la bóveda o no.

Este corte vertical **no** es la pieza completa. Su único objetivo es
demostrar que el pipeline funciona end-to-end sobre un contrato de juguete:

```
contrato  →  invariante  →  fork/EVM  →  PoC  →  veredicto (ROMPE / NO ROMPE)
```

## Qué hay dentro

| Archivo | Qué es |
|---|---|
| `src/VulnerableVault.sol` | Contrato **de juguete**, intencionalmente vulnerable a **reentrancy**. Educativo. **No es producción, no se despliega.** |
| `test/Invariant.t.sol` | La **propiedad que debe cumplirse siempre**: solvencia (`activos == suma de saldos`). Con fuzzing de estado y actores honestos, **se sostiene**. |
| `test/handlers/HonestHandler.sol` | Actores honestos (solo depósitos/retiros válidos) para el invariante. |
| `test/Exploit.t.sol` | El **PoC**: re-entra en `withdraw()` y vacía la bóveda. Que el test **pase** = el exploit se reprodujo → la invariante se rompe y **drena fondos**. |
| `run_validator.py` | Runner que corre Foundry y da el **veredicto claro** + el **gancho de la jaula**. |

## El bug (educativo)

`VulnerableVault.withdraw()` envía el ETH **antes** de poner el saldo a cero
(viola *checks-effects-interactions*). Un atacante con un `receive()` que
vuelve a llamar a `withdraw()` retira en bucle con el mismo saldo y vacía la
bóveda. El atacante arriesga **1 ETH** y se lleva **6** (su 1 + los 5 de las
víctimas).

## Requisitos

- **Foundry** (`forge` + `anvil`). Instalación normal:
  ```bash
  curl -L https://foundry.paradigm.xyz | bash && foundryup
  ```
  (En este entorno se instaló descargando el release estático de Foundry y un
  `solc` 0.8.24 estático, porque el proxy bloquea `binaries.soliditylang.org`.
  El runner detecta `~/.foundry/solc/solc-*` o `$NEXUS_SOLC` y lo pasa con
  `--use` automáticamente.)
- `forge-std` ya viene **vendorizado** en `lib/forge-std/` (repo autocontenido).

## Cómo correrlo

### Opción A — Foundry directo
```bash
cd twin
forge test -vv
```

### Opción B — runner con veredicto (recomendado)
```bash
cd twin
python3 run_validator.py
```
Da el veredicto **ROMPE / NO ROMPE**, con *invariante violada SÍ/NO*, *drena
fondos SÍ/NO*, la evidencia (`console.log` del EVM) y lo deja registrado en una
bitácora inmutable con hash encadenado (Capa 0).

## Qué demuestra

1. **Invariante bajo uso honesto → SOSTENIDA.** El fuzzer lanza miles de
   depósitos/retiros honestos y la solvencia nunca se rompe. Esa es la
   propiedad que *debería* cumplirse siempre.
2. **PoC → la rompe con certeza.** El exploit de reentrancy vacía la bóveda;
   el runner reporta `DRENA FONDOS: SÍ`, `INVARIANTE VIOLADA: SÍ`, veredicto
   **ROMPE**. Esto es la "certeza del 100%": no es lectura de código, es el
   ataque ejecutado en el EVM.

## Integración con la jaula (la regla invariable)

> **Ninguna capa abre un socket sin llamar antes a
> `ScopeGuard.assert_allowed(address)`.**

Validar un contrato **real** exige forkear mainnet (abrir un socket al RPC de
archivo). El runner **nunca** forkea una dirección sin pasar antes por la
jaula. El gancho está en `run_validator.py`:

```python
def assert_in_scope_before_fork(address, scope_path):
    guard = ScopeGuard.from_yaml(scope_path)
    guard.assert_allowed(Target(value=address, kind="contract"))  # PermissionError si no
```

El caso de juguete corre **100% local** (el contrato se despliega en el EVM de
Foundry, sin red real), así que no hay dirección de mainnet que forkear y el
gancho no llega a aplicarse — pero está puesto y documentado. Se puede ver en
acción sin tocar Foundry:

```bash
python3 run_validator.py --demo-gate app.example.com            # ALLOW
python3 run_validator.py --demo-gate app.example.com.attacker.net  # DENY (truco de sufijo)
python3 run_validator.py --demo-gate admin.example.com          # DENY (out_scope)
```

Y el diseño para un contrato real (requiere un RPC de archivo; `anvil
--fork-url <RPC>` sirve como fork local):

```bash
python3 run_validator.py --target 0xCONTRATO --fork-url https://RPC \
    --scope ../config/scope.<programa>.yaml
# -> si la dirección no está in-scope: DENY y NO se forkea.
```

## Alcance de este corte

Esto es **solo** el corte vertical del fork-validador sobre un caso de
juguete, para validar el pipeline. **No** incluye el observador, los motores
de análisis completos (fuzzing de invariantes a escala, simbólico, diffing),
ni ninguna otra capa.
