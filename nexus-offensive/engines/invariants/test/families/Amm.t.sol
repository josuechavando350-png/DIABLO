// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AmmInvariants} from "../invariants/AmmInvariants.sol";
import {AmmHandler} from "../handlers/AmmHandler.sol";
import {IAmm} from "../../src/interfaces/IAmm.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ToyAmm} from "../../src/amm/ToyAmm.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Aplica el set de invariantes AMM al contrato SANO (ToyAmm).
///         Bajo fuzzing honesto, las 3 invariantes deben sostenerse.
contract ToyAmmInvariantTest is AmmInvariants {
    function setUp() public {
        MockERC20 t0 = new MockERC20("Token0", "T0");
        MockERC20 t1 = new MockERC20("Token1", "T1");
        ToyAmm toy = new ToyAmm(IERC20(address(t0)), IERC20(address(t1)));

        ammHandler = new AmmHandler(toy, t0, t1);
        amm = IAmm(address(toy));

        targetContract(address(ammHandler));
    }
}
