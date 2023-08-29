// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";

contract CrvDepositorTest is BaseTest {
    using FixedPointMathLib for uint256;

    ISdToken public constant SD_CRV = ISdToken(0xD1b5651E55D4CeeD36251c61c50C889B36F6abB5);
    ILiquidityGauge public constant GAUGE_SDCRV = ILiquidityGauge(0x7f50786A0b15723D741727882ee99a0BF34e3466);

    function setUp() public {
        _labelAddress();

        // --- Fork --- //
        vm.rollFork(FORK_BLOCK_NUMBER_1);

        // --- Deploy Contracts --- //
        vm.startPrank(MS_STAKEDAO);

        // Roles
        rolesAuthority = new RolesAuthority(MS_STAKEDAO, Authority(address(0)));

        // Curve Strategy
        curveStrategy = new CurveStrategy(MS_STAKEDAO, rolesAuthority);

        // CRV Depositor
        crvDepositor =
        new CrvDepositor(address(CRV), LOCKER, address(SD_CRV), MS_STAKEDAO, payable(address(curveStrategy)), rolesAuthority);

        vm.stopPrank();

        // --- Setters --- //
        // Set new depositor as operator of sdToken
        vm.prank(SD_CRV.operator());
        SD_CRV.setOperator(address(crvDepositor));

        // Set gauge on depositor
        vm.prank(MS_STAKEDAO);
        crvDepositor.setGauge(address(GAUGE_SDCRV));

        // Max approval for depositor to spend CRV from ALICE
        vm.prank(ALICE);
        CRV.approve(address(crvDepositor), type(uint256).max);

        // Give strategy roles from depositor to new strategy
        vm.prank(ILocker(LOCKER).governance());
        ILocker(LOCKER).setStrategy(payable(address(curveStrategy)));

        // --- Roles --- //
        // 1. Create roles for `increaseAmount` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(
            1, payable(address(curveStrategy)), CurveStrategy.increaseAmount.selector, true
        );

        // 1. Grant `increaseAmount` role from Curve Strategy to crvDepositor
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(crvDepositor), 1, true);

        // 2. Create roles for `increaseUnlockTime` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(
            2, payable(address(curveStrategy)), CurveStrategy.increaseUnlockTime.selector, true
        );

        // 2. Grant `increaseUnlockTime` role from Curve Strategy to crvDepositor
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(crvDepositor), 2, true);

        _labelContract();
    }

    function test_Deposit_NoLock_NoStake() public {
        uint256 amount = 1_000e18;
        deal(address(CRV), ALICE, amount);

        vm.prank(ALICE);
        crvDepositor.deposit(amount, false, false, ALICE);

        uint256 incentive = amount.mulDivDown(crvDepositor.lockIncentive(), crvDepositor.FEE_DENOMINATOR());

        assertEq(ERC20(address(SD_CRV)).balanceOf(ALICE), amount - incentive);
    }

    function test_Deposit_NoLock_Stake() public {
        uint256 amount = 1_000e18;
        deal(address(CRV), ALICE, amount);

        vm.prank(ALICE);
        crvDepositor.deposit(amount, false, true, ALICE);

        uint256 incentive = amount.mulDivDown(crvDepositor.lockIncentive(), crvDepositor.FEE_DENOMINATOR());

        assertEq(GAUGE_SDCRV.balanceOf(ALICE), amount - incentive);
    }

    function test_Deposit_Lock_NoStake_WithoutIncentives() public {
        uint256 amount = 1_000e18;
        deal(address(CRV), ALICE, amount);

        vm.prank(ALICE);
        crvDepositor.deposit(amount, true, false, ALICE);

        assertEq(ERC20(address(SD_CRV)).balanceOf(ALICE), amount);
    }

    function test_Deposit_Lock_NoStake_WithIncentives() public {
        // TODO: Test with incentives
    }

    function test_IncreaseUnlockTime() public {
        uint256 endBefore = IVeCRV(VE_CRV).locked(LOCKER).end;
        uint256 endAfter = endBefore + 7 days;

        skip(30 weeks); // To avoid being above the max lock time
        vm.prank(MS_STAKEDAO);
        crvDepositor.increaseUnlockTime(endAfter);

        assertEq(IVeCRV(VE_CRV).locked(LOCKER).end, endAfter, "0");
    }
}
