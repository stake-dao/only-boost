// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/Base.t.sol";
import "test/mocks/WrongFeeDistributorMock.sol";

contract Get_Native_Rewards_Test is Base_Test {
    constructor() Base_Test(address(0), address(0)) {}

    WrongFeeDistributorMock public wrongFeeDistributorMock;

    function setUp() public override {
        vm.rollFork({blockNumber: 18_127_824});
        Base_Test.setUp();

        /// Deploy wrong fee distributor mock.
        wrongFeeDistributorMock = new WrongFeeDistributorMock();

        /// Setup Mocked Accumulator.
        curveStrategy.setAccumulator(address(mockAccumulator));
        assertEq(address(curveStrategy.accumulator()), address(mockAccumulator));

        /// Skip a week to accrue rewards.
        skip(1 weeks);
    }

    function test_ClaimNativeRewards_WithoutNotify() public {
        address _rewardToken = curveStrategy.curveRewardToken();

        curveStrategy.claimNativeRewards(false);

        uint256 _receiver = ERC20(_rewardToken).balanceOf(address(this));
        uint256 _balance = ERC20(_rewardToken).balanceOf(address(mockAccumulator));
        uint256 _lockerBalance = ERC20(_rewardToken).balanceOf(address(locker));

        /// When `notifyAll` is called, the balance of the accumulato and the locker should be 0.
        assertEq(_receiver, 0);
        assertEq(_lockerBalance, 0);

        /// The Mocked Accumulator transfers the reward to the deployer when `notifyAll` is called.
        /// Since it's not called, the balance of the deployer should be 0 and the balance of the accumulator should be > 0.
        assertGt(_balance, 0);
    }

    function test_ClaimNativeRewards_AndNotify() public {
        address _rewardToken = curveStrategy.curveRewardToken();

        curveStrategy.claimNativeRewards(true);

        uint256 _receiver = ERC20(_rewardToken).balanceOf(address(this));
        uint256 _balance = ERC20(_rewardToken).balanceOf(address(mockAccumulator));
        uint256 _lockerBalance = ERC20(_rewardToken).balanceOf(address(locker));

        /// When `notifyAll` is called, the balance of the accumulato and the locker should be 0.
        assertEq(_balance, 0);
        assertEq(_lockerBalance, 0);

        /// The Mocked Accumulator transfers the reward to the deployer when `notifyAll` is called.
        assertGt(_receiver, 0);
    }

    function test_ClaimNativeRewards_WrongFeeDistributorImplementation() public {
        curveStrategy.setFeeDistributor(address(wrongFeeDistributorMock));

        vm.expectRevert(CurveStrategy.CLAIM_FAILED.selector);
        curveStrategy.claimNativeRewards(true);
    }
}
