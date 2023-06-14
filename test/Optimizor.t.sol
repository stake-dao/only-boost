// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

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
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet"), FORK_BLOCK_NUMBER_1));

        // Deploy Optimizor
        optimizor = new Optimizor(address(this), Authority(address(0)), address(0), address(0), address(0));
        // End for deployment

        fallbackConvexFrax = optimizor.fallbackConvexFrax();
        fallbackConvexCurve = optimizor.fallbackConvexCurve();
    }

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////
    // --- Stake DAO Optimization
    function test_Optimization1() public view {
        optimizor.optimization1(gauges[address(EUR3)], true);
    }

    function test_Optimization2() public view {
        optimizor.optimization2(gauges[address(EUR3)], true);
    }

    function test_Optimization3() public view {
        optimizor.optimization3(gauges[address(EUR3)], true);
    }

    /// --- Opitmitzation on deposit
    function test_OptimizationOnDeposit_StakeDAOAndConvexCurve() public {
        // Cache the address of the token
        ERC20 token = CRV3;

        // Get the balance of the locker in the gauge
        uint256 lockerGaugeBalance = ERC20(gauges[address(token)]).balanceOf(LOCKER_STAKEDAO);

        uint256 amountStakeDAO = optimizor.optimization1(gauges[address(token)], false) - lockerGaugeBalance;
        uint256 amountFallbackCurve = 5_000_000e18;
        uint256 amountFallbackFrax = 0;
        uint256 amountTotal = amountStakeDAO + amountFallbackCurve + amountFallbackFrax;

        // Get the optimized amounts
        (address[] memory recipients, uint256[] memory results) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], amountTotal);

        // Assertions
        assertEq(results.length, 3, "1");
        assertEq(recipients.length, 3, "2");
        assertEq(results[0], amountStakeDAO, "3");
        assertEq(results[1], amountFallbackCurve, "4");
        assertEq(results[2], amountFallbackFrax, "5");
    }

    function test_OptimizationOnDeposit_StakeDAOAndConvexFrax() public {
        // Cache the address of the token
        ERC20 token = ALUSD_FRAXBP;

        // Get the balance of the locker in the gauge
        uint256 lockerGaugeBalance = ERC20(gauges[address(token)]).balanceOf(LOCKER_STAKEDAO);

        uint256 amountStakeDAO = optimizor.optimization1(gauges[address(token)], true) - lockerGaugeBalance;
        uint256 amountFallbackCurve = 0;
        uint256 amountFallbackFrax = 5_000_000e18;
        uint256 amountTotal = amountStakeDAO + amountFallbackCurve + amountFallbackFrax;

        // Get the optimized amounts
        (address[] memory recipients, uint256[] memory results) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], amountTotal);

        // Assertions
        assertEq(results.length, 3, "1");
        assertEq(recipients.length, 3, "2");
        assertEq(results[0], amountStakeDAO, "3");
        assertEq(results[1], amountFallbackCurve, "4");
        assertEq(results[2], amountFallbackFrax, "5");
    }

    function test_Min() public {
        // Only coverage purpose
        assertEq(optimizor.min(1, 2), 1);
        assertEq(optimizor.min(2, 1), 1);
    }

    function test_RescueToken() public {
        deal(address(CRV), address(optimizor), 100);

        assertEq(CRV.balanceOf(address(this)), 0);
        optimizor.rescueToken(address(CRV), address(this), 100);
        assertEq(CRV.balanceOf(address(this)), 100);
    }
}
