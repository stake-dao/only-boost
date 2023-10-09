// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

/// TODO: For testing, remove for production
//import "forge-std/Test.sol";

import "src/v2/Strategy.sol";

import {IFallback} from "src/interfaces/IFallback.sol";
import {IOnlyBoost} from "src/interfaces/IOnlyBoost.sol";

/// @title OnlyBoost Strategy Contract
/// @author Stake DAO
/// @notice OnlyBoost Compatible Strategy Proxy Contract to interact with Stake DAO Locker.
abstract contract OnlyBoost is Strategy {
    using SafeTransferLib for ERC20;

    /// @notice Optimizer address for deposit/withdrawal allocations.
    IOnlyBoost internal optimizer;

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    function _deposit(address _asset, uint256 amount) internal override {
        // Get the gauge address
        address gauge = gauges[_asset];
        // Revert if the gauge is not set
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Get the optimal allocation for the deposit.
        (address[] memory recipients, uint256[] memory allocations) =
            optimizer.getOptimalDepositAllocation(_asset, gauge, amount);

        for (uint256 i; i < recipients.length; ++i) {
            // Skip if the allocation amount is 0.
            if (allocations[i] == 0) continue;

            /// Deposit into the locker if the recipient is the locker.
            if (recipients[i] == address(locker)) {
                _depositIntoLocker(_asset, gauge, allocations[i]);
            } else {
                /// Else, transfer the asset to the fallback recipient and call deposit.
                ERC20(_asset).safeTransfer(recipients[i], allocations[i]);
                IFallback(recipients[i]).deposit(_asset, allocations[i]);
            }
        }
    }

    function _withdraw(address _asset, uint256 amount) internal override {
        // Get the gauge address
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Call the Optimizor contract
        (address[] memory recipients, uint256[] memory allocations) =
            optimizer.getOptimalWithdrawalPath(_asset, gauge, amount);

        for (uint256 i; i < recipients.length; ++i) {
            // Skip if the optimized amount is 0
            if (allocations[i] == 0) continue;

            // Special process for Stake DAO locker
            if (recipients[i] == address(locker)) {
                _withdrawFromLocker(_asset, gauge, allocations[i]);
            }
            // Deposit into other fallback
            else {
                IFallback(recipients[i]).withdraw(_asset, allocations[i]);
            }
        }
    }

    /// TO OVERRIDE
    /// CLAIM REWARDS

    /// NATIVE TO THIS CONTRACT
    /// REBALANCE

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE STRATEGY SETTERS
    //////////////////////////////////////////////////////

    /// @notice Set optimizer address
    /// @param _optimizer Optimizer address
    function setOptimizer(address _optimizer) external onlyGovernance {
        optimizer = IOnlyBoost(_optimizer);
    }
}
