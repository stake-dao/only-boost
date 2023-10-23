// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import "forge-std/Test.sol";

import "src/strategy/Strategy.sol";

import {IFallback} from "src/interfaces/IFallback.sol";
import {IOnlyBoost} from "src/interfaces/IOnlyBoost.sol";

/// @title OnlyBoost Strategy Contract
/// @author Stake DAO
/// @notice OnlyBoost Compatible Strategy Proxy Contract to interact with Stake DAO Locker.
abstract contract OnlyBoost is Strategy {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Optimizer address for deposit/withdrawal allocations.
    IOnlyBoost public optimizer;

    error REBALANCE_FAILED();

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
        (address[] memory fundsManagers, uint256[] memory allocations) =
            optimizer.getOptimalDepositAllocation(gauge, amount, false);

        for (uint256 i; i < fundsManagers.length; ++i) {
            // Skip if the allocation amount is 0.
            if (allocations[i] == 0) continue;

            /// Deposit into the locker if the recipient is the locker.
            if (fundsManagers[i] == address(locker)) {
                _depositIntoLocker(_asset, gauge, allocations[i]);
            } else {
                /// Else, transfer the asset to the fallback recipient and call deposit.
                ERC20(_asset).safeTransfer(fundsManagers[i], allocations[i]);
                IFallback(fundsManagers[i]).deposit(_asset, allocations[i]);
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
        (address[] memory fundsManagers, uint256[] memory allocations) =
            optimizer.getOptimalWithdrawalPath(gauge, amount);

        for (uint256 i; i < fundsManagers.length; ++i) {
            // Skip if the optimized amount is 0
            if (allocations[i] == 0) continue;

            // Special process for Stake DAO locker
            if (fundsManagers[i] == address(locker)) {
                _withdrawFromLocker(_asset, gauge, allocations[i]);
            }
            // Withdraw from other fallback
            else {
                IFallback(fundsManagers[i]).withdraw(_asset, allocations[i]);
            }
        }
    }

    /// @notice Claim rewards from gauge & fallbacks.
    /// @param _asset _asset staked to claim for.
    /// @param _claimExtra True to claim extra rewards. False can save gas.
    /// @param _claimFallbacksRewards  True to claim fallbacks, False can save gas.
    function harvest(address _asset, bool _distributeSDT, bool _claimExtra, bool _claimFallbacksRewards) public {
        // Get the gauge address
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Cache the rewardDistributor address.
        address rewardDistributor = rewardDistributors[gauge];

        /// 1. Claim `rewardToken` from the Gauge.
        uint256 _claimed = _claimRewardToken(gauge);

        uint256 _claimedFromFallbacks;
        uint256 _protocolFeesFromFallbacks;

        /// 2. Claim from the fallbacks if requested.
        if (_claimFallbacksRewards) {
            (_claimedFromFallbacks, _protocolFeesFromFallbacks) = _claimFallbacks(gauge, rewardDistributor, _claimExtra);
        }

        /// 3. Claim extra rewards if requested.
        if (_claimExtra) {
            /// We assume that the extra rewards are the same for all the fallbacks since we deposit in the same destination gauge.
            /// So we claim the extra rewards from the fallbacks first and then claim the extra rewards from the gauge.
            /// Finally, we distribute all in once.
            _claimed += _claimExtraRewards(gauge, rewardDistributor);
        }

        /// 4. Take Fees from _claimed amount.
        _claimed = _chargeProtocolFees(_claimed, _claimedFromFallbacks, _protocolFeesFromFallbacks);

        /// 5. Distribute Claim Incentive
        _claimed = _distributeClaimIncentive(_claimed);

        /// 6. Distribute SDT
        // Distribute SDT to the related gauge
        if (_distributeSDT) {
            console.log("ICI");
            ISdtDistributorV2(SDTDistributor).distribute(rewardDistributor);
        }

        /// 7. Distribute the rewardToken.
        ILiquidityGauge(rewardDistributor).deposit_reward_token(rewardToken, _claimed);
    }

    function rebalance(address _asset) public {
        if (address(optimizer) == address(0)) revert ADDRESS_NULL();

        // Get the gauge address
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Snapshot the current balance.
        uint256 _snapshotBalance = balanceOf(_asset);

        /// Get Fallbacks.
        address[] memory fallbacks = optimizer.getFallbacks(gauge);

        for (uint256 i; i < fallbacks.length; ++i) {
            /// Get the current balance of the fallbacks.
            uint256 _balanceOfFallback = IFallback(fallbacks[i]).balanceOf(_asset);

            if (_balanceOfFallback > 0) {
                /// Withdraw from the fallbacks.
                IFallback(fallbacks[i]).withdraw(_asset, _balanceOfFallback);
            }
        }

        /// Get the current balance of the gauge.
        uint256 _balanceOfGauge = ILiquidityGauge(gauge).balanceOf(address(locker));

        if (_balanceOfGauge > 0) {
            /// Withdraw from the locker.
            _withdrawFromLocker(_asset, gauge, _balanceOfGauge);
        }

        uint256 _currentBalance = ERC20(_asset).balanceOf(address(this));

        /// Get the optimal allocation for the deposit.
        (address[] memory fundsManagers, uint256[] memory allocations) =
            optimizer.getOptimalDepositAllocation(gauge, _currentBalance, true);

        for (uint256 i; i < fundsManagers.length; ++i) {
            // Skip if the allocation amount is 0.
            if (allocations[i] == 0) continue;

            /// Deposit into the locker if the recipient is the locker.
            if (fundsManagers[i] == address(locker)) {
                _depositIntoLocker(_asset, gauge, allocations[i]);
            } else {
                /// Else, transfer the asset to the fallback recipient and call deposit.
                ERC20(_asset).safeTransfer(fundsManagers[i], allocations[i]);
                IFallback(fundsManagers[i]).deposit(_asset, allocations[i]);
            }
        }

        _currentBalance = balanceOf(_asset);

        if (_currentBalance < _snapshotBalance) revert REBALANCE_FAILED();
    }

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    /// @return _amount Amount left after charging protocol fees.
    function _chargeProtocolFees(
        uint256 _amount,
        uint256 _claimedFromFallbacks,
        uint256 _totalProtocolFeesFromFallbacks
    ) internal returns (uint256) {
        // If there's no amount and no protocol fees from fallbacks, return the amount claimed from fallbacks
        if (_amount == 0 && _totalProtocolFeesFromFallbacks == 0) return _claimedFromFallbacks;

        // If there's no protocol fees set and there's no protocol fees from fallbacks, return the total amount
        if (protocolFeesPercent == 0 && _totalProtocolFeesFromFallbacks == 0) return _amount + _claimedFromFallbacks;

        // Calculate the fees accrued from the claimed amount
        uint256 _feeAccrued = _amount.mulDivDown(protocolFeesPercent, DENOMINATOR);

        // Update the total fees accrued with the fee accrued from this claim and the protocol fees from fallbacks
        feesAccrued += _feeAccrued + _totalProtocolFeesFromFallbacks;

        // Reduce the amount by the fees accrued but add back the protocol fees from fallbacks and the amount claimed from fallbacks
        uint256 _netAmount = _amount + _claimedFromFallbacks - _feeAccrued - _totalProtocolFeesFromFallbacks;

        return _netAmount;
    }

    function _claimFallbacks(address gauge, address rewardDistributor, bool _claimExtra)
        internal
        returns (uint256 _claimed, uint256 _totalProtocolFees)
    {
        /// Get the fallback addresses.
        address[] memory fallbacks;
        fallbacks = optimizer.getFallbacks(gauge);

        address _fallbackRewardToken;

        for (uint256 i; i < fallbacks.length;) {
            // Do the claim
            (uint256 rewardTokenAmount, uint256 fallbackRewardTokenAmount, uint256 protocolFees) =
                IFallback(fallbacks[i]).claim(_claimExtra);

            // Add the rewardTokenAmount to the _claimed amount.
            _claimed += rewardTokenAmount;
            _totalProtocolFees += protocolFees;

            /// Distribute the fallbackRewardToken.
            _fallbackRewardToken = IFallback(fallbacks[i]).fallbackRewardToken();
            if (_fallbackRewardToken != address(0) && fallbackRewardTokenAmount > 0) {
                /// Distribute the fallbackRewardToken.
                ILiquidityGauge(rewardDistributor).deposit_reward_token(_fallbackRewardToken, fallbackRewardTokenAmount);
            }

            unchecked {
                ++i;
            }
        }
    }

    function balanceOf(address _asset) public view override returns (uint256 _balanceOf) {
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        _balanceOf = ILiquidityGauge(gauge).balanceOf(address(locker));
        address[] memory _fallbacks = optimizer.getFallbacks(gauge);

        for (uint256 i; i < _fallbacks.length; ++i) {
            _balanceOf += IFallback(_fallbacks[i]).balanceOf(_asset);
        }
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE STRATEGY SETTERS
    //////////////////////////////////////////////////////

    /// @notice Set optimizer address
    /// @param _optimizer Optimizer address
    function setOptimizer(address _optimizer) external onlyGovernance {
        optimizer = IOnlyBoost(_optimizer);
    }
}
