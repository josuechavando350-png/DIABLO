# Cobertura del motor de invariantes vs. Damn Vulnerable DeFi

Entrenamiento del motor de invariantes (Capa 2) contra **6 retos reales** de
Damn Vulnerable DeFi v4 (CTF educativo de tinchoabbate / The Red Guild),
resueltos 100% en local. Por cada reto: PoC que pasa la condición de éxito +
la invariante que atrapa el bug (se sostiene en el estado inicial, se rompe
tras el exploit).

**Este reporte de huecos es el entregable clave:** muestra qué clases de bug
del mundo real **NO** cubría el catálogo actual del motor.

## Mapa reto → familia → invariante

| Reto | Familia | Clase de bug | Invariante que lo atrapa | ¿Catálogo Capa 2? |
|------|---------|--------------|--------------------------|-------------------|
| **unstoppable** | Vault ERC-4626 | Ruptura de contabilidad por donación directa (DoS) | `totalAssets() == totalSupply()` (shares 1:1, sin tokens no contabilizados) | 🔴 **HUECO** — V1 usaba `>=`, no detecta la donación |
| **naive-receiver** | Flash loan / acceso | Falta de autorización (fee a receiver ajeno + spoof de `_msgSender` vía forwarder/multicall) | Autorización: los fondos de una cuenta solo se mueven con su consentimiento | 🔴 **HUECO** — no existía familia flash-loan ni invariante de autorización |
| **side-entrance** | Flash loan pool | Repago confundido con solvencia (reentrada vía `deposit`) | Solvencia: `balance(pool) >= Σ balances[u]` | 🟡 **REUSA** concepto de solvencia (Lending L1/L3, Vault V3); vector nuevo |
| **the-rewarder** | Staking / rewards | Reclamo múltiple en una tx (claim no marcado) | **S1**: lo reclamado por un beneficiario ≤ su asignación | 🟢 **CUBIERTO** — reusa Capa 2 Staking S1 |
| **truster** | Flash loan / acceso | Llamada externa arbitraria con la autoridad del pool (approve abuse) | `token.allowance(pool, tercero) == 0` (el pool no otorga permiso de gasto) | 🔴 **HUECO** — sin invariante de control de acceso / llamada arbitraria |
| **puppet** | Oráculo / Lending | Manipulación de oráculo de precio spot (AMM) | Colateral valuado con precio resistente a manipulación: `depositRequired(x) >= x·precioJusto·2` | 🔴 **HUECO** — Lending L2 asumía precio fijo/honesto |

Resumen: de 6 retos, **1 queda cubierto** por el catálogo (the-rewarder → S1),
**1 por concepto reutilizado** (side-entrance → solvencia), y **4 revelan
huecos** (unstoppable, naive-receiver, truster, puppet).

## 🔴 Huecos detectados = qué agregar al motor (Capa 2)

Los retos reales exponen **dos familias nuevas** y **una invariante más estricta**
que el catálogo de juguete no tenía. Esta es la lista de trabajo para extender
el motor:

### 1. Familia nueva: **Flash Loan / Control de acceso**
Cubre unstoppable (en parte), naive-receiver, side-entrance y truster. Invariantes a agregar:

- **FL1 · Conservación de flash loan.** Tras `flashLoan`, el balance del pool
  nunca es menor que antes, y el movimiento neto del prestatario es cero salvo
  la comisión. (side-entrance la rompe depositando lo prestado; truster la
  rompe drenando después vía allowance.)
- **FL2 · Sin llamadas/allowance arbitrarias.** Un pool nunca ejecuta una
  llamada externa con parámetros del atacante ni otorga `allowance` de sus
  fondos a terceros. (truster.)
- **FL3 · Autorización de movimientos.** Los fondos de una cuenta solo se
  mueven con su consentimiento; un fee/retiro no puede imputarse a una cuenta
  que no inició la acción. (naive-receiver.)
- **FL4 · Solvencia de pool con reentrada.** `balance(pool) >= Σ pasivos`
  evaluado también dentro de callbacks (reentrada vía `deposit`). (side-entrance;
  reusa el concepto de solvencia de Lending/Vault, pero aplicado al pool de
  flash loans.)

### 2. Familia nueva: **Oráculo / Precio**
Cubre puppet. Invariante a agregar:

- **O1 · Precio resistente a manipulación.** Toda valuación con consecuencias
  económicas (colateral, liquidación, minteo) debe usar un precio NO
  manipulable en una sola tx (p.ej. TWAP o oráculo externo), nunca el spot de
  un AMM. Operacionalmente: el colateral exigido no puede caer por debajo del
  valor justo tras una operación dentro del mismo bloque. (puppet.)

### 3. Invariante más estricta en la familia **Vault ERC-4626**
- **V4 · Sin activos no contabilizados.** Para vaults con relación fija (o que
  ofrecen flash loans), `totalAssets() == totalSupply()` (igualdad estricta),
  no solo `>=`. Una donación directa rompe la igualdad y puede inutilizar el
  contrato. (unstoppable.) El catálogo Capa 2 solo tenía V1 con `>=`.

## Estado de los PoCs

`forge test` — 6/6 verde. Cada test demuestra la invariante **sosteniéndose al
inicio** y **rompiéndose tras el exploit**, además de cumplir la condición de
éxito oficial del reto (`_isSolved`).

| Reto | Test | Evidencia |
|------|------|-----------|
| unstoppable | `test_unstoppable` | INV `totalAssets==totalSupply`: true → false |
| naive-receiver | `test_naiveReceiver` | receiver vaciado de 10 → 0 WETH sin pedirlo |
| side-entrance | `test_sideEntrance` | pool insolvente tras reentrada |
| the-rewarder | `test_theRewarder` | reclamado 9.99 DVT vs asignación 0.0115 DVT (~866×) |
| truster | `test_truster` | pool otorgó allowance de 1 000 000 DVT al atacante |
| puppet | `test_puppet` | colateral por token 2.0 → 0.0002 ETH tras manipular el spot |

## Alcance y legalidad

Material **educativo**, ejecutado **100% en local** (sin red real, sin ninguna
dirección de mainnet ni de producción). Damn Vulnerable DeFi es open-source y
está diseñado para explotarse localmente con fines de aprendizaje.
