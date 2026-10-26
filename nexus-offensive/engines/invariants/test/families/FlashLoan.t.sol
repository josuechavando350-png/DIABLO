// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FlashLoanInvariants} from "../invariants/FlashLoanInvariants.sol";
import {FlashLoanHandler} from "../handlers/FlashLoanHandler.sol";
import {IFlashLoanPool} from "../../src/interfaces/IFlashLoanPool.sol";
import {ToyFlashLoanPool} from "../../src/flashloan/ToyFlashLoanPool.sol";

/// @notice Aplica el set de invariantes Flash Loan al contrato SANO.
contract ToyFlashLoanInvariantTest is FlashLoanInvariants {
    function setUp() public {
        ToyFlashLoanPool toy = new ToyFlashLoanPool();
        flHandler = new FlashLoanHandler(toy);
        flPool = IFlashLoanPool(address(toy));

        // Fuzzear solo las entradas honestas (no el callback onFlashLoan/receive).
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = FlashLoanHandler.deposit.selector;
        selectors[1] = FlashLoanHandler.withdraw.selector;
        selectors[2] = FlashLoanHandler.flashLoanHonest.selector;
        targetSelector(FuzzSelector({addr: address(flHandler), selectors: selectors}));
        targetContract(address(flHandler));
    }
}
