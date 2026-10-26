// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IStaking} from "../../src/interfaces/IStaking.sol";
import {StakingInvariantLib} from "../lib/StakingInvariantLib.sol";
import {StakingHandler} from "../handlers/StakingHandler.sol";

/// @notice SET DE INVARIANTES de la familia Staking. Genérico sobre IStaking.
abstract contract StakingInvariants is StdInvariant, Test {
    IStaking internal staking;
    StakingHandler internal stakingHandler;

    /// S1 · Recompensas repartidas (reclamadas + pendientes) <= emitidas.
    function invariant_staking_rewardsWithinFunded() public view {
        assertTrue(
            StakingInvariantLib.rewardsWithinFunded(staking, stakingHandler.getActors()),
            "S1: se repartio mas de lo emitido"
        );
    }

    /// S2 · El bote de rewards cubre lo pendiente de todos.
    function invariant_staking_rewardSolvency() public view {
        assertTrue(
            StakingInvariantLib.rewardSolvency(staking, stakingHandler.getActors()),
            "S2: rewards insolvente"
        );
    }

    /// S3 · El contrato custodia al menos lo apostado.
    function invariant_staking_stakeAccounting() public view {
        assertTrue(StakingInvariantLib.stakeAccounting(staking), "S3: contabilidad de stake rota");
    }
}
