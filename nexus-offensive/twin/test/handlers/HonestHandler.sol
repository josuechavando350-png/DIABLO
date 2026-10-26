// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {VulnerableVault} from "../../src/VulnerableVault.sol";

/// @notice Actores HONESTOS para el fuzzing de invariante.
/// @dev Solo depositan y retiran de forma válida. Bajo uso honesto la bóveda
///      se mantiene solvente (activos == suma de saldos), así que el
///      invariante DEBE sostenerse. El PoC (en Exploit.t.sol) es quien lo
///      rompe — ese es justo el punto del corte vertical.
contract HonestHandler is CommonBase, StdCheats, StdUtils {
    VulnerableVault public vault;
    address[] public actors;

    constructor(VulnerableVault _vault) {
        vault = _vault;
        for (uint256 i = 0; i < 3; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 0, actor.balance);
        vm.prank(actor);
        vault.deposit{value: amount}();
    }

    function withdraw(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        if (vault.balances(actor) == 0) {
            return;
        }
        vm.prank(actor);
        vault.withdraw();
    }
}
