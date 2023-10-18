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

        IBaseRewardPool baseRewardPool = proxy.baseRewardPool();

        uint256 _expectedLockerRewardTokenAmount = _getSdRewardTokenMinted();
        uint256 _expectedFallbackRewardTokenAmount;

        uint256 _totalRewardTokenAmount = _expectedLockerRewardTokenAmount;

        uint256[] memory _extraRewardsEarned = new uint256[](extraRewardTokens.length);
        uint256[] memory _SDExtraRewardsEarned = new uint256[](extraRewardTokens.length);

        uint256 _earned;
        if (_claimFallbacks) {
            _earned = baseRewardPool.earned(address(proxy));
            _totalRewardTokenAmount += _earned;

            _expectedFallbackRewardTokenAmount = _getFallbackRewardMinted();
        }

        if (_claimExtraRewards && extraRewardTokens.length > 0) {
            _SDExtraRewardsEarned = _getSDExtraRewardsEarned();

            if (_claimFallbacks) {
                for (uint256 i = 0; i < extraRewardTokens.length; i++) {
                    address virtualPool = baseRewardPool.extraRewards(i);
                    _extraRewardsEarned[i] = IBaseRewardPool(virtualPool).earned(address(proxy));

                    if (extraRewardTokens[i] == REWARD_TOKEN) {
                        _totalRewardTokenAmount += _extraRewardsEarned[i] + _SDExtraRewardsEarned[i];
                    }

                    if (extraRewardTokens[i] == FALLBACK_REWARD_TOKEN) {
                        _expectedFallbackRewardTokenAmount += _extraRewardsEarned[i] + _SDExtraRewardsEarned[i];
                    }
                }
            }
        }

        vm.prank(address(0xBEEC));
        strategy.harvest(address(token), _distributeSDT, _claimExtraRewards, _claimFallbacks);

        uint256 _balanceRewardToken = ERC20(REWARD_TOKEN).balanceOf(address(rewardDistributor));

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(proxy)), 0);

        if (_setFees) {
            /// Compute the fees.
            uint256 _protocolFee;
            if (_setFallbackFees && _claimFallbacks) {
                _protocolFee = _expectedLockerRewardTokenAmount.mulDivDown(17, 100);
                _protocolFee += _earned.mulDivDown(17, 100);
            } else {
                _protocolFee = _expectedLockerRewardTokenAmount.mulDivDown(17, 100);
            }
            _totalRewardTokenAmount -= _protocolFee;

            uint256 _claimerFee = _totalRewardTokenAmount.mulDivDown(1, 100);
            _totalRewardTokenAmount -= _claimerFee;

            assertEq(ERC20(REWARD_TOKEN).balanceOf(address(0xBEEC)), _claimerFee);
            assertEq(ERC20(REWARD_TOKEN).balanceOf(address(strategy)), _protocolFee);
            assertEq(_balanceRewardToken, _totalRewardTokenAmount);
        } else {
            assertEq(ERC20(REWARD_TOKEN).balanceOf(address(0xBEEC)), 0);
            assertEq(ERC20(REWARD_TOKEN).balanceOf(address(strategy)), 0);

            assertEq(_balanceRewardToken, _totalRewardTokenAmount);
        }

        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(this)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(proxy)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(strategy)), 0);

        if (_claimExtraRewards) {
            /// Loop through the extra reward tokens.
            for (uint256 i = 0; i < extraRewardTokens.length; i++) {
                assertEq(ERC20(extraRewardTokens[i]).balanceOf(address(this)), 0);
                assertEq(ERC20(extraRewardTokens[i]).balanceOf(address(proxy)), 0);
                assertEq(ERC20(extraRewardTokens[i]).balanceOf(address(strategy)), 0);

                /// Only if there's reward flowing, we assert that there's some balance.
                if (_extraRewardsEarned[i] > 0) {
                    _balanceRewardToken = ERC20(extraRewardTokens[i]).balanceOf(address(rewardDistributor));

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
    }
}
