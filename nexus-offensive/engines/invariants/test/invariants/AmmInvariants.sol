// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IAmm} from "../../src/interfaces/IAmm.sol";
import {AmmInvariantLib} from "../lib/AmmInvariantLib.sol";
import {AmmHandler} from "../handlers/AmmHandler.sol";

/// @notice SET DE INVARIANTES de la familia AMM.
/// @dev Abstracto y genérico sobre IAmm: cualquier test que fije `amm` y
///      `ammHandler` y registre el handler como targetContract hereda estas
///      invariantes. Agregar una familia NO toca este patrón.
abstract contract AmmInvariants is StdInvariant, Test {
    IAmm internal amm;
    AmmHandler internal ammHandler;

    /// A1 · Reservas respaldadas por balances reales (solvencia contable).
    function invariant_amm_reservesBacked() public view {
        assertTrue(
            AmmInvariantLib.reservesBackedByBalances(amm),
            "A1: reservas no respaldadas por balances"
        );
    }

    /// A2 · Con liquidez activa, ninguna reserva en cero.
    function invariant_amm_reservesNonZero() public view {
        assertTrue(
            AmmInvariantLib.reservesNonZeroWhenActive(amm),
            "A2: una reserva quedo en cero"
        );
    }

    /// A3 · El producto constante k nunca decrece por un swap.
    function invariant_amm_constantProduct() public view {
        assertFalse(
            ammHandler.brokeConstantProduct(),
            "A3: k decrecio en un swap (producto constante roto)"
        );
    }
}
