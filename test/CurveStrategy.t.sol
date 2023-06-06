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
        forkId1 = vm.createFork(vm.rpcUrl("mainnet"), FORK_BLOCK_NUMBER_1);
        forkId2 = vm.createFork(vm.rpcUrl("mainnet"), FORK_BLOCK_NUMBER_2);
    }

    modifier useFork(uint256 forkId) {
        vm.selectFork(forkId);
        _setup();
        _;
    }

    function _setup() internal {
        // Deployment contracts
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        curveStrategy = new CurveStrategy(address(this), rolesAuthority);
        liquidityGaugeMockCRV3 = new LiquidityGaugeMock();
        liquidityGaugeMockCNC_ETH = new LiquidityGaugeMock();
        liquidityGaugeMockSTETH_ETH = new LiquidityGaugeMock();
        liquidityGaugeMockALUSD_FRAXBP = new LiquidityGaugeMock();
        accumulatorMock = new AccumulatorMock();
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
    function test_DeploymentAddresses() public useFork(forkId1) {
        assertTrue(address(optimizor) != address(0), "1");
        assertTrue(fallbackConvexFrax != FallbackConvexFrax(address(0)), "2");
        assertTrue(fallbackConvexCurve != FallbackConvexCurve(address(0)), "3");
        assertTrue(optimizor.fallbacksLength() != 0, "4");
        assertTrue(fallbackConvexFrax.lastPidsCount() != 0, "5");
        assertTrue(fallbackConvexCurve.lastPidsCount() != 0, "6");
    }

    // --- Deposit
    function test_Deposit_AllOnStakeDAOWithOptimalAmount() public useFork(forkId1) useFork(forkId1) {
        (uint256 partStakeDAO,) = _calculDepositAmount(CRV3, 1, 0);

        _depositTest(CRV3, partStakeDAO, 0, 0);
    }

    function test_Deposit_AllOnStakeDAOBecauseOnlyChoice() public useFork(forkId1) {
        // Create a fack fallback that return false for `isActive`
        FallbackConvexCurveMock mock = new FallbackConvexCurveMock(address(curveStrategy));
        optimizor.setFallbackAddresses(address(mock), address(fallbackConvexFrax));

        _depositTest(CRV3, 5_000_000e18, 0, 0);
    }

    function test_Deposit_UsingConvexCurveFallback() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _depositTest(CRV3, partStakeDAO, partConvex, 0);
    }

    function test_Deposit_UsingConvexFraxFallBack() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);

        _depositTest(ALUSD_FRAXBP, partStakeDAO, partConvex, 0);
    }

    function test_Deposit_UsingConvexFraxSecondDeposit() public useFork(forkId1) {
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

    function test_Deposit_WhenConvexFraxIsPaused() public useFork(forkId1) {
        // Pause ConvexFrax deposit
        optimizor.pauseConvexFraxDeposit();

        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO1, uint256 partConvex1) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);
        _depositTest(ALUSD_FRAXBP, partStakeDAO1, partConvex1, 0);
    }

    function test_Deposit_UsingConvexCurveAndFrax() public useFork(forkId2) {
        // This situation could rarely happen, but it's possible
        // When a pool is added on ConvexCurve, user can deposit on curveStrategy for this pool
        // And some times after, the pool is added on ConvexFrax
        // so this should have some tokens on both fallbacks,
        // let's test it using COIL_FRAXBP, added on ConvexFrax at block 17326004 on this tx :
        // https://etherscan.io/tx/0xbcc25272dad48329ed963991f156b929b28ee171e4ad157e2d9b749f3d85eb7b

        // First deposit into StakeDAO Locker and Convex Curve,
        // at the moment COIL_FRAXBP is not added on Metapool mapping on this test
        (uint256 partStakeDAO, uint256 partConvexBefore) = _calculDepositAmount(COIL_FRAXBP, MAX, 1);
        _depositTest(COIL_FRAXBP, partStakeDAO, partConvexBefore, 0);

        _addCOIL_FRAXBPOnConvexFrax();
        isMetapool[address(COIL_FRAXBP)] = true;

        // Second deposit into StakeDAO Locker and Convex Frax
        (uint256 partStakeDAOAfter, uint256 partConvexAfter) = _calculDepositAmount(COIL_FRAXBP, MAX, 1);
        _depositTest(COIL_FRAXBP, partStakeDAOAfter, partConvexAfter, 0);

        skip(1 weeks);
        // Check that we have tokens on both fallbacks
        assertEq(fallbackConvexFrax.balanceOf(address(COIL_FRAXBP)), partConvexAfter, "1");
        assertEq(fallbackConvexCurve.balanceOf(address(COIL_FRAXBP)), partConvexBefore, "2");
    }

    function test_RevertWhen_AddresNull_Deposit() public useFork(forkId1) {
        // Give some tokens to this contract
        deal(address(CVX), address(this), 1);
        // Approve CurveStrategy to spend CVX
        CVX.safeApprove(address(curveStrategy), 1);

        // Should revert because no gauge for CVX
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.deposit(address(CVX), 1);
    }

    // --- Withdraw
    function test_Withdraw_AllFromStakeDAO() public useFork(forkId1) {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, 1, 0);
        _deposit(CRV3, partStakeDAO, partConvex);

        // === WITHDRAW PROCESS === //
        _withdrawTest(CRV3, partStakeDAO, partConvex, 0);
    }

    function test_Withdraw_UsingConvexCurveFallback() public useFork(forkId1) {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);
        _deposit(CRV3, partStakeDAO, partConvex);

        // === WITHDRAW PROCESS === //
        _withdrawTest(CRV3, partStakeDAO / 2, partConvex, 0);
    }

    function test_Withdraw_AllUsingConvexCurveFallback() public useFork(forkId1) {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);
        _deposit(CRV3, partStakeDAO, partConvex);

        // === WITHDRAW PROCESS === //
        _withdrawTest(CRV3, partStakeDAO, partConvex, 0);
    }

    function test_Withdraw_UsingConvexFraxFallbackPartly() public useFork(forkId1) {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);
        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex);

        // Withdraw ALUSD_FRAXBP
        _withdrawTest(ALUSD_FRAXBP, 0, partConvex / 2, fallbackConvexFrax.lockingIntervalSec());
    }

    function test_Withdraw_UsingConvexFraxFallbackFully() public useFork(forkId1) {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);
        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex);

        // Withdraw ALUSD_FRAXBP
        _withdrawTest(ALUSD_FRAXBP, 0, partConvex, fallbackConvexFrax.lockingIntervalSec());
    }

    function test_Withdraw_AllUsingConvexCurveAndFrax() public useFork(forkId2) {
        // This is the following ot test_Deposit_OnConvexCurveAndFrax
        // On this withdraw we need to take tokens from both fallbacks

        // === DEPOSIT PROCESS === //
        // First deposit into StakeDAO Locker and Convex Curve,
        // at the moment COIL_FRAXBP is not added on Metapool mapping on this test
        (uint256 partStakeDAOBefore, uint256 partConvexBefore) = _calculDepositAmount(COIL_FRAXBP, MAX, 1);
        _depositTest(COIL_FRAXBP, partStakeDAOBefore, partConvexBefore, 0);

        // Add the pool on ConvexFrax
        _addCOIL_FRAXBPOnConvexFrax();
        isMetapool[address(COIL_FRAXBP)] = true;

        // Second deposit into StakeDAO Locker and Convex Frax
        (uint256 partStakeDAOAfter, uint256 partConvexAfter) = _calculDepositAmount(COIL_FRAXBP, MAX, 1);
        _depositTest(COIL_FRAXBP, partStakeDAOAfter, partConvexAfter, 0);

        // Use the total amount owned by the locker to be sure to withdraw all
        uint256 balanceOfStakeDAO = ERC20(gauges[address(COIL_FRAXBP)]).balanceOf(LOCKER_STAKEDAO);

        // === WITHDRAW PROCESS === //
        _withdrawTest(
            COIL_FRAXBP,
            partStakeDAOAfter + partStakeDAOBefore + balanceOfStakeDAO,
            partConvexAfter + partConvexBefore,
            fallbackConvexFrax.lockingIntervalSec()
        );
    }

    function test_RevertWhen_WithdrawTooMuch() public useFork(forkId1) {
        _deposit(CRV3, 100, 0);

        uint256 balanceOfStakeDAO = ERC20(gauges[address(CRV3)]).balanceOf(LOCKER_STAKEDAO);
        vm.expectRevert(Optimizor.WRONG_AMOUNT.selector);
        curveStrategy.withdraw(address(CRV3), balanceOfStakeDAO + 1);
    }

    function test_RevertWhen_AddresNull_Withdraw() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.withdraw(address(CVX), 1);
    }

    function test_RevertWhen_WithdrawFailed_MigrateLP() public useFork(forkId1) {
        // Get balance of the gauge
        uint256 balanceGauge = ERC20(gauges[address(CRV3)]).balanceOf(address(LOCKER_STAKEDAO));
        // data used on executed function by the LL
        bytes memory data = abi.encodeWithSignature("withdraw(uint256)", balanceGauge);

        // Mock the call to force the fail on withdraw from gauge from the LL
        vm.mockCall(
            address(LOCKER_STAKEDAO),
            abi.encodeWithSignature("execute(address,uint256,bytes)", gauges[address(CRV3)], 0, data),
            abi.encode(false, 0x0)
        );

        // Assert Error
        vm.expectRevert(EventsAndErrors.WITHDRAW_FAILED.selector);
        curveStrategy.migrateLP(address(CRV3));
    }

    function test_RevertWhen_CallFailed_MigrateLP() public useFork(forkId1) {
        // Get balance of the gauge
        uint256 balanceGauge = ERC20(gauges[address(CRV3)]).balanceOf(address(LOCKER_STAKEDAO));
        // Get balance of the locker
        uint256 balanceLocker = CRV3.balanceOf(address(LOCKER_STAKEDAO));

        // data used on executed function by the LL
        bytes memory data =
            abi.encodeWithSignature("transfer(address,uint256)", address(this), balanceGauge + balanceLocker);

        // Mock the call to force the fail on transfer LP from the LL
        vm.mockCall(
            address(LOCKER_STAKEDAO),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(CRV3), 0, data),
            abi.encode(false, 0x0)
        );

        // Assert Revert
        vm.expectRevert(EventsAndErrors.CALL_FAILED.selector);
        curveStrategy.migrateLP(address(CRV3));
    }

    // --- Claim
    function test_Claim_NoExtraRewards() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, 1, 0);

        _deposit(CRV3, partStakeDAO, partConvex);

        _claimLiquidLockerTest(CRV3, 1 weeks, new address[](0));
    }

    function test_Claim_ExtraRewardsWithReceiver() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CNC_ETH, 1, 0);

        _deposit(CNC_ETH, partStakeDAO, partConvex);

        address[] memory extraTokens = new address[](1);
        extraTokens[0] = address(CNC);

        _claimLiquidLockerTest(CNC_ETH, 1 weeks, extraTokens);
    }

    function test_Claim_ExtraRewardsWithoutReceiver() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(STETH_ETH, 1, 0);

        _deposit(STETH_ETH, partStakeDAO, partConvex);

        address[] memory extraTokens = new address[](1);
        extraTokens[0] = address(LDO);
        _claimLiquidLockerTest(STETH_ETH, 1 weeks, extraTokens);
    }

    function test_Claim3CRV() public useFork(forkId1) {
        curveStrategy.setAccumulator(address(accumulatorMock));
        // Cache balance before
        uint256 balanceBeforeAC = CRV3.balanceOf(address(curveStrategy.accumulator()));

        // Timejump 1 week
        skip(1 weeks);

        // === CLAIM 3CRV PROCESS === //
        // No need to notify all, because it will call back the same exact process
        curveStrategy.claim3Crv(true);

        // === ASSERTIONS === //
        //Assertion 1: Check test accumulator received token
        assertGt(CRV3.balanceOf(address(curveStrategy.accumulator())), balanceBeforeAC, "1");
    }

    function test_Claim_ConvexCurveRewardsWithoutFees() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _deposit(CRV3, partStakeDAO, partConvex, 0);

        fallbackConvexCurve.setFeesOnRewards(0);

        _claimLiquidLockerTest(CRV3, 1 weeks, fallbackConvexCurve.getRewardsTokens(address(ALUSD_FRAXBP)));
    }

    function test_Claim_ConvexCurveRewardsWithFees() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _deposit(CRV3, partStakeDAO, partConvex, 0);

        fallbackConvexCurve.setFeesOnRewards(1e16);

        _claimLiquidLockerTest(CRV3, 1 weeks, fallbackConvexCurve.getRewardsTokens(address(CRV3)));
    }

    function test_Claim_ConvexFraxRewardsWithoutFees() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);

        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex, 0);

        fallbackConvexCurve.setFeesOnRewards(0);

        _claimLiquidLockerTest(ALUSD_FRAXBP, 1 weeks, fallbackConvexFrax.getRewardsTokens(address(ALUSD_FRAXBP)));
    }

    function test_Claim_ConvexFraxRewardsWithFees() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);

        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex, 0);

        fallbackConvexFrax.setFeesOnRewards(1e16);

        _claimLiquidLockerTest(ALUSD_FRAXBP, 1 weeks, fallbackConvexFrax.getRewardsTokens(address(ALUSD_FRAXBP)));
    }

    function test_RevertWhen_AddressNull_Claim() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.claim(address(CVX));
    }

    function test_RevertWhen_AddressNull_Fallbacks() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.claimFallbacks(address(CVX));
    }

    function test_RevertWhen_AmountNull_Claim3CRV() public useFork(forkId1) {
        // Because no time has been skipped, there is no rewards to claim
        vm.expectRevert(EventsAndErrors.AMOUNT_NULL.selector);
        curveStrategy.claim3Crv(false);
    }

    // --- Migrate LP
    function test_MigrateLP() public useFork(forkId1) {
        assertEq(CRV3.balanceOf(address(this)), 0, "0");

        uint256 balanceGaugeBefore = ERC20(gauges[address(CRV3)]).balanceOf(LOCKER_STAKEDAO);
        // === DEPOSIT PROCESS === //
        _deposit(CRV3, 100, 0);

        // === MIGRATE LP PROCESS === //
        curveStrategy.migrateLP(address(CRV3));

        // === ASSERTIONS === //
        assertEq(CRV3.balanceOf(address(this)), balanceGaugeBefore + 100, "1");
    }

    function test_RevertWhen_AddressNull_MigrateLP() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.migrateLP(address(CVX));
    }

    // --- Kill ConvexFrax
    function test_KillConvexFrax() public useFork(forkId1) {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1_000_000e18);
        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex);

        // Pause ConvexFrax deposit
        optimizor.pauseConvexFraxDeposit();

        // Wait 1 week
        skip(1 weeks);

        // Authorize Optimizor to withdraw from convexFrax and deposit into strategy
        _killConvexFraxAuth();

        assertGt(fallbackConvexFrax.balanceOf(address(ALUSD_FRAXBP)), 0, "0");

        uint256 balanceBeforeConvexCurve = fallbackConvexCurve.balanceOf(address(ALUSD_FRAXBP));
        uint256 balanceBeforeStakeDAO = ERC20(gauges[address(ALUSD_FRAXBP)]).balanceOf(address(LOCKER_STAKEDAO));

        // === KILL PROCESS === //
        optimizor.killConvexFrax();

        // === ASSERTIONS === //
        //Assertion 1: Check ConvexFrax balance
        assertEq(fallbackConvexFrax.balanceOf(address(ALUSD_FRAXBP)), 0, "1");
        //Assertion 2: Check ConvexCurve balance
        assertGt(fallbackConvexCurve.balanceOf(address(ALUSD_FRAXBP)), balanceBeforeConvexCurve, "2");
        //Assertion 3: Check StakeDAO balance
        assertGt(ERC20(gauges[address(ALUSD_FRAXBP)]).balanceOf(address(LOCKER_STAKEDAO)), balanceBeforeStakeDAO, "3");
    }

    function test_RevertWhen_OptimizorAlreadyPaused() public useFork(forkId1) {
        optimizor.pauseConvexFraxDeposit();

        vm.expectRevert(Optimizor.ALREADY_PAUSED.selector);
        optimizor.pauseConvexFraxDeposit();
    }

    function test_RevertWhen_OptimizorNotPaused() public useFork(forkId1) {
        vm.expectRevert(Optimizor.NOT_PAUSED.selector);
        optimizor.killConvexFrax();
    }

    function test_RevertWhen_OptimizorTooSoon() public useFork(forkId1) {
        optimizor.pauseConvexFraxDeposit();

        vm.expectRevert(Optimizor.TOO_SOON.selector);
        optimizor.killConvexFrax();
    }

    function test_PauseConvexFraxDeposit() public useFork(forkId1) {
        assertEq(optimizor.isConvexFraxPaused(), false, "0");
        assertEq(optimizor.convexFraxPausedTimestamp(), 0, "1");

        // Pause ConvexFrax deposit
        optimizor.pauseConvexFraxDeposit();

        assertEq(optimizor.isConvexFraxPaused(), true, "2");
        assertEq(optimizor.convexFraxPausedTimestamp(), block.timestamp, "3");
    }

    // --- SendToAccumulator
    function test_SendToAccumulator() public useFork(forkId1) {
        // Send 1_000 ALUSD_FRAXBP to the curve strategy
        deal(address(ALUSD_FRAXBP), address(curveStrategy), 1_000e18);

        // Set the accumulator address using mock contract
        curveStrategy.setAccumulator(address(accumulatorMock));

        // Check that the accumulator balance is 0
        assertEq(ALUSD_FRAXBP.balanceOf(address(curveStrategy.accumulator())), 0, "0");

        // Send 1_000 ALUSD_FRAXBP to the accumulator
        curveStrategy.sendToAccumulator(address(ALUSD_FRAXBP), 1_000e18);

        // Check that the accumulator balance is 1_000
        assertEq(ALUSD_FRAXBP.balanceOf(address(curveStrategy.accumulator())), 1_000e18, "1");
    }

    // --- Optimizor
    function test_ToggleUseLastOptimization() public useFork(forkId1) {
        assertEq(optimizor.useLastOpti(), false, "0");

        optimizor.toggleUseLastOptimization();

        assertEq(optimizor.useLastOpti(), true, "1");
    }

    function test_SetCachePeriod() public useFork(forkId1) {
        assertEq(optimizor.cachePeriod(), 7 days, "0");

        optimizor.setCachePeriod(2 weeks);

        assertEq(optimizor.cachePeriod(), 2 weeks, "1");
    }

    function test_LastOptiMappingWriting() public useFork(forkId1) {
        // Toggle using last optimization
        optimizor.toggleUseLastOptimization();

        // --- Test for Metapool
        // Get last optimization value
        (uint256 valueBefore, uint256 tsBefore) = optimizor.lastOptiMetapool(gauges[address(ALUSD_FRAXBP)]);
        // Calculate optimization
        uint256 calculatedOpti = optimizor.optimization1(address(gauges[address(ALUSD_FRAXBP)]), true);

        // Call the optimize deposit
        optimizor.optimizeDeposit(address(ALUSD_FRAXBP), gauges[address(ALUSD_FRAXBP)], 1_000_000e18);

        // Get last optimization value
        (uint256 valueAfter, uint256 tsAfter) = optimizor.lastOptiMetapool(gauges[address(ALUSD_FRAXBP)]);

        // Assertions
        assertEq(valueBefore, 0, "0");
        assertEq(tsBefore, 0, "1");
        assertEq(valueAfter, calculatedOpti, "2");
        assertEq(tsAfter, block.timestamp, "3");

        // --- Test for non Metapool
        // Get last optimization value
        (valueBefore, tsBefore) = optimizor.lastOpti(gauges[address(CRV3)]);
        // Calculate optimization
        calculatedOpti = optimizor.optimization1(address(gauges[address(CRV3)]), false);

        // Call the optimize deposit
        optimizor.optimizeDeposit(address(CRV3), gauges[address(CRV3)], 1_000_000e18);

        // Get last optimization value
        (valueAfter, tsAfter) = optimizor.lastOpti(gauges[address(CRV3)]);

        // Assertions
        assertEq(valueBefore, 0, "4");
        assertEq(tsBefore, 0, "5");
        assertEq(valueAfter, calculatedOpti, "6");
        assertEq(tsAfter, block.timestamp, "7");
    }

    function test_OptimizeDepositReturnedValueAfter4And7DaysMetapool() public useFork(forkId1) {
        _optimizedDepositReturnedValueAfter4And7Days(ALUSD_FRAXBP);
    }

    function test_OptimizeDepositReturnedValueAfter4And7DaysNotMetapool() public useFork(forkId1) {
        _optimizedDepositReturnedValueAfter4And7Days(CRV3);
    }

    // --- Setters
    function test_ToggleVault() public useFork(forkId1) {
        assertEq(curveStrategy.vaults(address(0x1)), false, "0");

        curveStrategy.toggleVault(address(0x1));

        assertEq(curveStrategy.vaults(address(0x1)), true, "1");
    }

    function test_SetGauge() public useFork(forkId1) {
        assertEq(curveStrategy.gauges(address(0x1)), address(0x0), "0");

        curveStrategy.setGauge(address(0x1), address(0x2));

        assertEq(curveStrategy.gauges(address(0x1)), address(0x2), "1");
    }

    function test_SetLGType() public useFork(forkId1) {
        assertEq(curveStrategy.lGaugeType(address(0x1)), 0, "0");

        curveStrategy.setLGtype(address(0x1), 1);

        assertEq(curveStrategy.lGaugeType(address(0x1)), 1, "1");
    }

    function test_SetMultiGauge() public useFork(forkId1) {
        assertEq(curveStrategy.multiGauges(address(0x1)), address(0), "0");

        curveStrategy.setMultiGauge(address(0x1), address(0x2));

        assertEq(curveStrategy.multiGauges(address(0x1)), address(0x2), "1");
    }

    function test_SetVeSDTProxy() public useFork(forkId1) {
        assertTrue(curveStrategy.veSDTFeeProxy() != address(0), "0");

        curveStrategy.setVeSDTProxy(address(0x1));

        assertEq(curveStrategy.veSDTFeeProxy(), address(0x1), "1");
    }

    function test_SetAccumulator() public useFork(forkId1) {
        assertTrue(address(curveStrategy.accumulator()) != address(0), "0");

        curveStrategy.setAccumulator(address(0x1));

        assertEq(address(curveStrategy.accumulator()), address(0x1), "1");
    }

    function test_SetRewardsReceiver() public useFork(forkId1) {
        assertTrue(curveStrategy.rewardsReceiver() != address(0), "0");

        curveStrategy.setRewardsReceiver(address(0x1));

        assertEq(curveStrategy.rewardsReceiver(), address(0x1), "1");
    }

    function test_SetOptimizor() public useFork(forkId1) {
        assertTrue(address(curveStrategy.optimizor()) != address(0), "0");

        curveStrategy.setOptimizor(address(0x1));

        assertEq(address(curveStrategy.optimizor()), address(0x1), "1");
    }

    function test_RevertWhen_AddressNull_ToggleVault() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.toggleVault(address(0));
    }

    function test_RevertWhen_AddressNull_SetGauge() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.setGauge(address(0), address(0x2));
    }

    function test_RevertWhen_AddressNull_SetLGType() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.setLGtype(address(0), 1);
    }

    function test_RevertWhen_AddressNull_SetMultiGauge() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.setMultiGauge(address(0), address(0x2));

        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.setMultiGauge(address(0x2), address(0));
    }

    function test_RevertWhen_AddressNull_SetVeSDTProxy() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.setVeSDTProxy(address(0));
    }

    function test_RevertWhen_AddressNull_SetAccumulator() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.setAccumulator(address(0));
    }

    function test_RevertWhen_AddressNull_SetRewardsReceiver() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.setRewardsReceiver(address(0));
    }

    function test_RevertWhen_AddressNull_SetOptimizor() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.setOptimizor(address(0));
    }

    function test_RevertWhen_AddressNull_ManageFee() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.ADDRESS_NULL.selector);
        curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.PERFFEE, address(0), 10);
    }

    function test_RevertWhen_FeeTooHigh_ManageFee() public useFork(forkId1) {
        vm.expectRevert(EventsAndErrors.FEE_TOO_HIGH.selector);
        curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.PERFFEE, gauges[address(ALUSD_FRAXBP)], 10001);
    }

    // --- Execute
    function test_Execute() public useFork(forkId1) {
        (bool success, bytes memory data) =
            curveStrategy.execute(address(optimizor), 0, abi.encodeWithSignature("CRV()"));

        assertTrue(success, "0");
        assertEq(abi.decode(data, (address)), address(CRV), "1");
    }
}
