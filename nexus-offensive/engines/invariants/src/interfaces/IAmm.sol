// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Familia AMM (producto constante, tipo Uniswap V2).
/// @dev El set de invariantes de la familia opera SOLO a través de esta
///      interfaz, así que aplica a cualquier contrato que la implemente.
interface IAmm {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function reserve0() external view returns (uint256);
    function reserve1() external view returns (uint256);
    function totalLiquidity() external view returns (uint256);
}
