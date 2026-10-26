# engines/invariants — Capa 2: motor de invariantes + biblioteca por familia

El **foso del proyecto**. Una biblioteca viva de invariantes DeFi (las
propiedades que SIEMPRE deben cumplirse) organizada por familia de protocolo,
con un motor genérico que las aplica por fuzzing de estado, contratos de
referencia sanos que las sostienen, y versiones vulnerables + PoCs que las
rompen para probar que el motor las detecta.

Todo es material **educativo de juguete**, no producción.

> **Alcance:** solo la Capa 2 (motor + biblioteca). No incluye observador,
> reporte, copiloto ni otras capas.

---

## El catálogo de invariantes (biblioteca viva)

4 familias · 12 invariantes · 5 PoCs. Todas verdes (`forge test`).

### 🟣 AMM — producto constante (tipo Uniswap V2) · interfaz `IAmm`

| ID | Invariante | Qué vigila y por qué | Clase de bug que la rompe | PoC |
|----|------------|----------------------|---------------------------|-----|
| **A1** | `balance(t0) ≥ reserve0` y `balance(t1) ≥ reserve1` | Las reservas contables están respaldadas por tokens reales: el pool nunca promete más de lo que tiene. | Fugas de fondos, swaps que pagan de más sin descontar de reservas. | — |
| **A2** | con `totalLiquidity>0`: `reserve0>0 ∧ reserve1>0` | Ninguna reserva puede vaciarse a cero: un lado en cero deja el precio indefinido y el pool inutilizable/drenable. | Fórmula de salida que permite drenar una reserva completa. | — |
| **A3** | `k = r0·r1` nunca decrece por un swap (con fee, crece) | Es la curva x·y=k: si k baja en un swap, alguien extrajo valor del pool (arbitraje tóxico). | **Fórmula de precio incorrecta** (lineal/sin curva, fee omitido). | ✅ `test_PoC_amm_constant_product_broken` |

### 🟢 Lending / colateralización (tipo Aave) · interfaz `ILending`

| ID | Invariante | Qué vigila y por qué | Clase de bug que la rompe | PoC |
|----|------------|----------------------|---------------------------|-----|
| **L1** | `totalCollateral ≥ totalDebt` | Solvencia global: el sistema siempre puede cubrir la deuda agregada (LTV<100%). | Mala deuda masiva, contabilidad de deuda inflada. | — |
| **L2** | ∀ usuario: `debt ≤ collateral·LTV` (todas sanas) | **Ninguna posición presta por encima de su colateral.** Es la regla central: una posición insana es pérdida latente. | **Chequeo de salud incompleto**: `borrow` que ignora la deuda acumulada. | ✅ `test_PoC_lending_overborrow_breaks_health` |
| **L3** | `cash == totalCollateral − totalDebt` | Contabilidad de caja consistente con depósitos y préstamos. | Retiros/préstamos que no actualizan la contabilidad. | — |

### 🔵 Vault ERC-4626 · interfaz `IVault4626`

| ID | Invariante | Qué vigila y por qué | Clase de bug que la rompe | PoC |
|----|------------|----------------------|---------------------------|-----|
| **V1** | `balance(asset) ≥ totalAssets()` | El vault custodia al menos lo que contabiliza (solvencia base). | Minteo de shares sin recibir activos; pérdida de activos. | — |
| **V2** | depósito de `x` → shares redimibles por `≈ x` | **Justicia al depositante / anti-inflación.** Si un depósito recibe ~0 shares, el depositante pierde sus fondos. | **Inflación de primer depositante** (sin virtual/dead shares; `totalAssets` cuenta donaciones; redondeo que perjudica al usuario). | ✅ `test_PoC_vault_inflation_steals_deposit` (+ `test_toyVault_resists_inflation`) |
| **V3** | `Σ convertToAssets(shares_u) ≤ totalAssets` | Todas las redenciones son pagables: el redondeo favorece al vault, nunca crea valor de la nada. | **Redondeo direccional incorrecto** (a favor del usuario). | — |

### 🟠 Staking / rewards · interfaz `IStaking`

| ID | Invariante | Qué vigila y por qué | Clase de bug que la rompe | PoC |
|----|------------|----------------------|---------------------------|-----|
| **S1** | `claimed + Σ earned(u) ≤ funded` | **Las recompensas repartidas nunca exceden las emitidas.** Es la regla central de un staking: no se puede pagar más de lo fondeado. | **Recompensa no reiniciada** tras el pago (doble claim), tasas sin fondeo. | ✅ `test_PoC_staking_double_claim_exceeds_funded` |
| **S2** | `balance(reward) ≥ Σ earned(u)` | El bote de rewards cubre lo pendiente de todos (solvencia de recompensas). | Drenaje del bote por doble claim; contabilidad de rewards rota. | — |
| **S3** | `balance(stake) ≥ totalStaked` | El contrato custodia al menos lo apostado (no se puede perder el principal de los stakers). | Contabilidad de stake desincronizada del balance. | — |

---

## Estructura

```
engines/invariants/
├── README.md                 # este catálogo (biblioteca viva)
├── families.py               # registro declarativo de familias (extensión)
├── InvariantRunner.py        # harness genérico + gancho de la jaula
├── foundry.toml / remappings.txt
├── lib/forge-std -> ../../twin/lib/forge-std   # reusa el del twin (symlink)
├── src/
│   ├── interfaces/           # IERC20, IAmm, ILending, IVault4626, IStaking
│   ├── mocks/MockERC20.sol · lib/Math.sol
│   ├── amm/      ToyAmm.sol       · VulnerableAmm.sol
│   ├── lending/  ToyLending.sol   · VulnerableLending.sol
│   ├── vault/    ToyVault4626.sol · VulnerableVault4626.sol
│   └── staking/  ToyStaking.sol   · VulnerableStaking.sol
└── test/
    ├── lib/          <Familia>InvariantLib.sol   # predicados reutilizables
    ├── invariants/   <Familia>Invariants.sol     # SET abstracto, genérico sobre la interfaz
    ├── handlers/     <Familia>Handler.sol        # actores honestos para el fuzzer
    ├── families/     <Familia>.t.sol             # aplica el set al contrato SANO
    └── exploits/     <Familia>Exploit.t.sol      # PoCs que rompen la invariante clave
```

## Cómo correrlo

```bash
cd engines/invariants
forge test -vv                     # todo (12 invariantes + 5 PoCs)
python3 InvariantRunner.py         # reporte por familia (sostenidas / detectadas)
python3 InvariantRunner.py --family AMM
```

(En este entorno se usa `--use ~/.foundry/solc/solc-0.8.24`; el runner lo
autodetecta. Ver nota de instalación en `../../twin/README.md`.)

## El harness genérico y cómo extenderlo

El **set de invariantes de cada familia es abstracto y genérico sobre la
interfaz** de la familia. Por ejemplo `AmmInvariants` solo habla `IAmm`:

```solidity
abstract contract AmmInvariants is StdInvariant, Test {
    IAmm internal amm;              // CUALQUIER contrato que implemente IAmm
    AmmHandler internal ammHandler;
    function invariant_amm_constantProduct() public view { ... }
    // ...
}
```

Aplicarlo a cualquier contrato de esa familia son ~6 líneas (fijar `amm` y el
handler, registrar el handler como `targetContract`): ver `test/families/*.t.sol`.

**Agregar una familia nueva** (sin tocar `InvariantRunner.py`):

1. `src/interfaces/IXxx.sol` — la interfaz de la familia.
2. `src/xxx/ToyXxx.sol` (+ `VulnerableXxx.sol`) — referencia y versión con bug.
3. `test/lib/XxxInvariantLib.sol` — predicados de invariante.
4. `test/invariants/XxxInvariants.sol` — el SET abstracto sobre `IXxx`.
5. `test/handlers/XxxHandler.sol` — actores honestos.
6. `test/families/Xxx.t.sol` + `test/exploits/XxxExploit.t.sol`.
7. Una entrada en `families.py`.

El runner itera `families.FAMILIES` y la recoge automáticamente.

## Integración con la jaula (regla invariable)

Para aplicar el motor a una **dirección real** hay que forkear mainnet; eso
**no se hace** sin pasar antes por `ScopeGuard.assert_allowed(address)` (mismo
gancho del `twin/`), en `InvariantRunner.assert_in_scope_before_fork()`:

```bash
python3 InvariantRunner.py --demo-gate app.example.com              # ALLOW
python3 InvariantRunner.py --demo-gate admin.example.com            # DENY (out_scope)
python3 InvariantRunner.py --target 0xC0ntract --fork-url https://RPC \
    --scope ../../config/scope.<programa>.yaml   # jaula → fork → invariantes
```

El set de juguete corre **100% local** (sin red real), así que el gancho no
llega a aplicarse — pero está puesto y documentado.
