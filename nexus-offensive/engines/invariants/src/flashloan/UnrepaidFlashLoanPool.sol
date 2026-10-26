// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFlashLoanPool, IFlashBorrower} from "../interfaces/IFlashLoanPool.sol";

/// @title UnrepaidFlashLoanPool — flash loan SIN verificación de repago
/// @notice El pool presta y nunca comprueba que le devuelvan los fondos.
///         Rompe FL1 (conservación): tras el préstamo el balance baja.
///         Educativo, no producción.
/// @dev Clase de bug: falta la comprobación de repago del flash loan.
contract UnrepaidFlashLoanPool is IFlashLoanPool {
    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;

    function depositOf(address u) external view returns (uint256) {
        return deposits[u];
    }

    function balanceHeld() external view returns (uint256) {
        return address(this).balance;
    }

    function deposit() external payable {
        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;
    }

    function flashLoan(uint256 amount) external {
        // ❌ BUG: presta y NO verifica que devuelvan nada.
        IFlashBorrower(msg.sender).onFlashLoan{value: amount}(amount);
    }

    receive() external payable {}
}
