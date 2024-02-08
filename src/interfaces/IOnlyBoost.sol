/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IOnlyBoost {
    function getOptimalDepositAllocation(address gauge, uint256 amount)
        external
        returns (address[] memory, uint256[] memory);

    function getRebalancedAllocation(address gauge, uint256 amount)
        external
        returns (address[] memory, uint256[] memory);

    function getOptimalWithdrawalPath(address gauge, uint256 amount)
        external
        view
        returns (address[] memory, uint256[] memory);

    function getFallbacks(address gauge) external view returns (address[] memory);
}
