// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFlashLoanPool, IFlashBorrower} from "../interfaces/IFlashLoanPool.sol";

/// @title ToyFlashLoanPool — pool de flash loans de ETH, SANO
/// @notice Referencia de juguete. El flash loan está protegido contra reentrada,
///         así que no se puede "repagar" depositando dentro del callback (el
///         truco de side-entrance). El repago es una transferencia directa.
///         Educativo, no producción.
contract ToyFlashLoanPool is IFlashLoanPool {
    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;
    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    function depositOf(address u) external view returns (uint256) {
        return deposits[u];
    }

    function balanceHeld() external view returns (uint256) {
        return address(this).balance;
    }

    function deposit() external payable nonReentrant {
        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(deposits[msg.sender] >= amount, "insufficient");
        deposits[msg.sender] -= amount;
        totalDeposits -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "send");
    }

    /// @notice Flash loan protegido: deposit/withdraw quedan bloqueados durante
    ///         el callback, así que el repago debe ser una devolución real.
    function flashLoan(uint256 amount) external nonReentrant {
        uint256 balanceBefore = address(this).balance;
        require(amount <= balanceBefore, "too much");
        IFlashBorrower(msg.sender).onFlashLoan{value: amount}(amount);
        require(address(this).balance >= balanceBefore, "not repaid");
    }

    receive() external payable {} // repago directo
}
