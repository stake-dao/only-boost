// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "src/base/strategy/Strategy.sol";
import {IFallback} from "src/base/interfaces/IFallback.sol";
import {IOnlyBoost} from "src/base/interfaces/IOnlyBoost.sol";

/// @notice Override the deposit/withdrawal logic to use the Optimizer contract.
abstract contract OnlyBoost is Strategy {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Optimizer address for deposit/withdrawal allocations.
    IOnlyBoost public optimizer;

    /// @notice Throwed if the rebalance gone wrong.
    error REBALANCE_FAILED();

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    /// @notice Claim rewards from gauge & fallbacks.
    /// @param asset _asset staked to claim for.
    /// @param claimExtra True to claim extra rewards. False can save gas.
    /// @param claimFallbacksRewards  True to claim fallbacks, False can save gas.
    function harvest(address asset, bool distributeSDT, bool claimExtra, bool claimFallbacksRewards) public {
        /// If optimzer is not set, use default withdraw.
        if (address(optimizer) == address(0)) {
            return super.harvest(asset, distributeSDT, claimExtra);
        }

        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Cache the rewardDistributor address.
        address rewardDistributor = rewardDistributors[gauge];

        /// 1. Claim `rewardToken` from the Gauge.
        uint256 claimed = _claimRewardToken(gauge);

        uint256 claimedFromFallbacks;
        uint256 protocolFeesFromFallbacks;

        /// 2. Claim from the fallbacks if requested.
        if (claimFallbacksRewards) {
            (claimedFromFallbacks, protocolFeesFromFallbacks) = _claimFallbacks(gauge, rewardDistributor, claimExtra);
        }

        /// 3. Claim extra rewards if requested.
        if (claimExtra) {
            /// We assume that the extra rewards are the same for all the fallbacks since we deposit in the same destination gauge.
            /// So we claim the extra rewards from the fallbacks first and then claim the extra rewards from the gauge.
            /// Finally, we distribute all in once.
            address rewardReceiver = rewardReceivers[gauge];

            if (rewardReceiver != address(0)) {
                claimed += IRewardReceiver(rewardReceiver).notifyAll();
            } else {
                claimed += _claimExtraRewards(gauge, rewardDistributor);
            }
        }

        /// 4. Take Fees from _claimed amount.
        claimed = claimed + claimedFromFallbacks
            - _chargeProtocolFees(claimed, claimedFromFallbacks, protocolFeesFromFallbacks);

        /// 6. Distribute SDT
        // Distribute SDT to the related gauge
        if (distributeSDT) {
            ISDTDistributor(SDTDistributor).distribute(rewardDistributor);
        }

        /// 7. Distribute the rewardToken.
        ILiquidityGauge(rewardDistributor).deposit_reward_token(rewardToken, claimed);
    }

    /// @notice Rebalance `_asset` splitted into the fallbacks.
    /// @param asset Asset to rebalance.
    function rebalance(address asset) public {
        if (address(optimizer) == address(0)) revert ADDRESS_NULL();

        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Snapshot the current balance.
        uint256 _snapshotBalance = balanceOf(asset);

        /// Get Fallbacks.
        address[] memory fallbacks = optimizer.getFallbacks(gauge);

        /// Get the optimal allocation for the deposit.
        (address[] memory fundsManagers, uint256[] memory allocations) =
            optimizer.getRebalancedAllocation(gauge, _snapshotBalance);

        for (uint256 i; i < fallbacks.length; ++i) {
            /// Get the current balance of the fallbacks.
            uint256 _balanceOfFallback = IFallback(fallbacks[i]).balanceOf(asset);

            if (_balanceOfFallback > 0) {
                /// Withdraw from the fallbacks.
                IFallback(fallbacks[i]).withdraw(asset, _balanceOfFallback);
            }
        }

        /// Get the current balance of the gauge.
        uint256 _balanceOfGauge = ILiquidityGauge(gauge).balanceOf(address(locker));

        if (_balanceOfGauge > 0) {
            /// Withdraw from the locker.
            _withdrawFromLocker(asset, gauge, _balanceOfGauge);
        }

        for (uint256 i; i < fundsManagers.length; ++i) {
            // Skip if the allocation amount is 0.
            if (allocations[i] == 0) continue;

            /// Deposit into the locker if the recipient is the locker.
            if (fundsManagers[i] == address(locker)) {
                _depositIntoLocker(asset, gauge, allocations[i]);
            } else {
                /// Else, transfer the asset to the fallback recipient and call deposit.
                SafeTransferLib.safeTransfer(asset, fundsManagers[i], allocations[i]);
                IFallback(fundsManagers[i]).deposit(asset, allocations[i]);
            }
        }

        if (balanceOf(asset) < _snapshotBalance) revert REBALANCE_FAILED();
    }

    ////////////////////////////////////////////////////////////////
    /// --- FUNCTIONS OVERRIDE
    ///////////////////////////////////////////////////////////////

    /// @notice Deposit `_amount` of `_asset` splitted into the fallbacks.
    /// @param asset Asset to deposit.
    /// @param amount Amount to deposit.
    function _deposit(address asset, uint256 amount) internal override {
        // If optimizer is not set, use default deposit
        if (address(optimizer) == address(0)) {
            return super._deposit(asset, amount);
        }

        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Get the optimal allocation for the deposit.
        (address[] memory fundsManagers, uint256[] memory allocations) =
            optimizer.getOptimalDepositAllocation(gauge, amount);

        for (uint256 i; i < fundsManagers.length; ++i) {
            // Skip if the allocation amount is 0.
            if (allocations[i] == 0) continue;

            /// Deposit into the locker if the recipient is the locker.
            if (fundsManagers[i] == address(locker)) {
                _depositIntoLocker(asset, gauge, allocations[i]);
            } else {
                /// Else, transfer the asset to the fallback recipient and call deposit.
                SafeTransferLib.safeTransfer(asset, fundsManagers[i], allocations[i]);
                IFallback(fundsManagers[i]).deposit(asset, allocations[i]);
            }
        }
    }

    /// @notice Withdraw `_amount` of `_asset` splitted into the fallbacks.
    /// @param asset Asset to withdraw.
    /// @param amount Amount to withdraw.
    /// @dev The optimizer contract would make sure to always withdraw from the biggest pool first.
    function _withdraw(address asset, uint256 amount) internal override {
        /// If optimzer is not set, use default withdraw.
        if (address(optimizer) == address(0)) {
            return super._withdraw(asset, amount);
        }

        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Get the optimal withdrawal path.
        (address[] memory fundsManagers, uint256[] memory allocations) =
            optimizer.getOptimalWithdrawalPath(gauge, amount);

        for (uint256 i; i < fundsManagers.length; ++i) {
            /// Skip if the optimized amount is 0.
            if (allocations[i] == 0) continue;

            /// If the recipient is the locker, withdraw from the locker.
            if (fundsManagers[i] == address(locker)) {
                _withdrawFromLocker(asset, gauge, allocations[i]);
            }
            /// Else, call withdraw on the fallback.
            else {
                IFallback(fundsManagers[i]).withdraw(asset, allocations[i]);
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    /// --- ONLYBOOST RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    /// @param amount Amount to charge protocol fees.
    /// @param claimedFromFallbacks Amount claimed from the fallbacks.
    /// @param totalProtocolFeesFromFallbacks Total protocol fees claimed taken from the fallbacks.
    /// @return _amount Amount left after charging protocol fees.
    function _chargeProtocolFees(uint256 amount, uint256 claimedFromFallbacks, uint256 totalProtocolFeesFromFallbacks)
        internal
        returns (uint256)
    {
        if (amount == 0 && claimedFromFallbacks == 0) return 0;
        // If there's no protocol fees set and there's no protocol fees from fallbacks, return the total amount
        if (protocolFeesPercent == 0 && totalProtocolFeesFromFallbacks == 0 && claimIncentiveFee == 0) return 0;

        // Calculate the fees accrued from the claimed amount
        uint256 _feeAccrued = amount.mulDiv(protocolFeesPercent, DENOMINATOR);

        // Update the total fees accrued with the fee accrued from this claim and the protocol fees from fallbacks
        feesAccrued += _feeAccrued + totalProtocolFeesFromFallbacks;

        /// Distribute Claim Incentive Fees to the caller.
        if (claimIncentiveFee == 0) return _feeAccrued + totalProtocolFeesFromFallbacks;

        uint256 claimerIncentive = (amount + claimedFromFallbacks).mulDiv(claimIncentiveFee, DENOMINATOR);
        SafeTransferLib.safeTransfer(rewardToken, msg.sender, claimerIncentive);

        return _feeAccrued + totalProtocolFeesFromFallbacks + claimerIncentive;
    }

    /// @notice Claim rewards from the fallbacks.
    /// @param gauge Address of the liquidity gauge.
    /// @param rewardDistributor Address of the reward distributor.
    /// @param claimExtra True to claim extra rewards.
    /// @return claimed RewardToken amount claimed from the fallbacks to add to the total claimed amount and avoid double distribution.
    /// @return totalProtocolFees Total protocol fees claimed from the fallbacks.
    function _claimFallbacks(address gauge, address rewardDistributor, bool claimExtra)
        internal
        returns (uint256 claimed, uint256 totalProtocolFees)
    {
        /// Get the fallback addresses.
        address[] memory fallbacks;
        fallbacks = optimizer.getFallbacks(gauge);

        address fallbackRewardToken;

        for (uint256 i; i < fallbacks.length;) {
            // Do the claim
            (uint256 rewardTokenAmount, uint256 fallbackRewardTokenAmount, uint256 protocolFees) =
                IFallback(fallbacks[i]).claim(claimExtra, false, address(this));

            // Add the rewardTokenAmount to the _claimed amount.
            claimed += rewardTokenAmount;
            totalProtocolFees += protocolFees;

            /// Distribute the fallbackRewardToken.
            fallbackRewardToken = IFallback(fallbacks[i]).fallbackRewardToken();
            if (fallbackRewardToken != address(0) && fallbackRewardTokenAmount > 0) {
                /// Distribute the fallbackRewardToken.
                ILiquidityGauge(rewardDistributor).deposit_reward_token(fallbackRewardToken, fallbackRewardTokenAmount);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Balance of asset in the locker and fallbacks.
    function balanceOf(address asset) public view override returns (uint256 _balanceOf) {
        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        _balanceOf = ILiquidityGauge(gauge).balanceOf(address(locker));
        address[] memory _fallbacks = optimizer.getFallbacks(gauge);

        for (uint256 i; i < _fallbacks.length; ++i) {
            _balanceOf += IFallback(_fallbacks[i]).balanceOf(asset);
        }
    }

    function getVersion() external pure override returns (string memory) {
        return "1.0";
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
