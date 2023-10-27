// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IConvexToken {
    function maxSupply() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalCliffs() external view returns (uint256);
    function reductionPerCliff() external view returns (uint256);
}
