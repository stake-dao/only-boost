// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";

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

    function test_Integration_Manipulate_Cache() public {
        // Cache the address of the token
        ERC20 token = CRV3;

        // Get the initial balances and amounts
        uint256 lockerGaugeBalance = ERC20(gauges[address(token)]).balanceOf(LOCKER);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);
        uint256 amountStakeDAO =
            optimizor.optimalAmount(gauges[address(token)], veCRVStakeDAO, false) - lockerGaugeBalance;
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
}
