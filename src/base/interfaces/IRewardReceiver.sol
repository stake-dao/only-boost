/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IRewardReceiver {
    function notifyAll() external returns (uint256 rewardTokenAmount);
    function notifyRewardToken(address token) external;
    function approveRewardToken(address token) external;
}
