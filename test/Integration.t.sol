// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";
import {VLCVX} from "test/interfaces/IVLCVX.sol";

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

    ////////////////////////////////////////////////////////////////

    /// --- Audit - Attack vectors

    ///////////////////////////////////////////////////////////////

    /// @dev https://github.com/stake-dao/strategy-optimizor/issues/4 + https://github.com/stake-dao/strategy-optimizor/issues/27

    /// @notice The test function should take into account potential vulnerabilities:

    /// 1. An attacker can force out all but the smallest CVX staker, skyrocketing the boost value. This would result in a scenario where Convex benefits outweigh StakeDAO's, causing all deposited LP tokens to be directed towards Convex.

    /// 2. If an attacker forces out all CVX stakers, the lockedSupply() would become 0, leading to a division by zero error in the boost calculation. This would result in the Optimizor failing to work, effectively 'bricking' it.

    function testZach__KickExpiredLocks() public {
        VLCVX vlcvx = VLCVX(0x72a19342e8F1838460eBFCCEf09F6585e32db86E);

        address bob = address(0xB0B);

        deal(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, bob, 10e18); // Get CVX

        // Lock
        vm.startPrank(bob);

        ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B).approve(address(vlcvx), 10e18);

        vlcvx.lock(bob, 10e18, 0);

        vm.stopPrank();

        // Wait for lock to expire

        vm.warp(block.timestamp + 86400 * 7 * 17);

        uint256 lockedSupplyBefore = vlcvx.lockedSupply();

        uint256 boostBefore = _calculateBoost();

        (uint256 totalBefore, uint256 unlockableBefore,,) = vlcvx.lockedBalances(bob);

        vm.prank(bob);
        vlcvx.processExpiredLocks(false);

        (uint256 totalAfter, uint256 unlockableAfter,,) = vlcvx.lockedBalances(bob);

        uint256 lockedSupplyAfter = vlcvx.lockedSupply();

        uint256 boostAfter = _calculateBoost();

        console.log(lockedSupplyBefore, lockedSupplyAfter);

        console.log(boostBefore, boostAfter);

        assertEq(totalBefore, 10e18);
        assertEq(unlockableBefore, 10e18);
        assertEq(totalAfter, 0);
        assertEq(unlockableAfter, 0);

        assertApproxEqAbs(lockedSupplyBefore, lockedSupplyAfter, 1e19); // Locked supply should be not that much different
        assertApproxEqAbs(boostBefore, boostAfter, 2e10); // Boost should be not that much different
    }

    /// @notice Reproduce boost calculation from Optimizor

    function _calculateBoost() internal view returns (uint256 boost) {
        // Copied from Optimizor

        address LOCKER_CVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

        address LOCKER_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

        address LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

        ERC20 CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);

        uint256 cvxTotal = CVX.totalSupply();

        uint256 vlCVXTotal = VLCVX(LOCKER_CVX).lockedSupply();

        boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);
    }
}
