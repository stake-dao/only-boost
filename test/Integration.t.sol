// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";

contract IntegrationTest is BaseTest {
    function setUp() public {
        _labelAddress();
        locker = ILocker(LOCKER);

        // --- Fork --- //
        vm.rollFork(FORK_BLOCK_NUMBER_1);

        // --- Deploy Contracts --- //
        vm.startPrank(DEPLOYER_007);

        // Roles
        rolesAuthority = new RolesAuthority(MS_STAKEDAO, Authority(address(0)));

        // Strategies
        curveStrategy = new CurveStrategy(MS_STAKEDAO, rolesAuthority);

        // Fallbacks
        fallbackConvexCurve = new FallbackConvexCurve(MS_STAKEDAO, rolesAuthority, address(curveStrategy)); // Convex Curve
        fallbackConvexFrax = new FallbackConvexFrax(MS_STAKEDAO, rolesAuthority, address(curveStrategy)); // Convex Frax

        // Optimizor
        optimizor =
        new Optimizor(MS_STAKEDAO, rolesAuthority, address(curveStrategy), address(fallbackConvexCurve), address(fallbackConvexFrax));
        vm.stopPrank();

        // --- Setters --- //
        // Set Optimizor on Curve Strategy
        vm.prank(MS_STAKEDAO);
        curveStrategy.setOptimizor(address(optimizor));

        // Set gauges on Curve Strategy
        vm.prank(MS_STAKEDAO);
        curveStrategy.setGauge(address(CRV3), gauges[address(CRV3)]);

        // Set New Curve Strategy as `strategy` on Locker
        vm.prank(locker.governance());
        locker.setStrategy(address(curveStrategy));

        // --- Handle Authority --- //
        // Create roles for `optimizeDeposit` on Optimizor
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(1, address(optimizor), Optimizor.optimizeDeposit.selector, true);

        // Grant `optimizeDeposit` role from Optimizor to Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveStrategy), 1, true);

        // Create roles for `deposit` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(2, address(curveStrategy), CurveStrategy.deposit.selector, true);

        // Grant `deposit` role from Curve Strategy to Vault
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(VAULT_3CRV), 2, true);
    }

    function test_Integration_3Pool() public {
        vm.prank(MS_STAKEDAO);
        VAULT_3CRV.setCurveStrategy(address(curveStrategy));
    }
}
