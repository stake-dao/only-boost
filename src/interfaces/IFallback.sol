/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

interface IFallback {
    function initialize() external;
    function claim(address _asset) external;
    function deposit(address _asset, uint256 _amount) external;
    function withdraw(address _asset, uint256 _amount) external;
}
