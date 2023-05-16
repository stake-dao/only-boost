// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IBaseRewardsPool {
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
}
