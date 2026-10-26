// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IFlashLoanPool} from "../../src/interfaces/IFlashLoanPool.sol";
import {FlashLoanInvariantLib} from "../lib/FlashLoanInvariantLib.sol";
import {FlashLoanHandler} from "../handlers/FlashLoanHandler.sol";

/// @notice SET DE INVARIANTES de la familia Flash Loan. Genérico sobre IFlashLoanPool.
abstract contract FlashLoanInvariants is StdInvariant, Test {
    IFlashLoanPool internal flPool;
    FlashLoanHandler internal flHandler;

    /// FL1 · Conservación: ningún flash loan dejó el balance por debajo del previo.
    function invariant_flashloan_conservation() public view {
        assertFalse(flHandler.brokeConservation(), "FL1: un flash loan no se repago");
    }

    /// FL4 · Solvencia bajo reentrada: balance custodiado >= depósitos totales.
    function invariant_flashloan_solvency() public view {
        assertTrue(FlashLoanInvariantLib.solvent(flPool), "FL4: pool insolvente");
    }

    /// Contabilidad de apoyo: totalDeposits == suma de depósitos por actor.
    function invariant_flashloan_accounting() public view {
        uint256 sum;
        uint256 n = flHandler.actorCount();
        for (uint256 i; i < n; i++) {
            sum += flPool.depositOf(flHandler.actors(i));
        }
        assertEq(flPool.totalDeposits(), sum, "contabilidad de depositos rota");
    }
}
