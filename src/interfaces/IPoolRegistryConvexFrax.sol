// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IPoolRegistryConvexFrax {
    function poolLength() external view returns (uint256);

    function vaultMap(uint256 pid, address user) external view returns (address);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address implementation,
            address stakingAddress,
            address stakingToken,
            address rewardsAddress,
            uint8 active
        );
}