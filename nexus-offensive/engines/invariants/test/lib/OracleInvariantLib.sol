// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracleLending} from "../../src/interfaces/IOracleLending.sol";

/// @notice Predicados de invariante de la familia Oráculo / Precio.
library OracleInvariantLib {
    /// O1 · Precio resistente a manipulación: el colateral exigido para pedir
    ///      prestado nunca cae por debajo del valor justo (2x el precio justo).
    ///      Un oráculo basado en spot de AMM rompe esto; uno tipo TWAP/snapshot
    ///      lo sostiene aunque se manipule el AMM dentro de la misma tx.
    function fairCollateral(IOracleLending l, uint256 fairPrice) internal view returns (bool) {
        uint256 required = l.calculateDepositRequired(1e18);
        uint256 fair = (1e18 * fairPrice * 2) / 1e18;
        return required >= fair;
    }
}
