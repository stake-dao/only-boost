// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface ILocker {
    function execute(address, uint256, bytes calldata) external returns (bool, bytes memory);
}
