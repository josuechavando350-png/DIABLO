// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {ToyStaking} from "../../src/staking/ToyStaking.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Handler HONESTO para Staking: stake/unstake/fund/claim válidos.
contract StakingHandler is CommonBase, StdCheats, StdUtils {
    ToyStaking public staking;
    MockERC20 public stk;
    MockERC20 public rwd;
    address[] public actors;

    constructor(ToyStaking _staking, MockERC20 _stk, MockERC20 _rwd) {
        staking = _staking;
        stk = _stk;
        rwd = _rwd;
        for (uint256 i = 0; i < 3; i++) {
            address a = address(uint160(0x5000 + i));
            actors.push(a);
            stk.mint(a, 1_000_000 ether);
            rwd.mint(a, 1_000_000 ether);
            vm.prank(a);
            stk.approve(address(staking), type(uint256).max);
            vm.prank(a);
            rwd.approve(address(staking), type(uint256).max);
        }
        // Un staker inicial para que fund() tenga a quién repartir.
        vm.prank(actors[0]);
        staking.stakeTokens(1_000 ether);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function stakeTokens(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        amount = bound(amount, 1 ether, 100_000 ether);
        if (stk.balanceOf(actor) < amount) return;
        vm.prank(actor);
        staking.stakeTokens(amount);
    }

    function unstake(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        uint256 bal = staking.stakedOf(actor);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(actor);
        staking.unstake(amount);
    }

    function fund(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        if (staking.totalStaked() == 0) return;
        amount = bound(amount, 1 ether, 10_000 ether);
        if (rwd.balanceOf(actor) < amount) return;
        vm.prank(actor);
        staking.fund(amount);
    }

    function claim(uint256 seed) external {
        address actor = actors[seed % actors.length];
        if (staking.earned(actor) == 0) return;
        vm.prank(actor);
        staking.claim();
    }
}
