// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

contract PoolRegistryMock {
    struct PoolInfo {
        address implementation;
        address stakingAddress;
        address stakingToken;
        address rewardsAddress;
        uint8 active;
    }

    PoolInfo[] public poolInfo;

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(address stakingAddress, address stakingToken) external {
        poolInfo.push(PoolInfo(address(0), stakingAddress, stakingToken, address(0), 1));
    }
}
