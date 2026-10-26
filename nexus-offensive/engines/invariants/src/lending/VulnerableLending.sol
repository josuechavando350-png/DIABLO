// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";
import {ILending} from "../interfaces/ILending.sol";

/// @title VulnerableLending — igual que ToyLending pero con un BUG en `borrow`
/// @notice `borrow` compara SOLO el monto nuevo contra el límite, ignorando la
///         deuda existente. Permite pedir prestado por encima del colateral en
///         varios pasos. Educativo, no producción.
/// @dev Clase de bug: chequeo de salud incompleto (omite la deuda acumulada).
///      Rompe la invariante "ninguna posición presta por encima del colateral".
contract VulnerableLending is ILending {
    IERC20 public immutable token;
    uint256 public constant LTV_BPS = 7500;
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
        // ❌ BUG: ignora debtOf[msg.sender]. Cada préstamo se mide aislado.
        require(amount <= maxBorrow(msg.sender), "undercollateralized");
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
