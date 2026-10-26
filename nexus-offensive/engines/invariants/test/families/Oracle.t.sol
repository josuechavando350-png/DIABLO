// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OracleInvariants} from "../invariants/OracleInvariants.sol";
import {OracleHandler} from "../handlers/OracleHandler.sol";
import {IOracleLending} from "../../src/interfaces/IOracleLending.sol";
import {ToyAmmPair} from "../../src/oracle/ToyAmmPair.sol";
import {ToyOracleLending} from "../../src/oracle/ToyOracleLending.sol";

/// @notice Aplica el set de invariantes Oráculo al contrato SANO (snapshot/TWAP).
///         El handler manipula el par; O1 se sostiene igual.
contract ToyOracleInvariantTest is OracleInvariants {
    function setUp() public {
        ToyAmmPair pair = new ToyAmmPair(10 ether, 10 ether); // precio 1:1
        fairPriceRef = pair.spotPrice();
        ToyOracleLending toy = new ToyOracleLending(pair);
        oracleHandler = new OracleHandler(pair);
        oracle = IOracleLending(address(toy));
        targetContract(address(oracleHandler));
    }
}
