// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface ICVXLocker {
    function totalSupply() external view returns (uint256);
    function lockedSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}