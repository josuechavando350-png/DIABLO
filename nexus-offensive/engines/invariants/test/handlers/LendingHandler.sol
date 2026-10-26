// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {ToyLending} from "../../src/lending/ToyLending.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Handler HONESTO para Lending: depósitos, préstamos dentro del
///         límite, repagos y retiros que mantienen la posición sana.
contract LendingHandler is CommonBase, StdCheats, StdUtils {
    ToyLending public lending;
    MockERC20 public token;
    address[] public actors;

    uint256 private constant BPS = 10_000;

    constructor(ToyLending _lending, MockERC20 _token) {
        lending = _lending;
        token = _token;
        for (uint256 i = 0; i < 3; i++) {
            address a = address(uint160(0x3000 + i));
            actors.push(a);
            token.mint(a, 1_000_000 ether);
            vm.prank(a);
            token.approve(address(lending), type(uint256).max);
        }
        // Siembra de caja: el actor 0 deposita para que haya qué prestar.
        vm.prank(actors[0]);
        lending.deposit(100_000 ether);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function deposit(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        amount = bound(amount, 1 ether, 50_000 ether);
        if (token.balanceOf(actor) < amount) return;
        vm.prank(actor);
        lending.deposit(amount);
    }

    function borrow(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        uint256 limit = (lending.collateralOf(actor) * lending.LTV_BPS()) / BPS;
        uint256 debt = lending.debtOf(actor);
        if (debt >= limit) return;
        uint256 allowed = limit - debt;
        uint256 cash = token.balanceOf(address(lending));
        uint256 cap = allowed < cash ? allowed : cash;
        if (cap == 0) return;
        amount = bound(amount, 1, cap);
        vm.prank(actor);
        lending.borrow(amount);
    }

    function repay(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        uint256 debt = lending.debtOf(actor);
        if (debt == 0) return;
        amount = bound(amount, 1, debt);
        vm.prank(actor);
        lending.repay(amount);
    }

    function withdraw(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        uint256 collat = lending.collateralOf(actor);
        uint256 debt = lending.debtOf(actor);
        // Colateral mínimo para seguir sano: ceil(debt * BPS / LTV).
        uint256 minCollat = debt == 0 ? 0 : (debt * BPS + lending.LTV_BPS() - 1) / lending.LTV_BPS();
        if (collat <= minCollat) return;
        uint256 freeCollat = collat - minCollat;
        uint256 cash = token.balanceOf(address(lending));
        uint256 cap = freeCollat < cash ? freeCollat : cash;
        if (cap == 0) return;
        amount = bound(amount, 1, cap);
        vm.prank(actor);
        lending.withdraw(amount);
    }
}
