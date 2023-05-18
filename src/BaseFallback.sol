// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

abstract contract BaseFallback {
    function deposit(uint256 amount) external virtual;
    function withdraw(uint256 amount) external virtual;
    function balanceOf(address lpToken) external virtual returns (uint256);
}
