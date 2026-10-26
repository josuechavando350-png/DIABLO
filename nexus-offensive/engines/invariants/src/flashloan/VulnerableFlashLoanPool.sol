// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFlashLoanPool, IFlashBorrower} from "../interfaces/IFlashLoanPool.sol";

/// @title VulnerableFlashLoanPool — pool con el bug de "side-entrance"
/// @notice Igual que ToyFlashLoanPool pero SIN protección de reentrada. El flash
///         loan solo verifica que el balance se restaure; el atacante lo
///         restaura DEPOSITÁNDOLO dentro del callback, lo que le acredita un
///         saldo retirable, y luego vacía el pool. Educativo, no producción.
/// @dev Clase de bug: repago confundido con solvencia (reentrada vía deposit).
///      Rompe la invariante de solvencia del pool.
contract VulnerableFlashLoanPool is IFlashLoanPool {
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

    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "insufficient");
        deposits[msg.sender] -= amount;
        totalDeposits -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "send");
    }

    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;
        IFlashBorrower(msg.sender).onFlashLoan{value: amount}(amount);
        // ❌ BUG: solo mira el balance; no distingue "repago" de "depósito".
        require(address(this).balance >= balanceBefore, "not repaid");
    }

    receive() external payable {}
}
