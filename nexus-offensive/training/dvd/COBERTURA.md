# Cobertura del motor de invariantes vs. Damn Vulnerable DeFi

Entrenamiento del motor de invariantes (Capa 2) contra retos reales de Damn
Vulnerable DeFi v4 (CTF educativo de tinchoabbate / The Red Guild), resueltos
100% en local. Por cada reto: PoC que pasa la condición de éxito oficial + la
invariante que atrapa el bug (se sostiene en el estado inicial, se rompe tras
el exploit) + documentación en español.

**Estado: 15 de 18 retos resueltos.** Los huecos que reveló la primera tanda
ya están **cerrados en el motor** (familias Flash Loan y Oráculo + invariante
V4, ver `../../engines/invariants/`).

## Mapa reto → familia → invariante (15 resueltos)

| # | Reto | Familia | Invariante que lo atrapa | Catálogo Capa 2 |
|---|------|---------|--------------------------|-----------------|
| 1 | **unstoppable** | Vault ERC-4626 | **V4** `totalAssets() == totalSupply()` | 🟢 CUBIERTO (V4) |
| 2 | **naive-receiver** | Flash loan / acceso | **FL3** autorización de movimientos | 🟢 CUBIERTO |
| 3 | **side-entrance** | Flash loan / acceso | **FL4** solvencia bajo reentrada | 🟢 CUBIERTO |
| 4 | **the-rewarder** | Staking / rewards | **S1** reclamado ≤ asignación | 🟢 CUBIERTO |
| 5 | **truster** | Flash loan / acceso | **FL2** sin llamada/allowance arbitraria | 🟢 CUBIERTO |
| 6 | **puppet** | Oráculo / Precio | **O1** precio resistente a manipulación | 🟢 CUBIERTO |
| 7 | **selfie** | Flash loan / gobernanza | quórum no alcanzable con voto prestado | 🟢 CUBIERTO (familia FL) |
| 8 | **abi-smuggling** | Control de acceso | FL3: selector ejecutado == permiso | 🟢 CUBIERTO |
| 9 | **compromised** | Oráculo / Precio | **O2** mediana robusta ante fuentes comprometidas | 🟢 CUBIERTO (familia Oráculo) |
| 10 | **puppet-v2** | Oráculo / Precio | **O1** precio resistente (Uniswap V2) | 🟢 CUBIERTO |
| 11 | **free-rider** | Marketplace / flujo de fondos | comprar cuesta al comprador (no le paga) | 🟡 relacionado FL (flujo de fondos) |
| 12 | **shards** | Marketplace / redondeo | reembolso nunca excede lo pagado | 🟡 relacionado V3 (redondeo a favor del protocolo) |
| 13 | **climber** | Control de acceso / timelock | no se ejecuta sin op agendada (checks antes de effects) | 🟢 CUBIERTO (familia FL / acceso) |
| 14 | **withdrawal** | Control de acceso / puente | retiro finalizado mueve sus fondos o ninguno | 🟢 CUBIERTO (familia FL / acceso) |
| 15 | **backdoor** | Control de acceso / init | init de wallet no otorga permisos a terceros | 🟢 CUBIERTO (familia FL / acceso) |

**Resultado:** los 15 retos quedan cubiertos (o directamente relacionados) por
una invariante del catálogo. Las familias nacieron del entrenamiento:
**Flash Loan / control de acceso** (FL1–FL4) de naive-receiver/side-entrance/
truster/selfie/abi-smuggling/climber/withdrawal/backdoor; **Oráculo** (O1–O2)
de puppet/compromised/puppet-v2; **V4** de unstoppable. free-rider y shards
tocan flujo de fondos y redondeo (relacionados con FL y Vault V3).

## Huecos del catálogo que se cerraron (Capa 2)

Implementados con contrato sano + vulnerable + PoC + fuzzing en `engines/invariants/`:

- **Familia Flash Loan / Control de acceso** — FL1 conservación, FL2 sin
  llamadas/allowance arbitrarias, FL3 autorización, FL4 solvencia bajo reentrada.
- **Familia Oráculo / Precio** — O1 precio resistente a manipulación (TWAP vs
  spot). (O2, robustez ante compromiso de fuentes, demostrada por compromised.)
- **Vault V4** — contabilidad estricta `totalAssets == totalSupply`.

**Huecos nuevos de catálogo que quedan: 0.** Los 3 retos sin resolver (abajo)
caen en familias ya representadas; no abren huecos nuevos.

## Retos DVD v4 restantes (3 de 18)

| Reto | Estado | Motivo |
|------|--------|--------|
| **wallet-mining** | 🟡 DIFERIDO | El más complejo de DVD: requiere *create2 mining* del address exacto (reconstruyendo el initializer exacto que usó el reto), una colisión de storage en el `TransparentProxy`/authorizer, y firma EIP-712 de una tx de Safe con la llave del usuario, todo en una sola tx. No abre hueco nuevo de catálogo (acceso/deploy). No se incluyó para no comprometer la regla "todo verde, sin esqueletos". |
| **puppet-v3** | 🔴 FUERA DE ALCANCE | Requiere **fork de mainnet** (`createSelectFork`). Viola "100% local, sin mainnet". RPC real = PENDIENTE DE INPUT. |
| **curvy-puppet** | 🔴 FUERA DE ALCANCE | Requiere **fork de mainnet** (pools Curve reales). RPC real = PENDIENTE DE INPUT. |

Los 2 **fuera de alcance** necesitan un RPC de archivo real (PENDIENTE DE
INPUT). **wallet-mining** es factible en local pero es el reto más intrincado;
su clase de bug (control de acceso + despliegue determinista) ya está
representada por la familia Flash Loan / control de acceso.

## Estado de los PoCs

`forge test` — **15/15 verde**. Cada test demuestra la invariante
**sosteniéndose al inicio** y **rompiéndose tras el exploit**, y cumple la
condición de éxito oficial del reto (`_isSolved`, "DO NOT TOUCH").

## Dependencias vendorizadas (self-contained, local)

forge-std (symlink al twin), solmate, solady, openzeppelin-contracts,
openzeppelin-contracts-upgradeable, murky, Uniswap V2 (solo interfaces; impl
desde el bytecode de `builds/`), Gnosis Safe (safe-smart-account/contracts).

## Alcance y legalidad

Material **educativo**, ejecutado **100% en local** (sin red real, sin ninguna
dirección de mainnet ni de producción). Las claves usadas en `compromised` y la
llave del `user` en los retos tipo puppet son datos del propio reto (CTF), no
secretos reales. Damn Vulnerable DeFi es open-source y está diseñado para
explotarse localmente con fines de aprendizaje.
