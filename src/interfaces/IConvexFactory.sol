// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

interface IConvexFactory {
    function protocolFeePercent() external view returns (uint256);
}
