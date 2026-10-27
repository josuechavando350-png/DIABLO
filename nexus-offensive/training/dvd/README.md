# training/dvd — Damn Vulnerable DeFi (entrenamiento del motor)

Banco de pruebas que enfrenta el **motor de invariantes (Capa 2)** contra
contratos vulnerables **reales de nivel profesional**: 6 retos de
[Damn Vulnerable DeFi](https://damnvulnerabledefi.xyz) v4 (CTF open-source,
material educativo diseñado para explotarse en local).

Corre **100% local**, sin red real ni direcciones de producción.

> **Alcance:** solo estos 6 retos, en local. No es una capa nueva del sistema;
> es entrenamiento/validación del motor contra bugs reales, y un **reporte de
> huecos** (`COBERTURA.md`) de qué le falta al catálogo.

## Los 15 retos resueltos (cubren las familias del motor)

| Reto | Familia | Invariante | Catálogo |
|------|---------|-----------|----------|
| unstoppable | Vault 4626 | V4 `totalAssets == totalSupply` | 🟢 cubierto |
| naive-receiver | Flash loan / acceso | FL3 autorización de movimientos | 🟢 cubierto |
| side-entrance | Flash loan pool | FL4 solvencia `balance >= Σ depósitos` | 🟢 cubierto |
| the-rewarder | Staking / rewards | S1 reclamado ≤ asignación | 🟢 cubierto |
| truster | Flash loan / acceso | FL2 pool no otorga allowance arbitraria | 🟢 cubierto |
| puppet | Oráculo / Precio | O1 colateral con precio no manipulable | 🟢 cubierto |
| selfie | Flash loan / gobernanza | quórum no alcanzable con voto prestado | 🟢 cubierto |
| abi-smuggling | Control de acceso | FL3 selector ejecutado == permiso | 🟢 cubierto |
| compromised | Oráculo / Precio | O2 mediana robusta ante fuentes comprometidas | 🟢 cubierto |
| puppet-v2 | Oráculo / Precio | O1 precio resistente (Uniswap V2) | 🟢 cubierto |
| free-rider | Marketplace / fondos | comprar cuesta al comprador | 🟡 relacionado FL |
| shards | Marketplace / redondeo | reembolso ≤ pagado | 🟡 relacionado V3 |
| climber | Control de acceso / timelock | no ejecuta sin op agendada | 🟢 cubierto |
| withdrawal | Control de acceso / puente | retiro mueve sus fondos o ninguno | 🟢 cubierto |
| backdoor | Control de acceso / init | init no otorga permisos a terceros | 🟢 cubierto |

**15 de 18 retos resueltos.** Faltan: wallet-mining (diferido, el más
intrincado) y puppet-v3 / curvy-puppet (fuera de alcance, requieren fork de
mainnet). Los huecos que descubrió la primera tanda ya están **cerrados en el motor**
(familias Flash Loan y Oráculo + invariante V4). El análisis completo de
cobertura, el mapa reto→familia→invariante y el estado de los retos restantes
(2 fuera de alcance por requerir fork de mainnet, 7 diferidos) están en
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
