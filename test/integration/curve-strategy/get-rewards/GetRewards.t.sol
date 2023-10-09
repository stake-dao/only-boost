// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/Base.t.sol";

abstract contract Get_Rewards_Test is Base_Test {
    constructor(address _asset, address _gauge) Base_Test(_asset, _gauge) {}

    function setUp() public override {
        vm.rollFork({blockNumber: 18_127_824});
        Base_Test.setUp();

        /// Setup Strategy
        curveStrategy.setGauge({token: address(asset), gauge: address(gauge)});
        curveStrategy.setRewardDistributor(address(gauge), address(mockLiquidityGauge));

        /// Setup Mocked Accumulator.
        curveStrategy.setAccumulator(address(mockAccumulator));
        assertEq(address(curveStrategy.accumulator()), address(mockAccumulator));

        /// Approve Strategy to spend asset.
        asset.approve(address(curveStrategy), type(uint256).max);
    }

    function test_Claim_OnlyLocker() public {
        /// Make sure the amount is big enough to split between fallback and Stake DAO.
        _createDeposit({_amount: 1_000_000e18, _split: true, _resetSD: true});

        curveStrategy.claim(address(asset), false);
    }
}
