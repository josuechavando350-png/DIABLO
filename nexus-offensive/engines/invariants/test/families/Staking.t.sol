// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StakingInvariants} from "../invariants/StakingInvariants.sol";
import {StakingHandler} from "../handlers/StakingHandler.sol";
import {IStaking} from "../../src/interfaces/IStaking.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ToyStaking} from "../../src/staking/ToyStaking.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Aplica el set de invariantes Staking al contrato SANO (ToyStaking).
contract ToyStakingInvariantTest is StakingInvariants {
    function setUp() public {
        MockERC20 stk = new MockERC20("Stake", "STK");
        MockERC20 rwd = new MockERC20("Reward", "RWD");
        ToyStaking toy = new ToyStaking(IERC20(address(stk)), IERC20(address(rwd)));

        stakingHandler = new StakingHandler(toy, stk, rwd);
        staking = IStaking(address(toy));

        targetContract(address(stakingHandler));
    }
}
