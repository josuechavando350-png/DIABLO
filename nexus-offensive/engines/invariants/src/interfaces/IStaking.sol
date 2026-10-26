// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Familia Staking / rewards (modelo de distribución por acumulador).
interface IStaking {
    function stakeToken() external view returns (address);
    function rewardToken() external view returns (address);
    function totalStaked() external view returns (uint256);
    function totalRewardsFunded() external view returns (uint256);  // emitido
    function totalRewardsClaimed() external view returns (uint256);  // repartido
    function stakedOf(address user) external view returns (uint256);
    function earned(address user) external view returns (uint256);   // pendiente
}
