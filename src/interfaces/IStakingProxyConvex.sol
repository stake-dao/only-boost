// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IStakingProxyConvex {
    function stakeLockedCurveLp(uint256 _liquidity, uint256 _secs) external returns (bytes32 kek_id);

    function lockAdditionalCurveLp(bytes32 _kek_id, uint256 _addl_liq) external;

    function withdrawLockedAndUnwrap(bytes32 _kek_id) external;

    function getReward(bool _claim) external;

    function stakingAddress() external view returns (address);
}
