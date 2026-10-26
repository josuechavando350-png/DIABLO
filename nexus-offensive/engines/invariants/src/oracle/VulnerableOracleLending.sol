// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracleLending} from "../interfaces/IOracleLending.sol";
import {ToyAmmPair} from "./ToyAmmPair.sol";

/// @title VulnerableOracleLending — valúa el colateral con el precio SPOT
/// @notice Lee `pair.spotPrice()` en cada cálculo. Un atacante hunde el spot
///         vendiendo tokens y pide prestado con colateral ridículo. Es el bug
///         de "puppet". Educativo, no producción.
/// @dev Clase de bug: oráculo de precio manipulable (spot de un AMM).
contract VulnerableOracleLending is IOracleLending {
    ToyAmmPair public pair;
    uint256 public constant FACTOR = 2;

    constructor(ToyAmmPair _pair) {
        pair = _pair;
    }

    function calculateDepositRequired(uint256 amount) external view returns (uint256) {
        return (amount * pair.spotPrice() * FACTOR) / 1e18; // ❌ precio spot manipulable
    }
}
