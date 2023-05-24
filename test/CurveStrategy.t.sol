// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "test/BaseTest.t.sol";

contract CurveStrategyTest is BaseTest {
    using SafeTransferLib for ERC20;

    Optimizor public optimizor;
    CurveStrategy public curveStrategy;
    FallbackConvexFrax public fallbackConvexFrax;
    FallbackConvexCurve public fallbackConvexCurve;

    LiquidityGaugeMock public liquidityGaugeMockCRV3;
    LiquidityGaugeMock public liquidityGaugeMockCNC_ETH;
    LiquidityGaugeMock public liquidityGaugeMockSTETH_ETH;
    LiquidityGaugeMock public liquidityGaugeMockALUSD_FRAXBP;

    ILocker public locker;
    IBoosterConvexFrax public boosterConvexFrax;
    IBoosterConvexCurve public boosterConvexCurve;
    IPoolRegistryConvexFrax public poolRegistryConvexFrax;

    //////////////////////////////////////////////////////
    /// --- SETUP --- ///
    //////////////////////////////////////////////////////
    function setUp() public {
        // Create a fork of mainnet, fixing block number for faster testing
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet"), 17286900));

        // Deployment contracts
        curveStrategy = new CurveStrategy();
        liquidityGaugeMockCRV3 = new LiquidityGaugeMock();
        liquidityGaugeMockCNC_ETH = new LiquidityGaugeMock();
        liquidityGaugeMockSTETH_ETH = new LiquidityGaugeMock();
        liquidityGaugeMockALUSD_FRAXBP = new LiquidityGaugeMock();
        // End deployment contracts

        // Setup contracts
        optimizor = curveStrategy.optimizor();
        fallbackConvexFrax = optimizor.fallbackConvexFrax();
        fallbackConvexCurve = optimizor.fallbackConvexCurve();
        locker = ILocker(LOCKER_STAKEDAO);
        boosterConvexFrax = IBoosterConvexFrax(fallbackConvexFrax.boosterConvexFrax());
        boosterConvexCurve = IBoosterConvexCurve(fallbackConvexCurve.boosterConvexCurve());
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(fallbackConvexFrax.poolRegistryConvexFrax());

        // Setup contract
        _addAllGauge();
        _setFees();

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(address(curveStrategy));

        // Label contracts
        _labelContract();
    }

    //////////////////////////////////////////////////////
    /// --- TESTS --- ///
    //////////////////////////////////////////////////////

    // --- Deployment --- //
    function test_DeploymentAddresses() public {
        assertTrue(address(optimizor) != address(0), "1");
        assertTrue(fallbackConvexFrax != FallbackConvexFrax(address(0)), "2");
        assertTrue(fallbackConvexCurve != FallbackConvexCurve(address(0)), "3");
        assertTrue(optimizor.fallbacksLength() != 0, "4");
        assertTrue(fallbackConvexFrax.lastPidsCount() != 0, "5");
        assertTrue(fallbackConvexCurve.lastPidsCount() != 0, "6");
    }

    // --- Deposit --- //
    function test_Deposit_AllOnStakeDAO() public {
        // Cache balance before
        uint256 balanceBefore = ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO));

        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO,) = _deposit(CRV3, 1, 0);

        // === ASSERTIONS === //
        // Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO)) - balanceBefore, partStakeDAO, "1");
    }

    function test_Deposit_UsingConvexCurveFallback() public {
        // Cache balance before
        uint256 balanceBeforeStakeDAO = ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO));
        uint256 balanceBeforeConvex = ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_CONVEX));

        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _deposit(CRV3, MAX, 1);

        // Get all needed infos for following assertions
        BaseFallback.PidsInfo memory pidsInfo = fallbackConvexCurve.getPid(address(CRV3));
        (,,, address crvRewards,,) = boosterConvexCurve.poolInfo(pidsInfo.pid);

        // === ASSERTIONS === //
        // Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO)) - balanceBeforeStakeDAO, partStakeDAO, "1");
        // Assertion 2: Check Gauge balance of Convex Liquid Locker
        assertEq(ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_CONVEX)) - balanceBeforeConvex, partConvex, "2");
        // Assertion 3: Check Convex balance of Curve Strategy
        assertEq(ERC20(crvRewards).balanceOf(address(fallbackConvexCurve)), partConvex, "3");
    }

    function test_Deposit_UsingConvexFraxFallBack() public {
        // Cache balance before
        uint256 balanceBeforeStakeDAO = ERC20(GAUGE_ALUSD_FRAXBP).balanceOf(address(LOCKER_STAKEDAO));

        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _deposit(ALUSD_FRAXBP, MAX, 1);

        // Get all needed infos for following assertions
        BaseFallback.PidsInfo memory pidsInfo = fallbackConvexFrax.getPid(address(ALUSD_FRAXBP));
        address personalVault = poolRegistryConvexFrax.vaultMap(pidsInfo.pid, address(fallbackConvexFrax));
        (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pidsInfo.pid);

        // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
        // and the last one is emptyed. So we need to get the last one.
        uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault);
        IFraxUnifiedFarm.LockedStake memory infos =
            IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[lockCount - 1];

        // === ASSERTIONS === //
        //Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(
            ERC20(GAUGE_ALUSD_FRAXBP).balanceOf(address(LOCKER_STAKEDAO)) - balanceBeforeStakeDAO, partStakeDAO, "1"
        );
        // Assertion 2: Check personal vault created
        assertTrue(poolRegistryConvexFrax.vaultMap(pidsInfo.pid, address(fallbackConvexFrax)) != address(0), "2");
        // Assertion 3: Check value for personal vault, such as liquidity, kek_id, timestamps, lock_multiplier
        assertEq(infos.liquidity, partConvex, "3");
        assertEq(infos.kek_id, fallbackConvexFrax.kekIds(fallbackConvexFrax.vaults(pidsInfo.pid)), "4"); // kek_id is the same as vault
        assertEq(infos.start_timestamp, block.timestamp, "5");
        assertEq(infos.ending_timestamp, block.timestamp + fallbackConvexFrax.lockingIntervalSec(), "6");
        assertGt(infos.lock_multiplier, 0, "7");
    }

    function test_Deposit_UsingConvexFraxSecondDeposit() public {
        // === DEPOSIT PROCESS N°1 === /
        (uint256 partStakeDAO1, uint256 partConvex1) = _deposit(ALUSD_FRAXBP, MAX, 1);

        // Cache timestamp before
        uint256 timestampBefore = block.timestamp;
        // Set timejump interval
        uint256 timejumpInterval = 10 days;
        // Timejump
        skip(timejumpInterval);

        // === DEPOSIT PROCESS N°2 === //
        (, uint256 partConvex2) = _deposit(ALUSD_FRAXBP, MAX, 1);

        // Get all needed infos for following assertions
        BaseFallback.PidsInfo memory pidsInfo = fallbackConvexFrax.getPid(address(ALUSD_FRAXBP));
        address personalVault = poolRegistryConvexFrax.vaultMap(pidsInfo.pid, address(fallbackConvexFrax));
        (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pidsInfo.pid);

        // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
        // and the last one is emptyed. So we need to get the last one.
        uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault);
        IFraxUnifiedFarm.LockedStake memory infos =
            IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[lockCount - 1];

        // === ASSERTIONS === //
        //Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertGt(ERC20(GAUGE_ALUSD_FRAXBP).balanceOf(address(LOCKER_STAKEDAO)), partStakeDAO1, "1");
        // Assertion 2: Check value for personal vault, such as liquidity, kek_id, timestamps, lock_multiplier
        assertEq(IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault), 1, "2");
        assertEq(infos.liquidity, partConvex1 + partConvex2, "3");
        assertEq(infos.kek_id, fallbackConvexFrax.kekIds(fallbackConvexFrax.vaults(pidsInfo.pid)), "4"); // kek_id is the same as vault
        assertEq(infos.start_timestamp, timestampBefore, "5");
        assertEq(infos.ending_timestamp, timestampBefore + fallbackConvexFrax.lockingIntervalSec(), "6");
        assertGt(infos.lock_multiplier, 0, "7");
        // Note: Locking additional liquidity doesn't change ending-timestamp
    }

    // --- Withdraw --- //
    function test_Withdraw_AllFromStakeDAO() public {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO,) = _deposit(CRV3, 1, 0);

        // Check Stake DAO balance before withdraw
        uint256 balanceBeforeStakeDAO = ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO));

        // === WITHDRAW PROCESS === //
        curveStrategy.withdraw(address(CRV3), partStakeDAO);

        // === ASSERTIONS === //
        //Assertion 1: Check test received token
        assertEq(CRV3.balanceOf(address(this)), partStakeDAO, "1");
        // Assertion 2: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(balanceBeforeStakeDAO - ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO)), partStakeDAO, "2");
    }

    function test_Withdraw_UsingConvexCurveFallback() public {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _deposit(CRV3, MAX, 1);

        // Check Stake DAO balance before withdraw
        uint256 balanceBeforeStakeDAO = ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO));

        uint256 toWithtdraw = partStakeDAO / 2 + partConvex;
        // === WITHDRAW PROCESS === //
        curveStrategy.withdraw(address(CRV3), toWithtdraw);

        // === ASSERTIONS === //
        //Assertion 1: Check test received token
        assertEq(CRV3.balanceOf(address(this)), toWithtdraw, "1");
        //Assertion 2: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(balanceBeforeStakeDAO - ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO)), partStakeDAO / 2, "2");
    }

    function test_Withdraw_UsingConvexFraxFallback() public {
        // === DEPOSIT PROCESS === //
        (, uint256 partConvex) = _deposit(ALUSD_FRAXBP, MAX, 1);

        // Get all needed infos for following assertions
        BaseFallback.PidsInfo memory pidsInfo = fallbackConvexFrax.getPid(address(ALUSD_FRAXBP));
        address personalVault = poolRegistryConvexFrax.vaultMap(pidsInfo.pid, address(fallbackConvexFrax));
        (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pidsInfo.pid);

        uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault);
        IFraxUnifiedFarm.LockedStake memory infosBefore =
            IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[lockCount - 1];

        // Withdraw only convex part
        uint256 toWithtdraw = partConvex / 2;
        uint256 timejump = fallbackConvexFrax.lockingIntervalSec();
        skip(timejump);

        // Withdraw ALUSD_FRAXBP
        curveStrategy.withdraw(address(ALUSD_FRAXBP), toWithtdraw);

        // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
        // and the last one is emptyed. So we need to get the last one.
        lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault);
        IFraxUnifiedFarm.LockedStake memory infosAfter =
            IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[lockCount - 1];

        // === ASSERTIONS === //
        //Assertion 1: Check test received token
        assertEq(ALUSD_FRAXBP.balanceOf(address(this)), toWithtdraw, "1");
        //Assertion 2: Check length of lockedStakesOf, should be 2 due to withdraw and redeposit
        assertEq(IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault), 2, "2");
        //Assertion 3: Check kek_id is different due to new lockStake
        assertTrue(infosAfter.kek_id != infosBefore.kek_id, "3");
    }

    // --- Claim --- //
    function test_Claim_NoExtraRewards() public {
        _claimTest(CRV3, ERC20(address(0)));
    }

    function test_Claim_ExtraRewardsWithReceiver() public {
        _claimTest(CNC_ETH, CNC);
    }

    function test_ClaimExtraRewardsWithoutReceiver() public {
        _claimTest(STETH_ETH, LDO);
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

    //////////////////////////////////////////////////////
    /// --- HELPER FUNCTIONS --- ///
    //////////////////////////////////////////////////////
    function _deposit(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex) internal returns (uint256, uint256) {
        // Amount for Stake DAO
        if (amountStakeDAO == 1) {
            amountStakeDAO = REF_AMOUNT;
        } else if (amountStakeDAO == MAX) {
            // Calculate optimal amount
            uint256 optimalAmount = optimizor.optimization1(gauges[address(token)], isMetapool[address(token)]);
            assert(optimalAmount > 0);

            // Final amount to deposit is optimal amount - locker gauge holding
            amountStakeDAO = optimalAmount - ERC20(gauges[address(token)]).balanceOf(LOCKER_STAKEDAO);
        }

        // Amount for Convex
        if (amountConvex == 1) amountConvex = REF_AMOUNT;

        uint256 totalAmount = amountStakeDAO + amountConvex;

        // Deal token to this contract
        deal(address(token), address(this), totalAmount);
        // Sometimes deal cheatcode doesn't work, so we check balance
        assert(token.balanceOf(address(this)) == totalAmount);

        // Approve token to strategy
        token.safeApprove(address(curveStrategy), totalAmount);

        // Deposit token
        curveStrategy.deposit(address(token), totalAmount);

        // Return infos
        return (amountStakeDAO, amountConvex);
    }

    function _claimTest(ERC20 token, ERC20 extraToken) internal {
        // Cache balance before
        uint256 balanceBeforeLG = CRV.balanceOf(liquidityGaugeMocks[address(token)]);
        uint256 balanceBeforeAC = CRV.balanceOf(address(curveStrategy.accumulator()));
        uint256 balanceBeforeMS = CRV.balanceOf(address(curveStrategy.rewardsReceiver()));
        uint256 balanceBeforeVE = CRV.balanceOf(address(curveStrategy.veSDTFeeProxy()));
        uint256 balanceBeforeCL = CRV.balanceOf(ALICE);
        uint256 balanceBeforeExtra;

        if (address(extraToken) != address(0)) {
            balanceBeforeExtra = extraToken.balanceOf(liquidityGaugeMocks[address(token)]);
        }

        // === DEPOSIT PROCESS === //
        _deposit(token, 1, 0);

        // Timejump 1 week
        skip(1 weeks);

        // === CLAIM PROCESS === //
        vm.prank(ALICE);
        curveStrategy.claim(address(token));

        // === ASSERTIONS === //
        //Assertion 1: Check test gauge received token
        assertGt(CRV.balanceOf(liquidityGaugeMocks[address(token)]), balanceBeforeLG, "1");
        //Assertion 2: Check test accumulator received token
        assertGt(CRV.balanceOf(address(curveStrategy.accumulator())), balanceBeforeAC, "2");
        //Assertion 3: Check test rewards receiver received token
        assertGt(CRV.balanceOf(address(curveStrategy.rewardsReceiver())), balanceBeforeMS, "3");
        //Assertion 4: Check test veSDT fee proxy received token
        assertGt(CRV.balanceOf(address(curveStrategy.veSDTFeeProxy())), balanceBeforeVE, "4");
        //Assertion 5: Check test alice received token
        assertGt(CRV.balanceOf(ALICE), balanceBeforeCL, "5");

        if (address(extraToken) == address(0)) return;
        // Assertion 6: Check extra token received
        assertGt(extraToken.balanceOf(liquidityGaugeMocks[address(token)]), balanceBeforeExtra, "6");
    }

    function _addAllGauge() internal {
        // Add all curve gauges
        curveStrategy.setGauge(address(CRV3), GAUGE_CRV3);
        curveStrategy.setGauge(address(CNC_ETH), GAUGE_CNC_ETH);
        curveStrategy.setGauge(address(STETH_ETH), GAUGE_STETH_ETH);
        curveStrategy.setGauge(address(ALUSD_FRAXBP), GAUGE_ALUSD_FRAXBP);

        // Add all stake dao gauges
        curveStrategy.setMultiGauge(gauges[address(CRV3)], address(liquidityGaugeMockCRV3));
        curveStrategy.setMultiGauge(gauges[address(CNC_ETH)], address(liquidityGaugeMockCNC_ETH));
        curveStrategy.setMultiGauge(gauges[address(ALUSD_FRAXBP)], address(liquidityGaugeMockALUSD_FRAXBP));
        curveStrategy.setMultiGauge(gauges[address(STETH_ETH)], address(liquidityGaugeMockSTETH_ETH));

        // Set gauge mocks
        liquidityGaugeMocks[address(CRV3)] = address(liquidityGaugeMockCRV3);
        liquidityGaugeMocks[address(CNC_ETH)] = address(liquidityGaugeMockCNC_ETH);
        liquidityGaugeMocks[address(STETH_ETH)] = address(liquidityGaugeMockSTETH_ETH);
        liquidityGaugeMocks[address(ALUSD_FRAXBP)] = address(liquidityGaugeMockALUSD_FRAXBP);

        // Set gauge types
        curveStrategy.setLGtype(gauges[address(CRV3)], 1);
        curveStrategy.setLGtype(gauges[address(CNC_ETH)], 0);
        curveStrategy.setLGtype(gauges[address(STETH_ETH)], 0);
        curveStrategy.setLGtype(gauges[address(ALUSD_FRAXBP)], 0);
    }

    function _labelContract() internal {
        vm.label(address(curveStrategy), "CurveStrategy");
        vm.label(address(curveStrategy.optimizor()), "Optimizor");
        vm.label(address(fallbackConvexFrax), "FallbackConvexFrax");
        vm.label(address(fallbackConvexCurve), "FallbackConvexCurve");
        vm.label(address(locker), "Locker");
        vm.label(address(boosterConvexFrax), "BoosterConvexFrax");
        vm.label(address(boosterConvexCurve), "BoosterConvexCurve");
        vm.label(address(poolRegistryConvexFrax), "PoolRegistryConvexFrax");
        
        // Mocks 
        vm.label(address(liquidityGaugeMockCRV3), "LiquidityGaugeMockCRV3");
        vm.label(address(liquidityGaugeMockCNC_ETH), "LiquidityGaugeMockCNC_ETH");
        vm.label(address(liquidityGaugeMockSTETH_ETH), "LiquidityGaugeMockSTETH_ETH");
        vm.label(address(liquidityGaugeMockALUSD_FRAXBP), "LiquidityGaugeMockALUSD_FRAXBP");
    }

    function _setFees() internal {
        address[] memory tokens = new address[](20);
        tokens[0] = address(CRV3);
        tokens[1] = address(ALUSD_FRAXBP);
        tokens[2] = address(CNC_ETH);
        tokens[3] = address(STETH_ETH);

        uint256 len = tokens.length;
        for (uint8 i; i < len; ++i) {
            address token = tokens[i];
            if (token == address(0)) break;

            curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.PERFFEE, gauges[address(token)], FEE_PERF);
            curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.VESDTFEE, gauges[address(token)], FEE_VESDT);
            curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.ACCUMULATORFEE, gauges[address(token)], FEE_ACCU);
            curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.CLAIMERREWARD, gauges[address(token)], FEE_CLAIM);
        }
    }
}
