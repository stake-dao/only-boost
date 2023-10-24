// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IStrategy {
    function locker() external view returns (address);

    function deposit(address _token, uint256 amount) external;
    function withdraw(address _token, uint256 amount) external;

    function claimProtocolFees() external;
    function claimNativeRewards() external;
    function harvest(address _asset, bool _distributeSDT, bool _claimExtra) external;

    function rewardDistributors(address _gauge) external view returns (address);
}
