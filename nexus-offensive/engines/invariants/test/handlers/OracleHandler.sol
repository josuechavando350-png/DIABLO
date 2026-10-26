// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {ToyAmmPair} from "../../src/oracle/ToyAmmPair.sol";

/// @notice Handler para Oráculo: intenta MANIPULAR el precio spot del par
///         vendiendo tokens. Contra un oráculo resistente (snapshot/TWAP), O1
///         debe sostenerse pese a la manipulación.
contract OracleHandler is CommonBase, StdCheats, StdUtils {
    ToyAmmPair public pair;

    constructor(ToyAmmPair _pair) {
        pair = _pair;
    }

    function manipulate(uint256 seed) external {
        uint256 reserve = pair.tokenReserve();
        if (reserve == 0) return;
        uint256 amount = bound(seed, 1, reserve * 100);
        pair.sellTokens(amount);
    }
}
