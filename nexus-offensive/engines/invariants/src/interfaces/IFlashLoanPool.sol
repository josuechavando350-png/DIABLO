// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Familia Flash Loan: pool de ETH con depósitos y préstamos flash.
/// @dev Hueco descubierto entrenando contra Damn Vulnerable DeFi (side-entrance).
interface IFlashLoanPool {
    function totalDeposits() external view returns (uint256);
    function depositOf(address user) external view returns (uint256);
    function balanceHeld() external view returns (uint256); // ETH realmente custodiado
}

/// @notice Receptor de un flash loan de ETH.
interface IFlashBorrower {
    function onFlashLoan(uint256 amount) external payable;
}
