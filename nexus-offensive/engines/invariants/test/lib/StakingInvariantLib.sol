// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStaking} from "../../src/interfaces/IStaking.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/// @notice Predicados de invariante de la familia Staking / rewards.
library StakingInvariantLib {
    /// S1 · Las recompensas repartidas (reclamadas + pendientes) nunca exceden
    ///      las emitidas (fondeadas).
    function rewardsWithinFunded(IStaking s, address[] memory users) internal view returns (bool) {
        uint256 outstanding;
        for (uint256 i; i < users.length; i++) {
            outstanding += s.earned(users[i]);
        }
        return s.totalRewardsClaimed() + outstanding <= s.totalRewardsFunded();
    }

    /// S2 · Solvencia de rewards: el bote cubre lo pendiente de todos.
    function rewardSolvency(IStaking s, address[] memory users) internal view returns (bool) {
        uint256 outstanding;
        for (uint256 i; i < users.length; i++) {
            outstanding += s.earned(users[i]);
        }
        return IERC20(s.rewardToken()).balanceOf(address(s)) >= outstanding;
    }

    /// S3 · Contabilidad de stake: el contrato custodia al menos lo apostado.
    function stakeAccounting(IStaking s) internal view returns (bool) {
        return IERC20(s.stakeToken()).balanceOf(address(s)) >= s.totalStaked();
    }
}
