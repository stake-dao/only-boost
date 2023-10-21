// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IVault {
    function setCurveStrategy(address _newStrat) external;
    function deposit(address _staker, uint256 _amount, bool _earn) external;
    function available() external view returns (uint256);
}
