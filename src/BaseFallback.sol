// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

abstract contract BaseFallback {
    function deposit(uint256 amount) external virtual;
}
