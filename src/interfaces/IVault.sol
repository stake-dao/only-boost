// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IVault {
    function deposit(address _recipient, uint256 _amount, bool _earn) external;
    function withdraw(uint256 _shares) external;
    function initialize() external;

    function token() external view returns (address);
    function liquidityGauge() external view returns (address);
}
