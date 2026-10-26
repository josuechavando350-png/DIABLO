// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IOracleLending} from "../../src/interfaces/IOracleLending.sol";
import {OracleInvariantLib} from "../lib/OracleInvariantLib.sol";
import {OracleHandler} from "../handlers/OracleHandler.sol";

/// @notice SET DE INVARIANTES de la familia Oráculo / Precio. Genérico sobre IOracleLending.
abstract contract OracleInvariants is StdInvariant, Test {
    IOracleLending internal oracle;
    uint256 internal fairPriceRef;
    OracleHandler internal oracleHandler;

    /// O1 · El colateral exigido usa un precio resistente a manipulación.
    function invariant_oracle_fairCollateral() public view {
        assertTrue(
            OracleInvariantLib.fairCollateral(oracle, fairPriceRef),
            "O1: colateral por debajo del valor justo (oraculo manipulable)"
        );
    }
}
