// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Familia Lending / colateralización (tipo Aave, un solo activo).
interface ILending {
    function asset() external view returns (address);
    function ltvBps() external view returns (uint256);
    function totalCollateral() external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function collateralOf(address user) external view returns (uint256);
    function debtOf(address user) external view returns (uint256);
    /// @notice Salud "real" de la posición: deuda <= colateral * LTV.
    function isHealthy(address user) external view returns (bool);
}
