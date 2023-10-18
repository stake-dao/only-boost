// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/Base.t.sol";

abstract contract OnlyBoost_Test is Base_Test {
    using FixedPointMathLib for uint256;

    constructor(uint256 pid, address _rewardDistributor) Base_Test(pid, _rewardDistributor) {}

    function setUp() public override {
        Base_Test.setUp();
    }

    function test_deposit(uint128 _amount) public {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);

        deal(address(token), address(this), amount);

        /// Snapshot optimal SD balance before deposit.
        uint256 optimalSDBalance = optimizer.computeOptimalDepositAmount(gauge);

        /// Check if Convex has maxboost.
        uint256 balance = ILiquidityGauge(gauge).balanceOf(CONVEX_VOTER_PROXY);
        uint256 workingBalance = ILiquidityGauge(gauge).working_balances(CONVEX_VOTER_PROXY);

        /// Assert that nor SD or Convex has tokens.
        assertEq(proxy.balanceOf(address(token)), 0);
        assertEq(ILiquidityGauge(gauge).balanceOf(SD_VOTER_PROXY), 0);

        strategy.deposit(address(token), amount);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(proxy)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(SD_VOTER_PROXY)), 0);

        assertEq(strategy.balanceOf(address(token)), amount);

        /// Means that Convex has maxboost.
        /// So we expect that deposit will be done to Convex.
        if (balance == workingBalance) {
            assertEq(proxy.balanceOf(address(token)), amount);
            assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), 0);
        } else if (optimalSDBalance >= amount) {
            /// If the optimal balance is greater than the amount we want to deposit,
            /// Everything will be deposited to SD.
            assertEq(proxy.balanceOf(address(token)), 0);
            assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), amount);
        } else {
            // Compute convexBalance between optimal balance and amount.
            uint256 convexBalance = amount - optimalSDBalance;

            assertGt(convexBalance, 0);
            assertEq(proxy.balanceOf(address(token)), convexBalance);
            assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), optimalSDBalance);
        }
    }

    function test_withdraw(uint128 _amount, uint128 _toWithdraw) public {
        uint256 amount = uint256(_amount);
        uint256 toWithdraw = uint256(_toWithdraw);

        vm.assume(amount != 0);
        vm.assume(toWithdraw != 0);
        vm.assume(amount >= toWithdraw);

        deal(address(token), address(this), amount);

        /// Snapshot optimal SD balance before deposit.
        uint256 optimalSDBalance = optimizer.computeOptimalDepositAmount(gauge);

        /// Check if Convex has maxboost.
        uint256 balance = ILiquidityGauge(gauge).balanceOf(CONVEX_VOTER_PROXY);
        uint256 workingBalance = ILiquidityGauge(gauge).working_balances(CONVEX_VOTER_PROXY);

        strategy.deposit(address(token), amount);

        /// Snapshot balances
        uint256 proxyBalance = proxy.balanceOf(address(token));
        uint256 sdBalance = ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY));

        strategy.withdraw(address(token), toWithdraw);

        /// Means that Convex has maxboost.
        /// So we expect that deposit will be done to Convex.
        if (balance == workingBalance) {
            assertEq(token.balanceOf(address(proxy)), 0);
            assertEq(token.balanceOf(address(this)), toWithdraw);
            assertEq(proxy.balanceOf(address(token)), amount - toWithdraw);
            assertEq(token.balanceOf(address(SD_VOTER_PROXY)), 0);
            assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), 0);
        } else if (optimalSDBalance > amount) {
            /// If the optimal balance is greater than the amount we want to deposit,
            /// Everything will be deposited to SD.
            assertEq(token.balanceOf(address(proxy)), 0);
            assertEq(token.balanceOf(address(this)), toWithdraw);
            assertEq(proxy.balanceOf(address(token)), 0);
            assertEq(token.balanceOf(address(SD_VOTER_PROXY)), 0);
            assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), amount - toWithdraw);
        } else {
            /// If proxy has more tokens than SD, we expect that everything will be withdrawn from Convex.
            // Or a mix of Convex and SD.
            // Compute convexBalance between optimal balance and amount.
            uint256 convexBalance = amount - optimalSDBalance;

            if (proxyBalance > sdBalance) {
                /// If we withdraw less than convexBalance, we expect that everything will be withdrawn from Convex.
                if (convexBalance > toWithdraw) {
                    assertEq(proxy.balanceOf(address(token)), convexBalance - toWithdraw);
                    assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), optimalSDBalance);
                } else {
                    assertEq(proxy.balanceOf(address(token)), 0);
                    uint256 leftToWithdraw = toWithdraw - convexBalance;
                    assertEq(
                        ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), optimalSDBalance - leftToWithdraw
                    );
                }
            } else {
                /// If we withdraw less than convexBalance, we expect that everything will be withdrawn from Convex.
                if (optimalSDBalance > toWithdraw) {
                    assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), optimalSDBalance - toWithdraw);
                    assertEq(proxy.balanceOf(address(token)), convexBalance);
                } else {
                    assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), 0);
                    uint256 leftToWithdraw = toWithdraw - optimalSDBalance;
                    assertEq(proxy.balanceOf(address(token)), convexBalance - leftToWithdraw);
                }
            }
        }
    }

    function test_harvest(
        uint128 _amount,
        uint256 _weeksToSkip,
        bool _distributeSDT,
        bool _claimExtraRewards,
        bool _claimFallbacks,
        bool _setFees,
        bool _setFallbackFees
    ) public {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);
        vm.assume(_weeksToSkip < 10);

        deal(address(token), address(this), amount);
        strategy.deposit(address(token), amount);

        if (_setFees) {
            strategy.updateProtocolFee(1_700); // 17%
            strategy.updateClaimIncentiveFee(100); // 1%
            /// Total: 18%

            if (_setFallbackFees) {
                factory.updateProtocolFee(1_700); // 17%
            }
        }

        /// Need to first skip weeks to harvest Convex.
        skip(_weeksToSkip * 1 weeks);

        vm.prank(address(0xBEEF));
        IBooster(BOOSTER).earmarkRewards(pid);

        /// Then skip weeks to harvest SD.
        skip(_weeksToSkip * 1 weeks);

        uint256 _expectedLockerRewardTokenAmount = _getSdRewardTokenMinted();
        uint256 _expectedFallbackRewardTokenAmount;

        uint256 _totalRewardTokenAmount = _expectedLockerRewardTokenAmount;

        uint256[] memory _extraRewardsEarned = new uint256[](extraRewardTokens.length);
        uint256[] memory _SDExtraRewardsEarned = new uint256[](extraRewardTokens.length);

        uint256 _earned;
        if (_claimFallbacks) {
            _earned = proxy.baseRewardPool().earned(address(proxy));
            _totalRewardTokenAmount += _earned;

            _expectedFallbackRewardTokenAmount = _getFallbackRewardMinted();
        }

        if (_claimExtraRewards && extraRewardTokens.length > 0) {
            _SDExtraRewardsEarned = _getSDExtraRewardsEarned();

            if (_claimFallbacks) {
                (_totalRewardTokenAmount, _expectedFallbackRewardTokenAmount, _extraRewardsEarned) =
                _checkForDuplicatesExtraRewards(
                    _totalRewardTokenAmount, _expectedFallbackRewardTokenAmount, _SDExtraRewardsEarned
                );
            }
        }

        vm.prank(address(0xBEEC));
        strategy.harvest(address(token), _distributeSDT, _claimExtraRewards, _claimFallbacks);

        uint256 _balanceRewardToken = ERC20(REWARD_TOKEN).balanceOf(address(rewardDistributor));

        if (_setFees) {
            _checkCorrectFeeCompute(
                _setFallbackFees,
                _claimFallbacks,
                _earned,
                _expectedLockerRewardTokenAmount,
                _totalRewardTokenAmount,
                _balanceRewardToken
            );
        } else {
            assertEq(strategy.feesAccrued(), 0);

            assertEq(_balanceOf(REWARD_TOKEN, address(this)), 0);
            assertEq(_balanceOf(REWARD_TOKEN, address(proxy)), 0);
            assertEq(_balanceOf(REWARD_TOKEN, address(0xBEEC)), 0);
            assertEq(_balanceOf(REWARD_TOKEN, address(strategy)), 0);

            assertEq(_balanceRewardToken, _totalRewardTokenAmount);
        }

        assertEq(_balanceOf(FALLBACK_REWARD_TOKEN, address(this)), 0);
        assertEq(_balanceOf(FALLBACK_REWARD_TOKEN, address(proxy)), 0);
        assertEq(_balanceOf(FALLBACK_REWARD_TOKEN, address(strategy)), 0);

        if (_claimExtraRewards) {
            _checkExtraRewardsDistribution(_extraRewardsEarned, _SDExtraRewardsEarned, _claimFallbacks);
        }
    }

    function test_fee_computation(uint128 _amount, uint256 _weeksToSkip, bool _setFallbackFees) public {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);
        vm.assume(_weeksToSkip < 10);

        // Deposit
        deal(address(token), address(this), amount);
        strategy.deposit(address(token), amount);

        // Set Fees
        strategy.updateProtocolFee(1_700); // 17%
        strategy.updateClaimIncentiveFee(100); // 1%

        if (_setFallbackFees) {
            factory.updateProtocolFee(1_700); // 17%
        }

        uint256 claimerFee;
        uint256 totalRewardTokenAmount;
        uint256 totalProtocolFeesAccrued;

        // Harvest and Check Fees Twice
        for (uint256 i = 0; i < 2; i++) {
            // Skip weeks for the harvest
            skip(_weeksToSkip * 1 weeks);

            // Harvest
            vm.prank(address(0xBEEF));
            IBooster(BOOSTER).earmarkRewards(pid);

            // Calculate and check fees
            uint256 expectedLockerRewardTokenAmount = _getSdRewardTokenMinted();
            uint256 earned = proxy.baseRewardPool().earned(address(proxy));

            vm.prank(address(0xBEEC));
            strategy.harvest(address(token), false, true, true);

            (totalProtocolFeesAccrued, claimerFee, totalRewardTokenAmount) = _checkFees(
                totalRewardTokenAmount, totalProtocolFeesAccrued, claimerFee, expectedLockerRewardTokenAmount, earned, _setFallbackFees
            );
        }
    }

    function _checkFees(
        uint256 totalRewardTokenAmount,
        uint256 totalProtocolFeesAccrued,
        uint256 claimerFee,
        uint256 _expectedLockerRewardTokenAmount,
        uint256 _earned,
        bool _setFallbackFees
    ) internal returns (uint256, uint256, uint256) {
        uint256 protocolFeeForThisHarvest = _expectedLockerRewardTokenAmount.mulDivDown(17, 100);

        if (_setFallbackFees && _earned > 0) {
            protocolFeeForThisHarvest += _earned.mulDivDown(17, 100);
        }

        totalProtocolFeesAccrued += protocolFeeForThisHarvest;
        uint256 _totalRewardTokenAmount = _expectedLockerRewardTokenAmount + _earned - protocolFeeForThisHarvest;

        uint256 _claimerFee = _totalRewardTokenAmount.mulDivDown(1, 100);
        claimerFee += _claimerFee;

        _totalRewardTokenAmount -= _claimerFee;

        totalRewardTokenAmount += _totalRewardTokenAmount;

        assertEq(strategy.feesAccrued(), totalProtocolFeesAccrued);
        assertEq(_balanceOf(REWARD_TOKEN, address(0xBEEC)), claimerFee);
        assertEq(_balanceOf(REWARD_TOKEN, address(strategy)), totalProtocolFeesAccrued);
        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(rewardDistributor)), totalRewardTokenAmount);

        return (totalProtocolFeesAccrued, claimerFee, totalRewardTokenAmount);
    }

    function _checkForDuplicatesExtraRewards(
        uint256 _totalRewardTokenAmount,
        uint256 _expectedFallbackRewardTokenAmount,
        uint256[] memory _SDExtraRewardsEarned
    ) internal view returns (uint256, uint256, uint256[] memory _extraRewardsEarned) {
        _extraRewardsEarned = new uint256[](extraRewardTokens.length);

        for (uint256 i = 0; i < extraRewardTokens.length; i++) {
            address virtualPool = proxy.baseRewardPool().extraRewards(i);
            _extraRewardsEarned[i] = IBaseRewardPool(virtualPool).earned(address(proxy));

            if (extraRewardTokens[i] == REWARD_TOKEN) {
                _totalRewardTokenAmount += _extraRewardsEarned[i] + _SDExtraRewardsEarned[i];
            }

            if (extraRewardTokens[i] == FALLBACK_REWARD_TOKEN) {
                _expectedFallbackRewardTokenAmount += _extraRewardsEarned[i] + _SDExtraRewardsEarned[i];
            }
        }

        return (_totalRewardTokenAmount, _expectedFallbackRewardTokenAmount, _extraRewardsEarned);
    }

    function _checkCorrectFeeCompute(
        bool _setFallbackFees,
        bool _claimFallbacks,
        uint256 _earned,
        uint256 _expectedLockerRewardTokenAmount,
        uint256 _totalRewardTokenAmount,
        uint256 _balanceRewardToken
    ) internal {
        uint256 _claimerFee;
        uint256 _protocolFee;

        /// Compute the fees.
        if (_setFallbackFees && _claimFallbacks) {
            _protocolFee = _expectedLockerRewardTokenAmount.mulDivDown(17, 100);
            _protocolFee += _earned.mulDivDown(17, 100);
        } else {
            _protocolFee = _expectedLockerRewardTokenAmount.mulDivDown(17, 100);
        }
        _totalRewardTokenAmount -= _protocolFee;

        _claimerFee = _totalRewardTokenAmount.mulDivDown(1, 100);
        _totalRewardTokenAmount -= _claimerFee;

        assertEq(_balanceOf(REWARD_TOKEN, address(0xBEEC)), _claimerFee);

        assertEq(strategy.feesAccrued(), _protocolFee);
        assertEq(_balanceOf(REWARD_TOKEN, address(strategy)), _protocolFee);

        assertEq(_balanceRewardToken, _totalRewardTokenAmount);
    }

    function _checkExtraRewardsDistribution(
        uint256[] memory _extraRewardsEarned,
        uint256[] memory _SDExtraRewardsEarned,
        bool _claimFallbacks
    ) internal {
        /// Loop through the extra reward tokens.
        for (uint256 i = 0; i < extraRewardTokens.length; i++) {
            assertEq(_balanceOf(extraRewardTokens[i], address(this)), 0);
            assertEq(_balanceOf(extraRewardTokens[i], address(proxy)), 0);
            assertEq(_balanceOf(extraRewardTokens[i], address(strategy)), 0);

            /// Only if there's reward flowing, we assert that there's some balance.
            if (_extraRewardsEarned[i] > 0) {
                uint256 _balanceRewardToken = ERC20(extraRewardTokens[i]).balanceOf(address(rewardDistributor));

                if (extraRewardTokens[i] == REWARD_TOKEN) continue;
                if (extraRewardTokens[i] == FALLBACK_REWARD_TOKEN) continue;

                if (_claimFallbacks) {
                    assertEq(_balanceRewardToken, _extraRewardsEarned[i] + _SDExtraRewardsEarned[i]);
                } else {
                    assertEq(_balanceRewardToken, _SDExtraRewardsEarned[i]);
                }
            }
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == address(0)) {
            return account.balance;
        }

        return ERC20(token).balanceOf(account);
    }
}
