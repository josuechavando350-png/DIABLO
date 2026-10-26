// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ToyAmmPair — par AMM de juguete usado como fuente de precio.
/// @notice Reservas ETH/token con producto constante. `spotPrice` es el precio
///         SPOT (manipulable en una sola tx vendiendo tokens). Educativo.
contract ToyAmmPair {
    uint256 public ethReserve;
    uint256 public tokenReserve;

    constructor(uint256 _ethReserve, uint256 _tokenReserve) {
        ethReserve = _ethReserve;
        tokenReserve = _tokenReserve;
    }

    /// @notice Precio spot del token en wei (ETH por token).
    function spotPrice() public view returns (uint256) {
        return (ethReserve * 1e18) / tokenReserve;
    }

    /// @notice Vender tokens al par hunde el precio del token (producto constante).
    function sellTokens(uint256 tokensIn) external returns (uint256 ethOut) {
        require(tokensIn > 0, "zero");
        uint256 newToken = tokenReserve + tokensIn;
        uint256 newEth = (ethReserve * tokenReserve) / newToken;
        ethOut = ethReserve - newEth;
        tokenReserve = newToken;
        ethReserve = newEth;
    }
}
