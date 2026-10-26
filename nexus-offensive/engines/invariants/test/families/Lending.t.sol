// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingInvariants} from "../invariants/LendingInvariants.sol";
import {LendingHandler} from "../handlers/LendingHandler.sol";
import {ILending} from "../../src/interfaces/ILending.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ToyLending} from "../../src/lending/ToyLending.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Aplica el set de invariantes Lending al contrato SANO (ToyLending).
contract ToyLendingInvariantTest is LendingInvariants {
    function setUp() public {
        MockERC20 token = new MockERC20("USD", "USD");
        ToyLending toy = new ToyLending(IERC20(address(token)));

        lendingHandler = new LendingHandler(toy, token);
        lending = ILending(address(toy));

        targetContract(address(lendingHandler));
    }
}
