// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Familia Oráculo: préstamo cuyo colateral se valúa con un precio.
/// @dev Hueco descubierto entrenando contra Damn Vulnerable DeFi (puppet).
interface IOracleLending {
    /// @return El colateral (en wei) exigido para pedir prestado `amount` tokens.
    function calculateDepositRequired(uint256 amount) external view returns (uint256);
}
