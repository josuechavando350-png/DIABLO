# training/dvd — Damn Vulnerable DeFi (entrenamiento del motor)

Banco de pruebas que enfrenta el **motor de invariantes (Capa 2)** contra
contratos vulnerables **reales de nivel profesional**: 6 retos de
[Damn Vulnerable DeFi](https://damnvulnerabledefi.xyz) v4 (CTF open-source,
material educativo diseñado para explotarse en local).

Corre **100% local**, sin red real ni direcciones de producción.

> **Alcance:** solo estos 6 retos, en local. No es una capa nueva del sistema;
> es entrenamiento/validación del motor contra bugs reales, y un **reporte de
> huecos** (`COBERTURA.md`) de qué le falta al catálogo.

## Los 6 retos (cubren las 4 familias + descubren huecos)

| Reto | Familia | Invariante | Catálogo |
|------|---------|-----------|----------|
| unstoppable | Vault 4626 | `totalAssets == totalSupply` | 🔴 hueco |
| naive-receiver | Flash loan / acceso | autorización de movimientos | 🔴 hueco |
| side-entrance | Flash loan pool | solvencia `balance >= Σ depósitos` | 🟡 reusa |
| the-rewarder | Staking / rewards | S1 reclamado ≤ asignación | 🟢 cubierto |
| truster | Flash loan / acceso | pool no otorga allowance arbitraria | 🔴 hueco |
| puppet | Oráculo / Lending | colateral con precio no manipulable | 🔴 hueco |

El análisis completo de cobertura y **huecos** (lo más importante) está en
[`COBERTURA.md`](./COBERTURA.md).

## Qué entrega cada reto

Cada `test/<reto>/<Reto>.t.sol` contiene:
1. El **setup y la condición de éxito oficiales** de DVD (verbatim, `_isSolved`).
2. El **PoC** que resuelve el reto (el test pasa).
3. La **invariante** que atrapa el bug, demostrada **sosteniéndose al inicio** y
   **rompiéndose tras el exploit** (reusa una invariante del catálogo Capa 2 si
   aplica; si no, se escribe nueva y se marca como hueco en `COBERTURA.md`).
4. **Documentación en español** en la cabecera: clase de bug, familia, invariante.

## Cómo correrlo

```bash
cd training/dvd
forge test -vv
```

En este entorno se usa `solc 0.8.25` local (el proxy bloquea la descarga
automática de solc); el entorno ya lo tiene en `~/.foundry/solc/solc-0.8.25`:

```bash
forge test --use ~/.foundry/solc/solc-0.8.25 -vv
```

## Integración

- **forge-std reusado** del `twin/` por symlink (`lib/forge-std`), sin duplicar.
- Dependencias de DVD vendorizadas (solmate, solady, openzeppelin-contracts,
  murky) en `lib/`.
- Contratos de los retos tomados de DVD v4 (`src/`), con sus datos
  (`builds/uniswap/`, `test/the-rewarder/*.json`).

## Relación con la jaula

Esto corre contra contratos de JUGUETE desplegados localmente en el EVM de
Foundry: no hay fork de mainnet ni dirección real, por lo que el gancho
`ScopeGuard.assert_allowed()` no aplica aquí (igual que en el caso local del
`twin/`). Cualquier futura corrida contra una dirección real seguiría pasando
primero por la jaula, como ya hace el `InvariantRunner` de la Capa 2.
