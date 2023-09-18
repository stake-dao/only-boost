// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/Base.t.sol";

abstract contract Withdrawal_Test is Base_Test {
    constructor(address _asset, address _gauge) Base_Test(_asset, _gauge) {}

    function setUp() public override {
        vm.rollFork({blockNumber: 18_127_824});
        Base_Test.setUp();

        /// Setup Strategy
        curveStrategy.setGauge({token: address(asset), gauge: address(gauge)});

        asset.approve(address(curveStrategy), type(uint256).max);
    }

    function test_RevertWhen_AssetNotAssociatedWithGauge() public {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.withdraw({token: address(mockToken), amount: 1000e18});
    }

    function test_RevertWhen_CallerUnauthorized() public {
        /// Make sure the amount is big enough to split between fallback and Stake DAO.
        _createDeposit({_amount: 1_000_000e18, _split: true, _resetSD: true});

        vm.prank(address(0xBEEF));
        vm.expectRevert("UNAUTHORIZED");
        curveStrategy.withdraw({token: address(asset), amount: 1000e18});
    }

    /// @dev It should always withdraw from the fallback first before withdrawing from Stake DAO.
    function test_Withdraw_AmountFromFallback() public {
        /// Make sure the amount is big enough to split between fallback and Stake DAO.
        _createDeposit({_amount: 1_000_000e18, _split: true, _resetSD: true});

        uint256 _fallbackBalance = convexFallback.balanceOf(address(asset));
        assertGt(_fallbackBalance, 0);

        /// Snapshot balance
        uint256 _balance = gauge.balanceOf(address(locker));

        /// Withdraw 1000e18 from the strategy.
        curveStrategy.withdraw({token: address(asset), amount: 1000e18});

        assertEq(gauge.balanceOf(LOCKER), _balance);
        assertEq(convexFallback.balanceOf(address(asset)), _fallbackBalance - 1000e18);

        assertEq(asset.balanceOf(address(curveStrategy)), 0);
        assertEq(asset.balanceOf(address(this)), 1000e18);
    }

    /// @dev Withdraw a huge amount where Convex doesn't have enough balance.
    function test_Withdraw_SplitFromStakeDAOAndFallback() public {
        /// Make sure the amount is big enough to split between fallback and Stake DAO.
        _createDeposit({_amount: 1_000_000e18, _split: true, _resetSD: true});

        uint256 _balance = gauge.balanceOf(address(locker));
        uint256 _fallbackBalance = convexFallback.balanceOf(address(asset));

        assertGt(_balance, 0);
        assertGt(_fallbackBalance, 0);

        /// Withdraw 1000e18 from the strategy.
        curveStrategy.withdraw({token: address(asset), amount: 1_000_000e18});

        assertEq(gauge.balanceOf(LOCKER), 0);
        assertEq(convexFallback.balanceOf(address(asset)), 0);

        assertEq(asset.balanceOf(address(curveStrategy)), 0);
        assertEq(asset.balanceOf(address(this)), 1_000_000e18);
    }
}
