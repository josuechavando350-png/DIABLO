// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {ToyVault4626} from "../../src/vault/ToyVault4626.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {IVault4626} from "../../src/interfaces/IVault4626.sol";
import {VaultInvariantLib} from "../lib/VaultInvariantLib.sol";

/// @notice Handler HONESTO para Vault: depósitos y redenciones válidas. Ghost
///         `brokeFairness` marca si algún depósito recibió shares injustas.
contract VaultHandler is CommonBase, StdCheats, StdUtils {
    ToyVault4626 public vault;
    MockERC20 public token;
    address[] public actors;

    bool public brokeFairness; // ghost V2

    constructor(ToyVault4626 _vault, MockERC20 _token) {
        vault = _vault;
        token = _token;
        for (uint256 i = 0; i < 3; i++) {
            address a = address(uint160(0x4000 + i));
            actors.push(a);
            token.mint(a, 1_000_000 ether);
            vm.prank(a);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function deposit(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        amount = bound(amount, 1 ether, 100_000 ether);
        if (token.balanceOf(actor) < amount) return;

        uint256 before = vault.balanceOf(actor);
        vm.prank(actor);
        vault.deposit(amount);
        uint256 got = vault.balanceOf(actor) - before;

        if (!VaultInvariantLib.depositWasFair(IVault4626(address(vault)), amount, got)) {
            brokeFairness = true; // ghost V2
        }
    }

    function redeem(uint256 seed, uint256 shares) external {
        address actor = actors[seed % actors.length];
        uint256 bal = vault.balanceOf(actor);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(actor);
        vault.redeem(shares);
    }
}
