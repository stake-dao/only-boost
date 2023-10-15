// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/Base.sol";

abstract contract Deposit_Test is Base_Test {
    constructor(uint256 pid, address _rewardDistributor) Base_Test(pid, _rewardDistributor) {}

    function setUp() public override {
        vm.rollFork({blockNumber: 18_127_824});
        Base_Test.setUp();

        vm.label(address(this), "Vault");
    }

    function test_deposit(uint128 _amount) public {
        uint256 amount = uint256(_amount);

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
        } else if (optimalSDBalance > amount) {
            /// If the optimal balance is greater than the amount we want to deposit,
            /// Everything will be deposited to SD.
            assertEq(proxy.balanceOf(address(token)), 0);
            assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), amount);
        } else {
            // Compute difference between optimal balance and amount.
            uint256 difference = amount - optimalSDBalance;

            assertGt(difference, 0);
            assertEq(proxy.balanceOf(address(token)), difference);
            assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), optimalSDBalance);
        }
    }
}
