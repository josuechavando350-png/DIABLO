// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {ILending} from "../../src/interfaces/ILending.sol";
import {LendingInvariantLib} from "../lib/LendingInvariantLib.sol";
import {LendingHandler} from "../handlers/LendingHandler.sol";

/// @notice SET DE INVARIANTES de la familia Lending. Genérico sobre ILending.
abstract contract LendingInvariants is StdInvariant, Test {
    ILending internal lending;
    LendingHandler internal lendingHandler;

    /// L1 · Solvencia global: colateral total >= deuda total.
    function invariant_lending_globalSolvency() public view {
        assertTrue(LendingInvariantLib.globalSolvency(lending), "L1: insolvencia global");
    }

    /// L2 · Ninguna posición presta por encima de su colateral (todas sanas).
    function invariant_lending_positionsHealthy() public view {
        uint256 n = lendingHandler.actorCount();
        for (uint256 i; i < n; i++) {
            assertTrue(lending.isHealthy(lendingHandler.actors(i)), "L2: posicion no sana");
        }
    }

    /// L3 · Contabilidad de caja: cash == colateral - deuda.
    function invariant_lending_cashAccounting() public view {
        assertTrue(LendingInvariantLib.cashAccounting(lending), "L3: contabilidad de caja rota");
    }
}
