// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILending} from "../../src/interfaces/ILending.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/// @notice Predicados de invariante de la familia Lending.
library LendingInvariantLib {
    /// L1 · Solvencia global: el colateral total nunca es menor que la deuda total.
    function globalSolvency(ILending l) internal view returns (bool) {
        return l.totalCollateral() >= l.totalDebt();
    }

    /// L3 · Contabilidad de caja: cash == colateral - deuda.
    function cashAccounting(ILending l) internal view returns (bool) {
        uint256 c = l.totalCollateral();
        uint256 d = l.totalDebt();
        if (d > c) return false;
        return IERC20(l.asset()).balanceOf(address(l)) == c - d;
    }
    // L2 (salud por posición) se verifica por actor con l.isHealthy(user).
}
