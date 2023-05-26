// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "test/BaseTest.t.sol";

contract CurveStrategyTest is BaseTest {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public {
        // Create a fork of mainnet, fixing block number for faster testing
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet"), FORK_BLOCK_NUMBER));

        // Deployment contracts
        curveStrategy = new CurveStrategy();
        liquidityGaugeMockCRV3 = new LiquidityGaugeMock();
        liquidityGaugeMockCNC_ETH = new LiquidityGaugeMock();
        liquidityGaugeMockSTETH_ETH = new LiquidityGaugeMock();
        liquidityGaugeMockALUSD_FRAXBP = new LiquidityGaugeMock();
        // End deployment contracts

        // Setup contract
        _afterDeployment();

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(address(curveStrategy));
    }

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////

    // --- Deployment
    function test_DeploymentAddresses() public {
        assertTrue(address(optimizor) != address(0), "1");
        assertTrue(fallbackConvexFrax != FallbackConvexFrax(address(0)), "2");
        assertTrue(fallbackConvexCurve != FallbackConvexCurve(address(0)), "3");
        assertTrue(optimizor.fallbacksLength() != 0, "4");
        assertTrue(fallbackConvexFrax.lastPidsCount() != 0, "5");
        assertTrue(fallbackConvexCurve.lastPidsCount() != 0, "6");
    }

    // --- Deposit
    function test_Deposit_AllOnStakeDAO() public {
        (uint256 partStakeDAO,) = _calculDepositAmount(CRV3, 1, 0);

        _depositTest(CRV3, partStakeDAO, 0, 0);
    }

    function test_Deposit_UsingConvexCurveFallback() public {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _depositTest(CRV3, partStakeDAO, partConvex, 0);
    }

    function test_Deposit_UsingConvexFraxFallBack() public {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);

        _depositTest(ALUSD_FRAXBP, partStakeDAO, partConvex, 0);
    }

    function test_Deposit_UsingConvexFraxSecondDeposit() public {
        // === DEPOSIT PROCESS N°1 === /
        (uint256 partStakeDAO1, uint256 partConvex1) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);
        _deposit(ALUSD_FRAXBP, partStakeDAO1, partConvex1, 0);

        // === DEPOSIT PROCESS N°2 === //
        skip(10 days);
        (uint256 partStakeDAO2, uint256 partConvex2) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);
        rewind(10 days);
        _depositTest(ALUSD_FRAXBP, partStakeDAO2, partConvex2, 10 days);
        // Note: Locking additional liquidity doesn't change ending-timestamp
    }

    // --- Withdraw
    function test_Withdraw_AllFromStakeDAO() public {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, 1, 0);
        _deposit(CRV3, partStakeDAO, partConvex);

        // === WITHDRAW PROCESS === //
        _withdrawTest(CRV3, partStakeDAO, partConvex, 0);
    }

    function test_Withdraw_UsingConvexCurveFallback() public {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);
        _deposit(CRV3, partStakeDAO, partConvex);

        // === WITHDRAW PROCESS === //
        _withdrawTest(CRV3, partStakeDAO / 2, partConvex, 0);
    }

    function test_Withdraw_UsingConvexFraxFallbackPartly() public {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);
        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex);

        // Withdraw ALUSD_FRAXBP
        _withdrawTest(ALUSD_FRAXBP, 0, partConvex / 2, fallbackConvexFrax.lockingIntervalSec());
    }

    function test_Withdraw_UsingConvexFraxFallbackFully() public {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);
        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex);

        // Withdraw ALUSD_FRAXBP
        _withdrawTest(ALUSD_FRAXBP, 0, partConvex, fallbackConvexFrax.lockingIntervalSec());
    }

    // --- Claim
    function test_Claim_NoExtraRewards() public {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, 1, 0);

        _deposit(CRV3, partStakeDAO, partConvex);
        _claimLiquidLockerTest(CRV3, 1 weeks, ERC20(address(0)));
    }

    function test_Claim_ExtraRewardsWithReceiver() public {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CNC_ETH, 1, 0);

        _deposit(CNC_ETH, partStakeDAO, partConvex);
        _claimLiquidLockerTest(CNC_ETH, 1 weeks, CNC);
    }

    function test_ClaimExtraRewardsWithoutReceiver() public {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(STETH_ETH, 1, 0);

        _deposit(STETH_ETH, partStakeDAO, partConvex);
        _claimLiquidLockerTest(STETH_ETH, 1 weeks, LDO);
    }

    function test_Claim3CRV() public {
        // Cache balance before
        uint256 balanceBeforeAC = CRV3.balanceOf(address(curveStrategy.accumulator()));

        // Timejump 1 week
        skip(1 weeks);

        // === CLAIM 3CRV PROCESS === //
        // No need to notify all, because it will call back the same exact process
        curveStrategy.claim3Crv(false);

        // === ASSERTIONS === //
        //Assertion 1: Check test accumulator received token
        assertGt(CRV3.balanceOf(address(curveStrategy.accumulator())), balanceBeforeAC, "1");
    }

    function test_Claim_ConvexCurveRewards() public {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _deposit(CRV3, partStakeDAO, partConvex, 0);

        skip(1 weeks);
        curveStrategy.claim(address(CRV3));
    }

    function test_Claim_ConvexFraxRewards() public {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);

        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex, 0);

        skip(1 weeks);
        curveStrategy.claim(address(ALUSD_FRAXBP));
    }
}
