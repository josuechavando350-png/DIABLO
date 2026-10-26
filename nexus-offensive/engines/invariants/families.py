"""Registro declarativo de familias de la biblioteca de invariantes.

Esta es la pieza que hace la biblioteca EXTENSIBLE: agregar una familia nueva
= agregar su interfaz + su set de invariantes en Solidity, y una entrada aquí.
`InvariantRunner.py` itera sobre esta lista y NO se toca.

Cada familia declara:
  - name            : nombre legible
  - interface       : la interfaz Solidity que define la familia (src/interfaces)
  - invariant_suite : contrato de test que aplica el set al contrato SANO
  - invariants      : lista de invariantes (id, test, qué vigila)
  - exploits        : PoCs que rompen una invariante clave (test, invariante rota)
"""

FAMILIES = [
    {
        "name": "AMM",
        "interface": "IAmm",
        "invariant_suite": "ToyAmmInvariantTest",
        "invariants": [
            {"id": "A1", "test": "invariant_amm_reservesBacked",
             "desc": "Reservas respaldadas por balances reales (solvencia contable)."},
            {"id": "A2", "test": "invariant_amm_reservesNonZero",
             "desc": "Con liquidez activa, ninguna reserva puede quedar en cero."},
            {"id": "A3", "test": "invariant_amm_constantProduct",
             "desc": "El producto constante k=r0*r1 nunca decrece por un swap."},
        ],
        "exploits": [
            {"test": "test_PoC_amm_constant_product_broken", "breaks": "A3",
             "desc": "Fórmula de precio lineal (sin curva x·y=k) hace decrecer k."},
        ],
    },
    {
        "name": "Lending",
        "interface": "ILending",
        "invariant_suite": "ToyLendingInvariantTest",
        "invariants": [
            {"id": "L1", "test": "invariant_lending_globalSolvency",
             "desc": "Colateral total nunca menor que la deuda total."},
            {"id": "L2", "test": "invariant_lending_positionsHealthy",
             "desc": "Ninguna posición presta por encima de su colateral (sana)."},
            {"id": "L3", "test": "invariant_lending_cashAccounting",
             "desc": "Contabilidad de caja: cash == colateral - deuda."},
        ],
        "exploits": [
            {"test": "test_PoC_lending_overborrow_breaks_health", "breaks": "L2",
             "desc": "borrow ignora la deuda existente → se presta sobre-colateral."},
        ],
    },
    {
        "name": "Vault4626",
        "interface": "IVault4626",
        "invariant_suite": "ToyVaultInvariantTest",
        "invariants": [
            {"id": "V1", "test": "invariant_vault_accountingSolvent",
             "desc": "El vault custodia al menos lo que contabiliza."},
            {"id": "V2", "test": "invariant_vault_depositFairness",
             "desc": "Ningún depósito recibe shares injustas (anti-inflación)."},
            {"id": "V3", "test": "invariant_vault_redemptionsSolvent",
             "desc": "Suma de lo redimible por todos nunca excede los activos."},
            {"id": "V4", "test": "invariant_vault_strictAccounting",
             "desc": "Contabilidad estricta: activos == shares (sin donaciones no contabilizadas)."},
        ],
        "exploits": [
            {"test": "test_PoC_vault_inflation_steals_deposit", "breaks": "V2",
             "desc": "Inflación de primer depositante: la víctima recibe 0 shares."},
            {"test": "test_PoC_V4_donation_breaks_strict_accounting", "breaks": "V4",
             "desc": "Donación directa rompe activos==shares (estilo unstoppable)."},
        ],
    },
    {
        "name": "Staking",
        "interface": "IStaking",
        "invariant_suite": "ToyStakingInvariantTest",
        "invariants": [
            {"id": "S1", "test": "invariant_staking_rewardsWithinFunded",
             "desc": "Recompensas repartidas (reclamadas+pendientes) <= emitidas."},
            {"id": "S2", "test": "invariant_staking_rewardSolvency",
             "desc": "El bote de rewards cubre lo pendiente de todos."},
            {"id": "S3", "test": "invariant_staking_stakeAccounting",
             "desc": "El contrato custodia al menos lo apostado."},
        ],
        "exploits": [
            {"test": "test_PoC_staking_double_claim_exceeds_funded", "breaks": "S1",
             "desc": "claim no resetea la recompensa → doble claim excede lo emitido."},
        ],
    },
    {
        "name": "FlashLoan",
        "interface": "IFlashLoanPool",
        "invariant_suite": "ToyFlashLoanInvariantTest",
        "invariants": [
            {"id": "FL1", "test": "invariant_flashloan_conservation",
             "desc": "Conservación: tras un flash loan el balance no baja (se repagó)."},
            {"id": "FL4", "test": "invariant_flashloan_solvency",
             "desc": "Solvencia bajo reentrada: balance custodiado >= depósitos."},
        ],
        "exploits": [
            {"test": "test_PoC_FL1_unrepaid_breaks_conservation", "breaks": "FL1",
             "desc": "Flash loan sin verificación de repago drena el pool."},
            {"test": "test_PoC_FL2_arbitrary_call_breaks_no_allowance", "breaks": "FL2",
             "desc": "Llamada arbitraria: el pool se auto-aprueba al atacante (truster)."},
            {"test": "test_PoC_FL3_unauthorized_loans_drain_receiver", "breaks": "FL3",
             "desc": "Préstamos no autorizados vacían al receptor vía fees (naive-receiver)."},
            {"test": "test_PoC_FL4_side_entrance_breaks_solvency", "breaks": "FL4",
             "desc": "Repagar depositando acredita saldo y vacía el pool (side-entrance)."},
        ],
    },
    {
        "name": "Oracle",
        "interface": "IOracleLending",
        "invariant_suite": "ToyOracleInvariantTest",
        "invariants": [
            {"id": "O1", "test": "invariant_oracle_fairCollateral",
             "desc": "Colateral valuado con precio resistente a manipulación (TWAP, no spot)."},
        ],
        "exploits": [
            {"test": "test_PoC_oracle_spot_manipulation_breaks_collateral", "breaks": "O1",
             "desc": "Manipular el spot del AMM desploma el colateral exigido (puppet)."},
        ],
    },
]
