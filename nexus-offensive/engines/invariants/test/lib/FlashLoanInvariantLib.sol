// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFlashLoanPool} from "../../src/interfaces/IFlashLoanPool.sol";

/// @notice Predicados de invariante de la familia Flash Loan.
library FlashLoanInvariantLib {
    /// FL1 · Solvencia: el pool custodia al menos lo que debe a los depositantes.
    function solvent(IFlashLoanPool p) internal view returns (bool) {
        return p.balanceHeld() >= p.totalDeposits();
    }
    // FL2 (contabilidad: totalDeposits == Σ depositOf) y FL3 (conservación del
    // flash loan, ghost) se verifican en el set abstracto / el handler.
}
