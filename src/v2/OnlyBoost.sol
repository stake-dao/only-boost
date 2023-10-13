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
    IOnlyBoost public optimizer;

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    function _deposit(address _asset, uint256 amount) internal override {
        // If optimizer is not set, use default deposit
        if (address(optimizer) == address(0)) {
            return super._deposit(_asset, amount);
        }

        // Get the gauge address
        address gauge = gauges[_asset];
        // Revert if the gauge is not set
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Get the optimal allocation for the deposit.
        (address[] memory recipients, uint256[] memory allocations) =
            optimizer.getOptimalDepositAllocation(gauge, amount);

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
        /// If optimzer is not set, use default withdraw.
        if (address(optimizer) == address(0)) {
            return super._withdraw(_asset, amount);
        }

        // Get the gauge address
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Call the Optimizor contract
        (address[] memory recipients, uint256[] memory allocations) =
            optimizer.getOptimalWithdrawalPath(gauge, amount);

        for (uint256 i; i < recipients.length; ++i) {
            // Skip if the optimized amount is 0
            if (allocations[i] == 0) continue;

            // Special process for Stake DAO locker
            if (recipients[i] == address(locker)) {
                _withdrawFromLocker(_asset, gauge, allocations[i]);
            }
            // Withdraw from other fallback
            else {
                IFallback(recipients[i]).withdraw(_asset, allocations[i]);
            }
        }
    }

    function claim(address _asset) public override {
        // If optimizer is not set, use default claim
        if (address(optimizer) == address(0)) {
            return super.claim(_asset);
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

    /// TODO: Implement
    //// It should withdraw from all the fallbacks and deposit into the locker
    ///  Then set the optimizer address to 0
    function killOptimizer() external onlyGovernance {}
}
