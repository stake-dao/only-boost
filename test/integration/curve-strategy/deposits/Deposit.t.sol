// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/Base.t.sol";

abstract contract Deposit_Test is Base_Test {
    constructor(address _asset, address _gauge) Base_Test(_asset, _gauge) {}

    function setUp() public override {
        vm.rollFork({blockNumber: 18_127_824});
        Base_Test.setUp();

        /// Setup Strategy
        curveStrategy.setGauge({token: address(asset), gauge: address(gauge)});

        /// Setup Deposit
        deal(address(asset), address(this), 1000e18);
        asset.approve(address(curveStrategy), type(uint256).max);
    }

    function test_RevertWhen_AssetNotAssociatedWithGauge() public {
        mockToken.mint(address(this), 1000e18);
        mockToken.approve(address(curveStrategy), 1000e18);

        vm.expectRevert(Strategy.ADDRESS_NULL.selector);
        curveStrategy.deposit({token: address(mockToken), amount: 1000e18});
    }

    function test_RevertWhen_CallerUnauthorized() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("UNAUTHORIZED");
        curveStrategy.deposit({token: address(asset), amount: 1000e18});
    }

    function test_Deposit_AssetNotAvailableOnConvex() public {
        /// Snapshot balance
        uint256 _balance = gauge.balanceOf(address(locker));

        /// Check that the fallback is active on Convex
        assertTrue(convexFallback.isActive(address(asset)));

        /// Since it's active, we'll mock call on fallback that return false for `isActive`
        vm.mockCall(address(convexFallback), abi.encodeWithSignature("isActive(address)", asset), abi.encode(false));

        curveStrategy.deposit({token: address(asset), amount: 1000e18});

        assertEq(asset.balanceOf(LOCKER), 0);
        assertEq(asset.balanceOf(address(this)), 0);
        assertEq(asset.balanceOf(address(curveStrategy)), 0);
        assertEq(asset.balanceOf(address(convexFallback)), 0);

        assertEq(gauge.balanceOf(LOCKER) - _balance, 1000e18);
    }

    function test_Deposit_AssetSplitBetweenSDAndConvex() public {
        /// Check for max boost
        if (_checkForConvexMaxBoost(address(gauge))) {
            /// Mock Calls to `cancel` max boost.
            /// This call is made only to check if the user has max boost.
            vm.mockCall(
                address(gauge), abi.encodeWithSignature("working_balances(address)", CONVEX_VOTER_PROXY), abi.encode(0)
            );
        }

        /// Get Optimal Deposit on Stake DAO.
        uint256 _optimalDeposit = _getDepositAmount(address(gauge));

        /// Deal the difference left to get the optimal deposit
        deal(address(asset), address(this), _optimalDeposit);
        assertEq(asset.balanceOf(address(this)), _optimalDeposit);

        uint256 _balance = gauge.balanceOf(address(locker));

        uint256 _expectedSDDeposit = _optimalDeposit > _balance ? _optimalDeposit - _balance : 0;
        uint256 _expectedFallbackBalance = _optimalDeposit - _expectedSDDeposit;

        curveStrategy.deposit({token: address(asset), amount: _optimalDeposit});

        assertEq(asset.balanceOf(LOCKER), 0);
        assertEq(asset.balanceOf(address(this)), 0);
        assertEq(asset.balanceOf(address(curveStrategy)), 0);
        assertEq(asset.balanceOf(address(convexFallback)), 0);

        /// If over the balance, then it shouldn't be deposited on Stake DAO.
        assertEq(gauge.balanceOf(LOCKER), _optimalDeposit > _balance ? _optimalDeposit : _balance);
        assertGt(convexFallback.balanceOf(address(asset)), 0);

        /// If over the balance, then _expectedFallbackBalance should be equal to the _optimalDeposit.
        assertEq(convexFallback.balanceOf(address(asset)), _expectedFallbackBalance);
    }

    /// @dev It should skip Stake DAO deposit if Convex has max boost.
    function test_Deposit_ConvexMaxBoost() public {
        uint256 _balance;

        /// Check for max boost
        if (!_checkForConvexMaxBoost(address(gauge))) {
            /// Mock Calls to `simulate` max boost.
            _balance = ILiquidityGauge(address(gauge)).balanceOf(CONVEX_VOTER_PROXY);
            vm.mockCall(
                address(gauge),
                abi.encodeWithSignature("working_balances(address)", CONVEX_VOTER_PROXY),
                abi.encode(_balance)
            );

            assertTrue(_checkForConvexMaxBoost(address(gauge)));
        }

        /// Get Optimal Deposit on Stake DAO.
        uint256 _optimalDeposit = _getDepositAmount(address(gauge));

        /// Deal the difference left to get the optimal deposit
        deal(address(asset), address(this), _optimalDeposit);
        assertEq(asset.balanceOf(address(this)), _optimalDeposit);

        _balance = gauge.balanceOf(address(locker));
        curveStrategy.deposit({token: address(asset), amount: _optimalDeposit});

        assertEq(asset.balanceOf(address(this)), 0);
        assertEq(asset.balanceOf(address(curveStrategy)), 0);
        assertEq(asset.balanceOf(address(convexFallback)), 0);

        assertEq(gauge.balanceOf(LOCKER), _balance);

        assertGt(convexFallback.balanceOf(address(asset)), 0);
        assertEq(convexFallback.balanceOf(address(asset)), _optimalDeposit);
    }
}