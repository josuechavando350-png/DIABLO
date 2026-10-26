// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";
import {IStaking} from "../interfaces/IStaking.sol";

/// @title ToyStaking — staking con rewards por acumulador, SANO
/// @notice `fund` reparte recompensas entre los stakers actuales subiendo
///         `rewardPerTokenStored`. `claim` paga lo ganado y lo pone a cero.
///         Nunca se reparte más de lo fondeado. Educativo, no producción.
contract ToyStaking is IStaking {
    IERC20 public immutable stk;
    IERC20 public immutable rwd;
    uint256 private constant ACC = 1e18;

    uint256 public totalStaked;
    uint256 public totalRewardsFunded;
    uint256 public totalRewardsClaimed;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public stakedOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    constructor(IERC20 _stk, IERC20 _rwd) {
        stk = _stk;
        rwd = _rwd;
    }

    function stakeToken() external view returns (address) {
        return address(stk);
    }

    function rewardToken() external view returns (address) {
        return address(rwd);
    }

    function earned(address u) public view returns (uint256) {
        return rewards[u] + (stakedOf[u] * (rewardPerTokenStored - userRewardPerTokenPaid[u])) / ACC;
    }

    function _update(address u) internal {
        rewards[u] = earned(u);
        userRewardPerTokenPaid[u] = rewardPerTokenStored;
    }

    function stakeTokens(uint256 amount) external {
        require(amount > 0, "zero");
        _update(msg.sender);
        require(stk.transferFrom(msg.sender, address(this), amount), "pull");
        stakedOf[msg.sender] += amount;
        totalStaked += amount;
    }

    function unstake(uint256 amount) external {
        require(amount > 0 && stakedOf[msg.sender] >= amount, "bad");
        _update(msg.sender);
        stakedOf[msg.sender] -= amount;
        totalStaked -= amount;
        require(stk.transfer(msg.sender, amount), "send");
    }

    function fund(uint256 amount) external {
        require(totalStaked > 0, "no stakers");
        require(amount > 0, "zero");
        require(rwd.transferFrom(msg.sender, address(this), amount), "pull");
        rewardPerTokenStored += (amount * ACC) / totalStaked;
        totalRewardsFunded += amount;
    }

    function claim() external {
        _update(msg.sender);
        uint256 r = rewards[msg.sender];
        require(r > 0, "nothing");
        rewards[msg.sender] = 0; // resetea: no se puede reclamar dos veces
        totalRewardsClaimed += r;
        require(rwd.transfer(msg.sender, r), "send");
    }
}
