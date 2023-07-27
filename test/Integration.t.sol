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

        // Optimizor
        optimizor = new Optimizor(MS_STAKEDAO, rolesAuthority, address(curveStrategy), address(fallbackConvexCurve));
        vm.stopPrank();

        // --- Setters --- //
        // Set Optimizor on Curve Strategy
        vm.prank(MS_STAKEDAO);
        curveStrategy.setOptimizor(address(optimizor));

        // Set New Curve Strategy as `strategy` on Locker
        vm.prank(locker.governance());
        locker.setStrategy(address(curveStrategy));

        // --- Handle Authority --- //
        // 1. Create roles for `optimizeDeposit` on Optimizor
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(1, address(optimizor), Optimizor.optimizeDeposit.selector, true);

        // 1. Grant `optimizeDeposit` role from Optimizor to Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveStrategy), 1, true);

        // 2. Create roles for `deposit` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(2, address(curveStrategy), CurveStrategy.deposit.selector, true);

        // 2. Grant `deposit` role from Curve Strategy to Vault
        vm.startPrank(MS_STAKEDAO);
        rolesAuthority.setUserRole(vaults[address(CRV3)], 2, true);
        rolesAuthority.setUserRole(vaults[address(SDT_ETH)], 2, true);
        rolesAuthority.setUserRole(vaults[address(UZD_FRAXBP)], 2, true);
        vm.stopPrank();

        // 3. Create roles for `deposit` on Fallback Convex Curve
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(3, address(fallbackConvexCurve), FallbackConvexCurve.deposit.selector, true);

        // 3. Grant `deposit` role from Fallback Convex Curve to Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveStrategy), 3, true);
    }

    function test_Integration_3Pool() public {
        // Set gauges on Curve Strategy
        vm.prank(MS_STAKEDAO);
        curveStrategy.setGauge(address(CRV3), gauges[address(CRV3)]);

        // Set new strategy
        vm.prank(MS_STAKEDAO);
        VAULT_SDCRV_CRV.setCurveStrategy(address(curveStrategy));
    }

    function test_Integration_SDT_ETH() public {
        // Set gauges on Curve Strategy
        vm.prank(MS_STAKEDAO);
        curveStrategy.setGauge(address(SDT_ETH), gauges[address(SDT_ETH)]);

        // Set new strategy
        vm.prank(MS_STAKEDAO);
        VAULT_SDT_ETH.setCurveStrategy(address(curveStrategy));
    }

    function test_Integration_UZD_FRAXBP() public {
        // Set gauges on Curve Strategy
        vm.prank(MS_STAKEDAO);
        curveStrategy.setGauge(address(UZD_FRAXBP), gauges[address(UZD_FRAXBP)]);

        // Set new strategy
        vm.prank(MS_STAKEDAO);
        VAULT_UZD_FRAXBP.setCurveStrategy(address(curveStrategy));
    }
}
