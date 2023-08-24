// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";
import {VLCVX} from "test/interfaces/IVLCVX.sol";

interface IGauge {
    function balanceOf(address) external view returns (uint256);
    function withdraw(uint256) external;
    function deposit(uint256) external;
}

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
        fallbackConvexCurve = new ConvexFallback(MS_STAKEDAO, rolesAuthority, address(curveStrategy)); // Convex Curve

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
        rolesAuthority.setRoleCapability(3, address(fallbackConvexCurve), BaseFallback.deposit.selector, true);

        // 3. Grant `deposit` role from Fallback Convex Curve to Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveStrategy), 3, true);
    }

    function test_Integration_3Pool() public {
        _testSwitchStrategy(address(CRV3));
    }

    function test_Integration_SDT_ETH() public {
        _testSwitchStrategy(address(SDT_ETH));
    }

    function test_Integration_UZD_FRAXBP() public {
        _testSwitchStrategy(address(UZD_FRAXBP));
    }

    function _testSwitchStrategy(address token) internal {
        // Set gauges on Curve Strategy
        vm.prank(MS_STAKEDAO);
        curveStrategy.setGauge(token, gauges[token]);

        // Get LL LP Balance
        uint256 balanceBefore = ERC20(gauges[token]).balanceOf(LOCKER);
        require(vaults[token] != address(0), "Vault not set");
        uint256 balanceVault = IVault(vaults[token]).available();

        // Set new strategy
        vm.prank(MS_STAKEDAO);
        IVault(vaults[token]).setCurveStrategy(address(curveStrategy));

        assertEq(balanceBefore + balanceVault, _totalBalance(token));
    }

    function test_Integration_Manipulate_Cache() public {
        // Cache the address of the token
        ERC20 token = CRV3;

        // Get the initial balances and amounts
        uint256 lockerGaugeBalance = ERC20(gauges[address(token)]).balanceOf(LOCKER);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);
        uint256 amountStakeDAO = optimizor.optimalAmount(gauges[address(token)], veCRVStakeDAO) - lockerGaugeBalance;
        uint256 amountFallbackCurve = 5_000_000e18;
        uint256 amountTotal = amountStakeDAO + amountFallbackCurve;
        uint256 balanceConvex = IGauge(GAUGE_CRV3).balanceOf(LOCKER_CONVEX);

        // Set gauges on Curve Strategy and set the new strategy
        vm.startPrank(MS_STAKEDAO);
        curveStrategy.setGauge(address(token), gauges[address(token)]);
        VAULT_3CRV.setCurveStrategy(address(curveStrategy));
        optimizor.toggleUseLastOptimization();
        vm.stopPrank();

        // Prank as MS_STAKEDAO and get the optimized amounts before manipulation
        vm.prank(MS_STAKEDAO);
        (, uint256[] memory resultsBefore) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], amountTotal);

        // Withdraw from the Convex gauge and make a deposit via StakeDAO's CurveStrategy contract
        vm.startPrank(LOCKER_CONVEX);
        IGauge(GAUGE_CRV3).withdraw(balanceConvex);
        token.approve(address(VAULT_3CRV), amountStakeDAO);
        VAULT_3CRV.deposit(address(LOCKER_CONVEX), amountStakeDAO, false);
        vm.stopPrank();

        // Trigger cache and redeposit into the Convex gauge
        vm.prank(MS_STAKEDAO);
        optimizor.optimizeDeposit(address(token), gauges[address(token)], amountStakeDAO);
        vm.startPrank(LOCKER_CONVEX);
        token.approve(address(GAUGE_CRV3), balanceConvex - amountStakeDAO);
        IGauge(GAUGE_CRV3).deposit(balanceConvex - amountStakeDAO);
        vm.stopPrank();

        // Get the optimized amounts after manipulation
        vm.prank(MS_STAKEDAO);
        (, uint256[] memory resultsAfter) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], amountTotal);

        // The optimized amounts before and after should not be the same as we don't use the cache
        assert(resultsBefore[0] != resultsAfter[0]);
        assert(resultsBefore[1] != resultsAfter[1]);
    }

    /// @dev https://github.com/stake-dao/strategy-optimizor/issues/4 + https://github.com/stake-dao/strategy-optimizor/issues/27
    /// @notice The test function should take into account potential vulnerabilities:
    /// 1. An attacker can force out all but the smallest CVX staker, skyrocketing the boost value. This would result in a scenario where Convex benefits outweigh StakeDAO's, causing all deposited LP tokens to be directed towards Convex.
    /// 2. If an attacker forces out all CVX stakers, the lockedSupply() would become 0, leading to a division by zero error in the boost calculation. This would result in the Optimizor failing to work, effectively 'bricking' it.
    function test_Integration_KickExpiredLocks() public {
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
