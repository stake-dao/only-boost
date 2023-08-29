// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";

contract CurveStrategyTest is BaseTest {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public {
        // Create a fork of mainnet, fixing block number for faster testing
        forkId1 = FORK_BLOCK_NUMBER_1;
        forkId2 = FORK_BLOCK_NUMBER_2;
        forkId3 = FORK_BLOCK_NUMBER_3;
    }

    modifier useFork(uint256 forkId) {
        vm.rollFork(forkId);
        _setup();
        _;
    }

    function _setup() internal {
        locker = ILocker(LOCKER);

        // Deployment contracts
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        curveStrategy = new CurveStrategy(address(this), rolesAuthority);
        fallbackConvexCurve = new ConvexFallback(address(this), rolesAuthority, address(curveStrategy));
        optimizor = new Optimizor(address(this), rolesAuthority, address(curveStrategy), address(fallbackConvexCurve));
        liquidityGaugeMockCRV3 = new LiquidityGaugeMock(CRV3);
        liquidityGaugeMockCNC_ETH = new LiquidityGaugeMock(CNC_ETH);
        liquidityGaugeMockSTETH_ETH = new LiquidityGaugeMock(STETH_ETH);
        liquidityGaugeMockALUSD_FRAXBP = new LiquidityGaugeMock(ALUSD_FRAXBP);
        accumulatorMock = new AccumulatorMock();
        // End deployment contracts

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(address(curveStrategy));

        // Setup contract
        _afterDeployment();
    }

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////

    // --- Deployment
    function test_DeploymentAddresses() public useFork(forkId1) {
        assertTrue(address(optimizor) != address(0), "1");
        assertTrue(fallbackConvexCurve != ConvexFallback(address(0)), "3");
        assertTrue(optimizor.fallbacksLength() != 0, "4");
        assertTrue(fallbackConvexCurve.lastPidsCount() != 0, "6");
    }

    // --- Deposit
    function test_Deposit_AllOnStakeDAOWithOptimalAmount() public useFork(forkId1) useFork(forkId1) {
        (uint256 partStakeDAO,) = _calculDepositAmount(CRV3, 1, 0);

        _depositTest(CRV3, partStakeDAO, 0, 0);
    }

    function test_Deposit_AllOnStakeDAOBecauseOnlyChoice() public useFork(forkId1) {
        // Mock call on fallback that return false for `isActive`
        vm.mockCall(
            address(fallbackConvexCurve), abi.encodeWithSignature("isActive(address)", address(CRV3)), abi.encode(false)
        );

        _depositTest(CRV3, 5_000_000e18, 0, 0);
    }

    function test_Deposit_UsingConvexCurveFallback() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _depositTest(CRV3, partStakeDAO, partConvex, 0);
    }

    function test_Deposit_UsingConvexCurveOnlyDueToMaxBoost() public useFork(forkId1) {
        // Check balance before
        uint256 balanceBeforeStakeDAO = ERC20(gauges[address(SDCRV_CRV)]).balanceOf(address(LOCKER));
        uint256 balanceBeforeConvex = ERC20(gauges[address(SDCRV_CRV)]).balanceOf(address(LOCKER_CONVEX));

        // Deposit SDCRV_CRV
        _deposit(SDCRV_CRV, 200, 0);

        // Check balance after
        uint256 balanceAfterStakeDAO = ERC20(gauges[address(SDCRV_CRV)]).balanceOf(address(LOCKER));
        uint256 balanceAfterConvex = ERC20(gauges[address(SDCRV_CRV)]).balanceOf(address(LOCKER_CONVEX));

        // Because convex has max boost on this pool, all tokens should be on ConvexCurve fallback
        assertEq(balanceAfterStakeDAO, balanceBeforeStakeDAO, "1");
        assertEq(balanceAfterConvex, balanceBeforeConvex + 200, "2");
    }

    function test_Deposit_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        // Give some tokens to this contract
        deal(address(CVX), address(this), 1);
        // Approve CurveStrategy to spend CVX
        CVX.safeApprove(address(curveStrategy), 1);

        // Should revert because no gauge for CVX
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.deposit(address(CVX), 1);
    }

    function test_Deposit_RevertWhen_CALL_FAILED() public useFork(forkId1) {
        // Give some tokens to this contract
        deal(address(CRV3), address(this), 1);
        // Approve CurveStrategy to spend CRV3
        CRV3.safeApprove(address(curveStrategy), 1);

        bytes memory data = abi.encodeWithSignature("deposit(uint256)", 1);

        // Mock call to StakeDAO Locker
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", gauges[address(CRV3)], 0, data),
            abi.encode(false, 0x0)
        );

        // Should revert because no gauge for CRV3
        vm.expectRevert(CurveStrategy.CALL_FAILED.selector);
        curveStrategy.deposit(address(CRV3), 1);
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

    function test_Withdraw_RevertWhen_WRONG_AMOUNT() public useFork(forkId1) {
        _deposit(CRV3, 100, 0);

        uint256 balanceOfStakeDAO = ERC20(gauges[address(CRV3)]).balanceOf(LOCKER);
        vm.expectRevert(Optimizor.WRONG_AMOUNT.selector);
        curveStrategy.withdraw(address(CRV3), balanceOfStakeDAO + 1);
    }

    function test_Withdraw_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.withdraw(address(CVX), 1);
    }

    function test_Withdraw_RevertWhen_WITHDRAW_FAILED() public useFork(forkId1) {
        bytes memory data = abi.encodeWithSignature("withdraw(uint256)", 1);

        // Mock call to StakeDAO Locker
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", gauges[address(CRV3)], 0, data),
            abi.encode(false, 0x0)
        );

        // Should revert because no gauge for CRV3
        vm.expectRevert(CurveStrategy.WITHDRAW_FAILED.selector);
        curveStrategy.withdraw(address(CRV3), 1);
    }

    function test_Withdraw_RevertWhen_CALL_FAILED() public useFork(forkId1) {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(curveStrategy), 1);

        // Mock call to StakeDAO Locker
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(CRV3), 0, data),
            abi.encode(false, 0x0)
        );

        // Should revert because no gauge for CRV3
        vm.expectRevert(CurveStrategy.TRANSFER_FROM_LOCKER_FAILED.selector);
        curveStrategy.withdraw(address(CRV3), 1);
    }

    // --- Claim
    function test_Claim_NoExtraRewards() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, 1, 0);

        _deposit(CRV3, partStakeDAO, partConvex);

        _claimLiquidLockerTest(CRV3, 1 weeks, new address[](0), ALICE);
    }

    function test_Claim_ExtraRewardsWithReceiver() public useFork(forkId1) {
        // Deposit only into Stake dao
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CNC_ETH, 1, 0);

        _deposit(CNC_ETH, partStakeDAO, partConvex);

        address[] memory extraTokens = new address[](1);
        extraTokens[0] = address(CNC);

        _claimLiquidLockerTest(CNC_ETH, 1 weeks, extraTokens, ALICE);
    }

    function test_Claim_ExtraRewardsWithoutReceiver() public useFork(forkId1) {
        // Deposit only into Stake dao
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(STETH_ETH, 1, 0);

        _deposit(STETH_ETH, partStakeDAO, partConvex);

        address[] memory extraTokens = new address[](0);
        //extraTokens[0] = address(LDO);
        _claimLiquidLockerTest(STETH_ETH, 1 weeks, extraTokens, ALICE);
    }

    function test_Claim_ConvexCurveRewardsWithoutFees() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _deposit(CRV3, partStakeDAO, partConvex, 0);

        _claimLiquidLockerTest(CRV3, 1 weeks, fallbackConvexCurve.getRewardsTokens(address(ALUSD_FRAXBP)), ALICE);
    }

    function test_Claim_ConvexCurveRewardsWithFees() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _deposit(CRV3, partStakeDAO, partConvex, 0);

        _claimLiquidLockerTest(CRV3, 1 weeks, fallbackConvexCurve.getRewardsTokens(address(CRV3)), ALICE);
    }

    function test_Claim_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.claim(address(CVX), true);
    }

    function test_Claim_RevertWhen_ADDRESS_NULL_OnFallbacks() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.claimFallbacks(address(CVX));
    }

    function test_Claim_RevertWhen_MINT_FAILED() public useFork(forkId1) {
        _deposit(CRV3, 1000e18, 1);
        skip(1 weeks);

        bytes memory data = abi.encodeWithSignature("mint(address)", gauges[address(CRV3)]);

        // Mock call to StakeDAO Locker
        // Here 0 and Data are not specified because amount claimed is unknown.
        // But address(CRV3) is needed, otherwise it will revert on the "claim call"
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", curveStrategy.CRV_MINTER(), 0, data),
            abi.encode(false, 0x0)
        );

        // Because no time has been skipped, there is no rewards to claim
        vm.expectRevert(CurveStrategy.MINT_FAILED.selector);
        curveStrategy.claim(address(CRV3), true);
    }

    function test_Claim_RevertWhen_CALL_FAILED_TransferCRV() public useFork(forkId1) {
        _deposit(CRV3, 1000e18, 1);
        skip(1 weeks);

        //bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(curveStrategy));

        // Mock call to StakeDAO Locker
        // Here 0 and Data are not specified because amount claimed is unknown.
        // But address(CRV3) is needed, otherwise it will revert on the "claim call"
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(CRV)), //, 0, data),
            abi.encode(false, 0x0)
        );

        // Because no time has been skipped, there is no rewards to claim
        vm.expectRevert(CurveStrategy.CALL_FAILED.selector);
        curveStrategy.claim(address(CRV3), true);
    }

    function test_Claim_RevertWhen_CALL_FAILED_TransferExtraReward() public useFork(forkId1) {
        _deposit(STETH_ETH, 100e18, 1);
        skip(1 weeks);

        //bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(curveStrategy));

        // Mock call to StakeDAO Locker
        // Here 0 and Data are not specified because amount claimed is unknown.
        // But address(STETH_ETH) is needed, otherwise it will revert on the first transfer
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(LDO)), //, 0, data),
            abi.encode(false, 0x0)
        );

        // Because no time has been skipped, there is no rewards to claim
        vm.expectRevert(CurveStrategy.CALL_FAILED.selector);
        curveStrategy.claim(address(STETH_ETH), true);
    }

    // --- Claim 3CRV
    function test_Claim3CRV() public useFork(forkId1) {
        curveStrategy.setAccumulator(address(accumulatorMock));
        // Cache balance before
        uint256 balanceBeforeAC = CRV3.balanceOf(address(curveStrategy.accumulator()));

        // Timejump 1 week
        skip(1 weeks);

        // === CLAIM 3CRV PROCESS === //
        // No need to notify all, because it will call back the same exact process
        curveStrategy.claimNativeRewards(true);

        // === ASSERTIONS === //
        //Assertion 1: Check test accumulator received token
        assertGt(CRV3.balanceOf(address(curveStrategy.accumulator())), balanceBeforeAC, "1");
    }

    function test_Claim3CRV_RevertWhen_CLAIM_FAILED() public useFork(forkId1) {
        bytes memory data = abi.encodeWithSignature("claim()");

        // Mock call to StakeDAO Locker
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", curveStrategy.feeDistributor(), 0, data),
            abi.encode(false, 0x0)
        );

        // Because no time has been skipped, there is no rewards to claim
        vm.expectRevert(CurveStrategy.CLAIM_FAILED.selector);
        curveStrategy.claimNativeRewards(true);
    }

    function test_Claim3CRV_RevertWhen_CALL_FAILED() public useFork(forkId1) {
        _deposit(CRV3, 1000e18, 1);
        skip(1 weeks);

        // Mock call to StakeDAO Locker
        // Here 0 and Data are not specified because amount claimed is unknown.
        // But address(CRV3) is needed, otherwise it will revert on the "claim call"
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(CRV3)), // 0, data),
            abi.encode(false, 0x0)
        );

        // Because no time has been skipped, there is no rewards to claim
        vm.expectRevert(CurveStrategy.CALL_FAILED.selector);
        curveStrategy.claimNativeRewards(true);
    }

    // --- Migrate LP
    function test_MigrateLP() public useFork(forkId1) {
        assertEq(CRV3.balanceOf(vaults[address(CRV3)]), 0, "0");

        uint256 balanceGaugeBefore = ERC20(gauges[address(CRV3)]).balanceOf(LOCKER);
        // === DEPOSIT PROCESS === //
        _deposit(CRV3, 100, 0);

        // === MIGRATE LP PROCESS === //
        // Prank the vault to be able to call migrateLP
        vm.prank(vaults[address(CRV3)]);
        curveStrategy.migrateLP(address(CRV3));

        // === ASSERTIONS === //
        assertEq(CRV3.balanceOf(vaults[address(CRV3)]), balanceGaugeBefore + 100, "1");
    }

    function test_MigrateLP_RevertWhen_UNAUTHORIZED() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.UNAUTHORIZED.selector);
        curveStrategy.migrateLP(address(CRV3));
    }

    function test_MigrateLP_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        vm.prank(vaults[address(CRV3)]);
        curveStrategy.migrateLP(address(CVX));
    }

    function test_MigrateLP_RevertWhen_WITHDRAW_FAILED() public useFork(forkId1) {
        // Get balance of the gauge
        uint256 balanceGauge = ERC20(gauges[address(CRV3)]).balanceOf(address(LOCKER));
        // data used on executed function by the LL
        bytes memory data = abi.encodeWithSignature("withdraw(uint256)", balanceGauge);

        // Mock the call to force the fail on withdraw from gauge from the LL
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", gauges[address(CRV3)], 0, data),
            abi.encode(false, 0x0)
        );

        // Assert Error
        vm.expectRevert(CurveStrategy.WITHDRAW_FAILED.selector);
        // Prank the vault to be able to call migrateLP
        vm.prank(vaults[address(CRV3)]);
        // Call the function
        curveStrategy.migrateLP(address(CRV3));
    }

    function test_MigrateLP_RevertWhen_CALL_FAILED() public useFork(forkId1) {
        // Get balance of the gauge
        uint256 balanceGauge = ERC20(gauges[address(CRV3)]).balanceOf(address(LOCKER));
        // Get balance of the locker
        uint256 balanceLocker = CRV3.balanceOf(address(LOCKER));

        // data used on executed function by the LL
        bytes memory data =
            abi.encodeWithSignature("transfer(address,uint256)", vaults[address(CRV3)], balanceGauge + balanceLocker);

        // Mock the call to force the fail on transfer LP from the LL
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(CRV3), 0, data),
            abi.encode(false, 0x0)
        );

        // Assert Revert
        vm.expectRevert(CurveStrategy.CALL_FAILED.selector);
        // Prank the vault to be able to call migrateLP
        vm.prank(vaults[address(CRV3)]);
        // Call the function
        curveStrategy.migrateLP(address(CRV3));
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
        assertEq(optimizor.cacheEnabled(), false, "0");

        optimizor.toggleUseLastOptimization();

        assertEq(optimizor.cacheEnabled(), true, "1");
    }

    function test_SetCachePeriod() public useFork(forkId1) {
        assertEq(optimizor.cachePeriod(), 7 days, "0");

        optimizor.setCachePeriod(2 weeks);

        assertEq(optimizor.cachePeriod(), 2 weeks, "1");
    }

    function test_LastOptiMappingWriting() public useFork(forkId1) {
        // Toggle using last optimization
        optimizor.toggleUseLastOptimization();

        // --- Test for non Metapool
        // Get last optimization value
        (uint256 valueBefore, uint256 tsBefore) = optimizor.cachedOptimizations(gauges[address(CRV3)]);
        // Get veCRVStakeDAO balance
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);
        // Calculate optimization
        uint256 calculatedOpti = optimizor.optimalAmount(address(gauges[address(CRV3)]), veCRVStakeDAO);

        // Call the optimize deposit
        optimizor.optimizeDeposit(address(CRV3), gauges[address(CRV3)], 1_000_000e18);

        // Get last optimization value
        (uint256 valueAfter, uint256 tsAfter) = optimizor.cachedOptimizations(gauges[address(CRV3)]);

        // Assertions
        assertEq(valueBefore, 0, "4");
        assertEq(tsBefore, 0, "5");
        assertEq(valueAfter, calculatedOpti, "6");
        assertEq(tsAfter, block.timestamp, "7");
    }

    function test_OptimizeDepositReturnedValueAfter4And7DaysNotMetapool() public useFork(forkId1) {
        _optimizedDepositReturnedValueAfter4And7Days(CRV3);
    }

    function test_OptimizedDepositReturnedValueAfterCRVLockNotMetapool() public useFork(forkId1) {
        _optimizedDepositReturnedValueAfterCRVLock(CRV3);
    }

    // --- Setters
    function test_ToggleVault() public useFork(forkId1) {
        assertEq(curveStrategy.vaults(address(0x1)), false, "0");

        curveStrategy.toggleVault(address(0x1));

        assertEq(curveStrategy.vaults(address(0x1)), true, "1");
    }

    function test_ToggleVault_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.toggleVault(address(0));
    }

    function test_SetGauge() public useFork(forkId1) {
        assertEq(curveStrategy.gauges(address(0x1)), address(0x0), "0");

        curveStrategy.setGauge(address(0x1), address(0x2));

        assertEq(curveStrategy.gauges(address(0x1)), address(0x2), "1");
    }

    function test_SetGauge_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.setGauge(address(0), address(0x2));
    }

    function test_SetLGType() public useFork(forkId1) {
        assertEq(curveStrategy.lGaugeType(address(0x1)), 0, "0");

        curveStrategy.setLGtype(address(0x1), 1);

        assertEq(curveStrategy.lGaugeType(address(0x1)), 1, "1");
    }

    function test_SetLGType_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.setLGtype(address(0), 1);
    }

    function test_SetMultiGauge() public useFork(forkId1) {
        assertEq(curveStrategy.rewardDistributors(address(0x1)), address(0), "0");

        curveStrategy.setMultiGauge(address(0x1), address(0x2));

        assertEq(curveStrategy.rewardDistributors(address(0x1)), address(0x2), "1");
    }

    function test_SetMultiGauge_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.setMultiGauge(address(0), address(0x2));

        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.setMultiGauge(address(0x2), address(0));
    }

    function test_SetVeSDTProxy() public useFork(forkId1) {
        assertTrue(curveStrategy.veSDTFeeProxy() != address(0), "0");

        curveStrategy.setVeSDTProxy(address(0x1));

        assertEq(curveStrategy.veSDTFeeProxy(), address(0x1), "1");
    }

    function test_SetVeSDTProxyRevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.setVeSDTProxy(address(0));
    }

    function test_SetAccumulator() public useFork(forkId1) {
        assertTrue(address(curveStrategy.accumulator()) != address(0), "0");

        curveStrategy.setAccumulator(address(0x1));

        assertEq(address(curveStrategy.accumulator()), address(0x1), "1");
    }

    function test_SetAccumulator_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.setAccumulator(address(0));
    }

    function test_SetRewardsReceiver() public useFork(forkId1) {
        assertTrue(curveStrategy.rewardsReceiver() != address(0), "0");

        curveStrategy.setRewardsReceiver(address(0x1));

        assertEq(curveStrategy.rewardsReceiver(), address(0x1), "1");
    }

    function test_SetRewardsReceiver_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.setRewardsReceiver(address(0));
    }

    function test_SetOptimizor() public useFork(forkId1) {
        assertTrue(address(curveStrategy.optimizor()) != address(0), "0");

        curveStrategy.setOptimizor(address(0x1));

        assertEq(address(curveStrategy.optimizor()), address(0x1), "1");
    }

    function test_ManageFee_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.manageFee(CurveStrategy.MANAGEFEE.PERF_FEE, address(0), 10);
    }

    function test_RevertWhen_FeeTooHigh_ManageFee() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.FEE_TOO_HIGH.selector);
        curveStrategy.manageFee(CurveStrategy.MANAGEFEE.PERF_FEE, gauges[address(ALUSD_FRAXBP)], 10001);
    }

    function test_SetSdtDistributor() public useFork(forkId1) {
        assertTrue(address(curveStrategy.sdtDistributor()) != address(0x1), "0");

        curveStrategy.setSdtDistributor(address(0x1));

        assertEq(address(curveStrategy.sdtDistributor()), address(0x1), "1");
    }

    function test_SetCurveRewardToken() public useFork(forkId1) {
        assertTrue(address(curveStrategy.curveRewardToken()) != address(0x1), "0");

        curveStrategy.setCurveRewardToken(address(0x1));

        assertEq(address(curveStrategy.curveRewardToken()), address(0x1), "1");
    }

    function test_SetNewFeeDistributor() public useFork(forkId1) {
        assertTrue(address(curveStrategy.feeDistributor()) != address(0x1), "0");

        curveStrategy.setFeeDistributor(address(0x1));

        assertEq(address(curveStrategy.feeDistributor()), address(0x1), "1");
    }

    function test_SetVeCRVDifferenceThreshold() public useFork(forkId1) {
        uint256 before = optimizor.veCRVDifferenceThreshold();

        optimizor.setVeCRVDifferenceThreshold(1);

        assertNotEq(optimizor.veCRVDifferenceThreshold(), before, "0");
        assertEq(optimizor.veCRVDifferenceThreshold(), 1, "1");
    }

    function test_SetConvexDifferenceThreshold() public useFork(forkId1) {
        uint256 before = optimizor.convexDifferenceThreshold();

        optimizor.setConvexDifferenceThreshold(1);

        assertNotEq(optimizor.convexDifferenceThreshold(), before, "0");
        assertEq(optimizor.convexDifferenceThreshold(), 1, "1");
    }

    // --- Execute
    function test_Execute() public useFork(forkId1) {
        (bool success, bytes memory data) =
            curveStrategy.execute(address(optimizor), 0, abi.encodeWithSignature("CRV()"));

        assertTrue(success, "0");
        assertEq(abi.decode(data, (address)), address(CRV), "1");
    }

    // --- Locker Management
    function test_IncreaseAmount() public useFork(forkId1) {
        uint256 amount = 1000;
        deal(address(CRV), address(this), amount);

        CRV.transfer(LOCKER, amount);

        IVeCRV.LockedBalance memory balBefore = IVeCRV(VE_CRV).locked(LOCKER);

        curveStrategy.increaseAmount(amount);

        IVeCRV.LockedBalance memory balAfter = IVeCRV(VE_CRV).locked(LOCKER);

        assertGe(balAfter.amount, balBefore.amount, "0");
    }

    function test_ReleaseCRV() public useFork(forkId1) {
        skip(4 * 52 weeks);

        uint256 balBefore = CRV.balanceOf(LOCKER);

        curveStrategy.release();

        assertGt(CRV.balanceOf(LOCKER), balBefore, "0");
    }

    function test_SetGovernance_Locker() public useFork(forkId1) {
        vm.prank(ILocker(LOCKER).governance());
        ILocker(LOCKER).setGovernance(address(curveStrategy));

        address before = ILocker(LOCKER).governance();
        assertNotEq(before, address(0x123), "0");

        curveStrategy.setGovernance(address(0x123));

        assertEq(ILocker(LOCKER).governance(), address(0x123), "1");
    }

    function test_SetStrategy_Locker() public useFork(forkId1) {
        vm.prank(ILocker(LOCKER).governance());
        ILocker(LOCKER).setGovernance(address(curveStrategy));

        address before = ILocker(LOCKER).strategy();
        assertNotEq(before, address(0x123), "0");

        curveStrategy.setStrategy(address(0x123));

        assertEq(ILocker(LOCKER).strategy(), address(0x123), "1");
    }

    function test_IncreaseUnlockTime() public useFork(forkId1) {
        uint256 endBefore = IVeCRV(VE_CRV).locked(LOCKER).end;
        uint256 endAfter = endBefore + 7 days;

        skip(30 weeks); // To avoid being above the max lock time
        curveStrategy.increaseUnlockTime(endAfter);

        assertEq(IVeCRV(VE_CRV).locked(LOCKER).end, endAfter, "0");
    }

    //////////////////////////////////////////////////////
    /// --- FALLBACKS
    //////////////////////////////////////////////////////

    function test_RescueTokens() public useFork(forkId1) {
        deal(address(CRV), address(fallbackConvexCurve), 1000);
        assertEq(CRV.balanceOf(address(fallbackConvexCurve)), 1000, "0");
        fallbackConvexCurve.rescueERC20(address(CRV), address(this), 1000);
        assertEq(CRV.balanceOf(address(fallbackConvexCurve)), 0, "1");
    }

    function test_SetAllPidsOptimizedOnConvexCurve() public useFork(forkId3) {
        // Need to  be done before the following tx on mainnet
        // https://etherscan.io/tx/0x3d480ef9c77434b38e4b9881bd7cb7dd8f03ffaca62bae05edd38f44c6bde520

        address poolManager = 0xc461E1CE3795Ee30bA2EC59843d5fAe14d5782D5;
        address gaugeToAdd = 0xb0a6F55a758C8F035C067672e89903d76A5AbE9b;
        (bool success,) = poolManager.call(abi.encodeWithSignature("addPool(address)", gaugeToAdd));
        assertTrue(success, "0");

        uint256 lastPidCount = fallbackConvexCurve.lastPidsCount();
        fallbackConvexCurve.setAllPidsOptimized();

        assertEq(fallbackConvexCurve.lastPidsCount(), lastPidCount + 1, "0");
    }
}
