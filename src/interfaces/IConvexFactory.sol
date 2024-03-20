// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IConvexFactory {
    function protocolFeesPercent() external view returns (uint256);
    function fallbacks(address gauge) external view returns (address);
    function create(address token, uint256 pid) external returns (address);
}
