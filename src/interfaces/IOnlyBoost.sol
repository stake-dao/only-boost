/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

interface IOnlyBoost {
    function getOptimalDepositAllocation(address gauge, uint256 amount)
        external
        returns (address[] memory, uint256[] memory);

    function getOptimalWithdrawalPath(address gauge, uint256 amount)
        external
        view
        returns (address[] memory, uint256[] memory);

    function getFallback(address gauge) external view returns (address);
}
