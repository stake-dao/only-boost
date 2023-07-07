// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface IBoosterConvexCurve {
    function poolLength() external view returns (uint256);

    function poolInfo(uint256 pid)
        external
        view
        returns (address lpToken, address token, address gauge, address crvRewards, address stash, bool shutdown);

    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function claimRewards(uint256 _pid, address gauge) external returns (bool);
}
