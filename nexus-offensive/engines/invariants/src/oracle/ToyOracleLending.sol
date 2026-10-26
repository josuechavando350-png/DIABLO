// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracleLending} from "../interfaces/IOracleLending.sol";
import {ToyAmmPair} from "./ToyAmmPair.sol";

/// @title ToyOracleLending — valuación de colateral RESISTENTE a manipulación
/// @notice Toma una FOTO del precio al desplegar (proxy de un TWAP/oráculo
///         externo) y no la vuelve a leer del spot. Manipular el AMM dentro de
///         una tx no cambia el colateral exigido. Educativo, no producción.
contract ToyOracleLending is IOracleLending {
    uint256 public immutable fairPrice; // snapshot, no manipulable intra-tx
    uint256 public constant FACTOR = 2;

    constructor(ToyAmmPair pair) {
        fairPrice = pair.spotPrice();
    }

    function calculateDepositRequired(uint256 amount) external view returns (uint256) {
        return (amount * fairPrice * FACTOR) / 1e18;
    }
}
