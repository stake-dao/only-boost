// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IBoosterConvexFrax {
    function createVault(uint256 pid) external returns (address);
}
