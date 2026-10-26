// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAmm} from "../../src/interfaces/IAmm.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/// @notice Predicados de invariante de la familia AMM.
/// @dev Funciones puras/vista sobre IAmm, reutilizadas por el harness de
///      fuzzing (AmmInvariants) y por los PoC. "La biblioteca" de la familia.
library AmmInvariantLib {
    /// A1 · Las reservas contables están respaldadas por balances reales.
    ///      (balance >= reserva: nunca insolvente respecto a lo que dice tener)
    function reservesBackedByBalances(IAmm amm) internal view returns (bool) {
        return IERC20(amm.token0()).balanceOf(address(amm)) >= amm.reserve0()
            && IERC20(amm.token1()).balanceOf(address(amm)) >= amm.reserve1();
    }

    /// A2 · Con liquidez activa, ninguna reserva puede quedar en cero.
    function reservesNonZeroWhenActive(IAmm amm) internal view returns (bool) {
        if (amm.totalLiquidity() == 0) return true;
        return amm.reserve0() > 0 && amm.reserve1() > 0;
    }

    /// Producto constante k = r0 * r1 (para A3, comparado antes/después).
    function k(IAmm amm) internal view returns (uint256) {
        return amm.reserve0() * amm.reserve1();
    }
}
