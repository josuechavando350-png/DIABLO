// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";
import {ILending} from "../interfaces/ILending.sol";

/// @title ToyLending — mercado monetario de un solo activo, SANO
/// @notice Referencia de juguete para la familia Lending. Colateral y activo
///         prestable son el mismo token (precio 1:1), LTV 75%. Educativo.
contract ToyLending is ILending {
    IERC20 public immutable token;
    uint256 public constant LTV_BPS = 7500; // 75%
    uint256 private constant BPS = 10_000;

    uint256 public totalCollateral;
    uint256 public totalDebt;
    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    constructor(IERC20 t) {
        token = t;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function ltvBps() external pure returns (uint256) {
        return LTV_BPS;
    }

    function maxBorrow(address u) public view returns (uint256) {
        return (collateralOf[u] * LTV_BPS) / BPS;
    }

    function isHealthy(address u) public view returns (bool) {
        return debtOf[u] <= maxBorrow(u);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "zero");
        require(token.transferFrom(msg.sender, address(this), amount), "pull");
        collateralOf[msg.sender] += amount;
        totalCollateral += amount;
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "zero");
        // Comprueba la deuda TOTAL contra el límite por colateral.
        require(debtOf[msg.sender] + amount <= maxBorrow(msg.sender), "undercollateralized");
        require(token.balanceOf(address(this)) >= amount, "no cash");
        debtOf[msg.sender] += amount;
        totalDebt += amount;
        require(token.transfer(msg.sender, amount), "send");
    }

    function repay(uint256 amount) external {
        uint256 d = debtOf[msg.sender];
        if (amount > d) amount = d;
        require(amount > 0, "nothing");
        require(token.transferFrom(msg.sender, address(this), amount), "pull");
        debtOf[msg.sender] -= amount;
        totalDebt -= amount;
    }

    function withdraw(uint256 amount) external {
        require(amount > 0 && collateralOf[msg.sender] >= amount, "bad");
        require(token.balanceOf(address(this)) >= amount, "no cash");
        collateralOf[msg.sender] -= amount;
        totalCollateral -= amount;
        require(debtOf[msg.sender] <= maxBorrow(msg.sender), "would be unhealthy");
        require(token.transfer(msg.sender, amount), "send");
    }
}
