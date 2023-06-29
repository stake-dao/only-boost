// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface IFraxFarmERC20 {
    function getAllRewardTokens() external view returns (address[] memory);
}
