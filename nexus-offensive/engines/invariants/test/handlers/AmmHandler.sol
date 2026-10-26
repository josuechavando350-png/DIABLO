// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {ToyAmm} from "../../src/amm/ToyAmm.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Handler HONESTO para la familia AMM: liquidez proporcional y swaps
///         válidos. Lleva un "ghost" que marca si algún swap hizo decrecer k.
contract AmmHandler is CommonBase, StdCheats, StdUtils {
    ToyAmm public amm;
    MockERC20 public t0;
    MockERC20 public t1;
    address[] public actors;

    bool public brokeConstantProduct; // ghost A3

    constructor(ToyAmm _amm, MockERC20 _t0, MockERC20 _t1) {
        amm = _amm;
        t0 = _t0;
        t1 = _t1;
        for (uint256 i = 0; i < 3; i++) {
            address a = address(uint160(0x2000 + i));
            actors.push(a);
            t0.mint(a, 1_000_000 ether);
            t1.mint(a, 1_000_000 ether);
            vm.prank(a);
            t0.approve(address(amm), type(uint256).max);
            vm.prank(a);
            t1.approve(address(amm), type(uint256).max);
        }
        // Siembra inicial de liquidez (fija el precio 1:1).
        address seeder = actors[0];
        vm.prank(seeder);
        amm.addLiquidity(10_000 ether, 10_000 ether);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function addLiquidity(uint256 actorSeed, uint256 amount0) external {
        address actor = actors[actorSeed % actors.length];
        if (amm.reserve0() == 0) return;
        amount0 = bound(amount0, 1 ether, 50_000 ether);
        uint256 amount1 = (amount0 * amm.reserve1()) / amm.reserve0();
        if (amount1 == 0) return;
        if (t0.balanceOf(actor) < amount0 || t1.balanceOf(actor) < amount1) return;
        vm.prank(actor);
        amm.addLiquidity(amount0, amount1);
    }

    function removeLiquidity(uint256 actorSeed, uint256 shares) external {
        address actor = actors[actorSeed % actors.length];
        uint256 bal = amm.liquidityOf(actor);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        // No vaciar del todo el pool (deja piso de liquidez).
        if (shares >= amm.totalLiquidity()) return;
        vm.prank(actor);
        amm.removeLiquidity(shares);
    }

    function swap(uint256 actorSeed, uint256 amountIn, bool zeroForOne) external {
        address actor = actors[actorSeed % actors.length];
        if (amm.reserve0() == 0 || amm.reserve1() == 0) return;
        uint256 rIn = zeroForOne ? amm.reserve0() : amm.reserve1();
        amountIn = bound(amountIn, 1 ether, rIn); // trade razonable
        MockERC20 tin = zeroForOne ? t0 : t1;
        if (tin.balanceOf(actor) < amountIn) return;

        uint256 kBefore = amm.reserve0() * amm.reserve1();
        vm.prank(actor);
        try amm.swap(amountIn, zeroForOne) {
            uint256 kAfter = amm.reserve0() * amm.reserve1();
            if (kAfter < kBefore) {
                brokeConstantProduct = true; // ghost A3
            }
        } catch {
            // swap inválido (p.ej. out==rOut): se descarta
        }
    }
}
