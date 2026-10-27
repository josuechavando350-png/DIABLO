# Cobertura del motor de invariantes vs. Damn Vulnerable DeFi

Entrenamiento del motor de invariantes (Capa 2) contra retos reales de Damn
Vulnerable DeFi v4 (CTF educativo de tinchoabbate / The Red Guild), resueltos
100% en local. Por cada reto: PoC que pasa la condición de éxito oficial + la
invariante que atrapa el bug (se sostiene en el estado inicial, se rompe tras
el exploit).

**Estado:** 9 retos resueltos y mapeados. Los huecos que reveló la primera
tanda ya están **cerrados en el motor** (familias Flash Loan y Oráculo +
invariante V4, ver `../../engines/invariants/`).

## Mapa reto → familia → invariante (9 resueltos)

| Reto | Familia | Clase de bug | Invariante que lo atrapa | Catálogo Capa 2 |
|------|---------|--------------|--------------------------|-----------------|
| **unstoppable** | Vault ERC-4626 | Donación directa rompe contabilidad (DoS) | **V4** `totalAssets() == totalSupply()` | 🟢 CUBIERTO (V4 agregada) |
| **naive-receiver** | Flash loan / acceso | Falta de autorización (fee a receiver ajeno + spoof forwarder) | **FL3** autorización de movimientos | 🟢 CUBIERTO (familia FlashLoan) |
| **side-entrance** | Flash loan / acceso | Repago confundido con solvencia (reentrada) | **FL4** `balanceHeld ≥ Σ depósitos` | 🟢 CUBIERTO (familia FlashLoan) |
| **the-rewarder** | Staking / rewards | Reclamo múltiple en una tx | **S1** reclamado ≤ asignación | 🟢 CUBIERTO (ya existía) |
| **truster** | Flash loan / acceso | Llamada externa arbitraria (approve abuse) | **FL2** `allowance(pool, tercero) == 0` | 🟢 CUBIERTO (familia FlashLoan) |
| **puppet** | Oráculo / Precio | Manipulación de spot de AMM | **O1** precio resistente a manipulación | 🟢 CUBIERTO (familia Oráculo) |
| **selfie** | Flash loan / gobernanza | Poder de voto tomado en préstamo | Flash loan: quórum no alcanzable con tokens prestados | 🟢 CUBIERTO (familia FlashLoan) |
| **abi-smuggling** | Control de acceso | Contrabando de ABI (selector autorizado ≠ ejecutado) | FL3 (autorización): función ejecutada == permiso del llamante | 🟢 CUBIERTO (refuerza FL3) |
| **compromised** | Oráculo / Precio | Fuentes del oráculo comprometidas (claves filtradas) | **O2** mediana robusta salvo mayoría comprometida | 🟢 CUBIERTO (familia Oráculo) |

**Resultado:** tras cerrar los huecos, los **9 retos resueltos quedan cubiertos**
por una invariante del catálogo. La familia **Flash Loan / control de acceso**
(FL1–FL4) nació de naive-receiver/side-entrance/truster; la familia **Oráculo**
(O1–O2) de puppet/compromised; la invariante **V4** de unstoppable.

## Huecos que se cerraron en el motor (Capa 2)

Lo que la primera tanda marcó como hueco ya está implementado, con contrato
sano + vulnerable + PoC + fuzzing, en `engines/invariants/`:

- **Familia Flash Loan / Control de acceso** — FL1 conservación, FL2 sin
  llamadas/allowance arbitrarias, FL3 autorización de movimientos, FL4
  solvencia bajo reentrada.
- **Familia Oráculo / Precio** — O1 precio resistente a manipulación (TWAP vs
  spot). (O2, robustez ante compromiso de fuentes, queda demostrada aquí por el
  reto compromised; como invariante formal del motor es la extensión natural.)
- **Vault V4** — contabilidad estricta `totalAssets == totalSupply`.

## Retos DVD v4 restantes (estado)

Total DVD v4 ≈ 18 retos. 9 resueltos arriba. Los demás:

| Reto | Estado | Motivo |
|------|--------|--------|
| **puppet-v3** | 🔴 FUERA DE ALCANCE | Requiere **fork de mainnet** (`createSelectFork`). Viola la regla "100% local, sin mainnet". RPC real = PENDIENTE DE INPUT. |
| **curvy-puppet** | 🔴 FUERA DE ALCANCE | Requiere **fork de mainnet** (pools Curve reales). RPC real = PENDIENTE DE INPUT. |
| **puppet-v2** | 🟡 DIFERIDO | Factible local; necesita vendorizar Uniswap V2 (v2-core/periphery). Familia ya cubierta (Oráculo O1). |
| **free-rider** | 🟡 DIFERIDO | Uniswap V2 flashswap + marketplace de NFT. Dep. pesadas (v2). |
| **backdoor** | 🟡 DIFERIDO | Gnosis Safe wallet factory + módulo. Dep. pesadas (safe-smart-account). |
| **climber** | 🟡 DIFERIDO | Timelock + proxy UUPS upgradeable. Dep. oz-upgradeable. |
| **wallet-mining** | 🟡 DIFERIDO | Deploy determinista (Safe + create2). Muy complejo. |
| **shards** | 🟡 DIFERIDO | Marketplace de shards de NFT con bug de redondeo. |
| **withdrawal** | 🟡 DIFERIDO | Puente L1/L2 con cola de retiros Merkle. Datos + complejidad. |

Los 2 **fuera de alcance** lo están por la regla de no tocar mainnet (necesitan
un RPC de archivo real, marcado PENDIENTE DE INPUT). Los 7 **diferidos** son
factibles en local pero requieren vendorizar dependencias pesadas (Uniswap V2,
Safe, OZ-upgradeable) o reproducir mecánicas extensas; sus clases de bug ya
están representadas por familias del motor (Oráculo, Flash Loan/acceso), así
que no abren huecos nuevos del catálogo — solo falta el PoC específico.

## Estado de los PoCs

`forge test` — 9/9 verde. Cada test demuestra la invariante **sosteniéndose al
inicio** y **rompiéndose tras el exploit**, y cumple la condición de éxito
oficial del reto (`_isSolved`, "DO NOT TOUCH").

## Alcance y legalidad

Material **educativo**, ejecutado **100% en local** (sin red real, sin ninguna
dirección de mainnet ni de producción). Las claves usadas en `compromised` son
datos del propio reto (CTF), no secretos reales. Damn Vulnerable DeFi es
open-source y está diseñado para explotarse localmente con fines de aprendizaje.
