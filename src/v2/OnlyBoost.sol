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
    using FixedPointMathLib for uint256;

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
        (address[] memory fundsManagers, uint256[] memory allocations) =
            optimizer.getOptimalDepositAllocation(gauge, amount);

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
    function claim(address _asset, bool _claimExtra, bool _claimFallbacksRewards) public {
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
        ISdtDistributorV2(SDTDistributor).distribute(rewardDistributor);

        /// 7. Distribute the rewardToken.
        ILiquidityGauge(rewardDistributor).deposit_reward_token(rewardToken, _claimed);
    }

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    /// @return _amount Amount left after charging protocol fees.
    function _chargeProtocolFees(
        uint256 _amount,
        uint256 _claimedFromFallbacks,
        uint256 _totalProtocolFeesFromFallbacks
    ) internal returns (uint256) {
        if (_amount == 0) return 0;
        if (protocolFeesPercent == 0) return _amount;

        uint256 _feeAccrued = _amount.mulDivDown(protocolFeesPercent, DENOMINATOR);
        feesAccrued += _feeAccrued + _totalProtocolFeesFromFallbacks;

        /// Add the _claimedFromFallbacks to the _claimed amount only.
        /// We add it here to avoid the fees to be charged on the _claimedFromFallbacks amount.
        return _amount -= _feeAccrued - _totalProtocolFeesFromFallbacks + _claimedFromFallbacks;
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
            if (_fallbackRewardToken != address(0)) {
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
