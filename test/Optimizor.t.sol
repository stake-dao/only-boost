// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";

contract OptimizorTest is BaseTest {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public {
        // 17136445 : 27 April 2023 08:51:23 UTC
        // 17136745 : 27 April 2023 09:51:47 UTC
        // 17137000 : 27 April 2023 10:43:59 UTC
        // Create Fork
        vm.rollFork(FORK_BLOCK_NUMBER_1);

        // Deploy Optimizor
        fallbackConvexCurve = new ConvexFallback(address(this), rolesAuthority, payable(address(curveStrategy)));
        optimizor =
            new Optimizor(address(this), Authority(address(0)), payable(address(0)), address(fallbackConvexCurve));
        // End for deployment
    }

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////
    // --- Stake DAO Optimization
    function test_Optimization() public view {
        // Get veCRVStakeDAO balance
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);
        optimizor.optimalAmount(gauges[address(EUR3)], veCRVStakeDAO);
    }

    /// --- Optimization on deposit
    function test_OptimizationOnDeposit_StakeDAOAndConvexCurve() public {
        // Cache the address of the token
        ERC20 token = CRV3;

        // Get the balance of the locker in the gauge
        uint256 lockerGaugeBalance = ERC20(gauges[address(token)]).balanceOf(LOCKER);
        // Get veCRVStakeDAO balance
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);
        uint256 amountStakeDAO = optimizor.optimalAmount(gauges[address(token)], veCRVStakeDAO) - lockerGaugeBalance;
        uint256 amountFallbackCurve = 5_000_000e18;
        uint256 amountTotal = amountStakeDAO + amountFallbackCurve;

        // Get the optimized amounts
        (address[] memory recipients, uint256[] memory results) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], amountTotal);

        // Assertions
        assertEq(results.length, 2, "1");
        assertEq(recipients.length, 2, "2");
        assertEq(results[1], amountStakeDAO, "3");
        assertEq(results[0], amountFallbackCurve, "4");
    }

    function test_RescueToken() public {
        deal(address(CRV), address(optimizor), 100);

        assertEq(CRV.balanceOf(address(this)), 0);
        optimizor.rescueERC20(address(CRV), address(this), 100);
        assertEq(CRV.balanceOf(address(this)), 100);
    }
}
