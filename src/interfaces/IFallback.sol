/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

interface IFallback {
    function initialize() external;
    function claim(bool _claimExtraRewards)
        external
        returns (uint256 rewardTokenAmount, uint256 fallbackRewardTokenAmount, uint256 protocolFees);
    function balanceOf() external view returns (uint256);
    function deposit(address _asset, uint256 _amount) external;
    function withdraw(address _asset, uint256 _amount) external;
    function fallbackRewardToken() external view returns (address);
}
