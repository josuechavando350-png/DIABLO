// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Familia Vault ERC-4626 (subconjunto necesario para las invariantes).
interface IVault4626 {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address user) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}
