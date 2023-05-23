// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IAccumulator {
    function notifyAll() external;
    function depositToken(address token, uint256 amount) external;
}
