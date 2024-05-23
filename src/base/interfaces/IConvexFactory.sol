// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IConvexFactory {
    function create(uint256 pid) external returns (address);
    function protocolFeesPercent() external view returns (uint256);
    function fallbacks(address gauge) external view returns (address);
}
