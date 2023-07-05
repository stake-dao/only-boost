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
        // Deployment contracts
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        curveStrategy = new CurveStrategy(address(this), rolesAuthority);
        fallbackConvexCurve = new FallbackConvexCurve(address(this), rolesAuthority, address(curveStrategy));
        fallbackConvexFrax = new FallbackConvexFrax(address(this), rolesAuthority, address(curveStrategy));
        optimizor =
        new Optimizor(address(this), rolesAuthority, address(curveStrategy), address(fallbackConvexCurve), address(fallbackConvexFrax));
        liquidityGaugeMockCRV3 = new LiquidityGaugeMock(CRV3);
        liquidityGaugeMockCNC_ETH = new LiquidityGaugeMock(CNC_ETH);
        liquidityGaugeMockSTETH_ETH = new LiquidityGaugeMock(STETH_ETH);
        liquidityGaugeMockALUSD_FRAXBP = new LiquidityGaugeMock(ALUSD_FRAXBP);
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
        // Mock call on fallback that return false for `isActive`
        vm.mockCall(
            address(fallbackConvexCurve), abi.encodeWithSignature("isActive(address)", address(CRV3)), abi.encode(false)
        );

        _depositTest(CRV3, 5_000_000e18, 0, 0);
    }

    function test_Deposit_AllOnStakeDAOBecauseNoOptimizor() public useFork(forkId1) {
        curveStrategy.setOptimizor(address(0));

        // Test deposit not metapool
        _depositTest(CRV3, 5_000_000e18, 0, 0);

        // Test deposit metapool
        _depositTest(ALUSD_FRAXBP, 5_000_000e18, 0, 0);
    }

    function test_Deposit_UsingConvexCurveFallback() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);

        _depositTest(CRV3, partStakeDAO, partConvex, 0);
    }

    function test_Deposit_UsingConvexFraxFallBack() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);

        _depositTest(ALUSD_FRAXBP, partStakeDAO, partConvex, 0);

        BaseFallback.PidsInfo memory pid = fallbackConvexFrax.getPid(address(ALUSD_FRAXBP));
        assertEq(fallbackConvexFrax.balanceOfLocked(pid.pid), partConvex);

        skip(fallbackConvexFrax.lockingIntervalSec());
        assertEq(fallbackConvexFrax.balanceOfLocked(pid.pid), 0);
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
        fallbackConvexFrax.setAllPidsOptimized();

        // Second deposit into StakeDAO Locker and Convex Frax
        (uint256 partStakeDAOAfter, uint256 partConvexAfter) = _calculDepositAmount(COIL_FRAXBP, MAX, 1);
        _depositTest(COIL_FRAXBP, partStakeDAOAfter, partConvexAfter, 0);

        skip(1 weeks);
        // Check that we have tokens on both fallbacks
        assertEq(fallbackConvexFrax.balanceOf(address(COIL_FRAXBP)), partConvexAfter, "1");
        assertEq(fallbackConvexCurve.balanceOf(address(COIL_FRAXBP)), partConvexBefore, "2");
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

    function test_Withdraw_AllFromStakeDAOBecauseNoOptimizor() public useFork(forkId1) {
        curveStrategy.setOptimizor(address(0));

        _deposit(CRV3, 5_000_000e18, 0, 0);

        _withdrawTest(CRV3, 5_000_000e18, 0, 0);
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
        fallbackConvexFrax.setAllPidsOptimized();

        // Second deposit into StakeDAO Locker and Convex Frax
        (uint256 partStakeDAOAfter, uint256 partConvexAfter) = _calculDepositAmount(COIL_FRAXBP, MAX, 1);
        _depositTest(COIL_FRAXBP, partStakeDAOAfter, partConvexAfter, 0);

        // Use the total amount owned by the locker to be sure to withdraw all
        uint256 balanceOfStakeDAO = ERC20(gauges[address(COIL_FRAXBP)]).balanceOf(LOCKER);

        // === WITHDRAW PROCESS === //
        _withdrawTest(
            COIL_FRAXBP,
            partStakeDAOAfter + partStakeDAOBefore + balanceOfStakeDAO,
            partConvexAfter + partConvexBefore,
            fallbackConvexFrax.lockingIntervalSec()
        );
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

        address[] memory extraTokens = new address[](1);
        extraTokens[0] = address(LDO);
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

    function test_Claim_ConvexFraxRewardsWithoutFees() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);

        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex, 0);

        _claimLiquidLockerTest(ALUSD_FRAXBP, 1 weeks, fallbackConvexFrax.getRewardsTokens(address(ALUSD_FRAXBP)), ALICE);
    }

    function test_Claim_ConvexFraxRewardsWithFees() public useFork(forkId1) {
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);

        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex, 0);

        _claimLiquidLockerTest(ALUSD_FRAXBP, 1 weeks, fallbackConvexFrax.getRewardsTokens(address(ALUSD_FRAXBP)), ALICE);
    }

    function test_Claim_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
        curveStrategy.claim(address(CVX));
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
        curveStrategy.claim(address(CRV3));
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
        curveStrategy.claim(address(CRV3));
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
        curveStrategy.claim(address(STETH_ETH));
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
        curveStrategy.claim3Crv(true);

        // === ASSERTIONS === //
        //Assertion 1: Check test accumulator received token
        assertGt(CRV3.balanceOf(address(curveStrategy.accumulator())), balanceBeforeAC, "1");
    }

    function test_Claim3CRV_RevertWhen_AMOUNT_NULL() public useFork(forkId1) {
        // Because no time has been skipped, there is no rewards to claim
        vm.expectRevert(CurveStrategy.AMOUNT_NULL.selector);
        curveStrategy.claim3Crv(false);
    }

    function test_Claim3CRV_RevertWhen_CLAIM_FAILED() public useFork(forkId1) {
        bytes memory data = abi.encodeWithSignature("claim()");

        // Mock call to StakeDAO Locker
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", curveStrategy.CRV_FEE_D(), 0, data),
            abi.encode(false, 0x0)
        );

        // Because no time has been skipped, there is no rewards to claim
        vm.expectRevert(CurveStrategy.CLAIM_FAILED.selector);
        curveStrategy.claim3Crv(true);
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
        curveStrategy.claim3Crv(true);
    }

    // --- Migrate LP
    function test_MigrateLP() public useFork(forkId1) {
        assertEq(CRV3.balanceOf(address(this)), 0, "0");

        uint256 balanceGaugeBefore = ERC20(gauges[address(CRV3)]).balanceOf(LOCKER);
        // === DEPOSIT PROCESS === //
        _deposit(CRV3, 100, 0);

        // === MIGRATE LP PROCESS === //
        curveStrategy.migrateLP(address(CRV3));

        // === ASSERTIONS === //
        assertEq(CRV3.balanceOf(address(this)), balanceGaugeBefore + 100, "1");
    }

    function test_MigrateLP_RevertWhen_ADDRESS_NULL() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.ADDRESS_NULL.selector);
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
        curveStrategy.migrateLP(address(CRV3));
    }

    function test_MigrateLP_RevertWhen_CALL_FAILED() public useFork(forkId1) {
        // Get balance of the gauge
        uint256 balanceGauge = ERC20(gauges[address(CRV3)]).balanceOf(address(LOCKER));
        // Get balance of the locker
        uint256 balanceLocker = CRV3.balanceOf(address(LOCKER));

        // data used on executed function by the LL
        bytes memory data =
            abi.encodeWithSignature("transfer(address,uint256)", address(this), balanceGauge + balanceLocker);

        // Mock the call to force the fail on transfer LP from the LL
        vm.mockCall(
            address(LOCKER),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(CRV3), 0, data),
            abi.encode(false, 0x0)
        );

        // Assert Revert
        vm.expectRevert(CurveStrategy.CALL_FAILED.selector);
        curveStrategy.migrateLP(address(CRV3));
    }

    // --- Pause ConvexFrax
    function test_PauseConvexFraxDeposit() public useFork(forkId1) {
        assertEq(optimizor.isConvexFraxPaused(), false, "0");
        assertEq(optimizor.convexFraxPausedTimestamp(), 0, "1");

        // Pause ConvexFrax deposit
        optimizor.pauseConvexFraxDeposit();

        assertEq(optimizor.isConvexFraxPaused(), true, "2");
        assertEq(optimizor.convexFraxPausedTimestamp(), block.timestamp, "3");
    }

    function test_PauseConvexFraxDeposit_RevertWhen_ALREADY_PAUSED() public useFork(forkId1) {
        optimizor.pauseConvexFraxDeposit();

        vm.expectRevert(Optimizor.ALREADY_PAUSED.selector);
        optimizor.pauseConvexFraxDeposit();
    }

    // --- Kill ConvexFrax
    function test_KillConvexFrax() public useFork(forkId1) {
        // === DEPOSIT PROCESS === //
        (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 10_000_000e18);
        _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex);

        // Pause ConvexFrax deposit
        optimizor.pauseConvexFraxDeposit();

        // Wait 1 week
        skip(1 weeks);

        // Authorize Optimizor to withdraw from convexFrax and deposit into strategy
        _killConvexFraxAuth();

        assertGt(fallbackConvexFrax.balanceOf(address(ALUSD_FRAXBP)), 0, "0");

        uint256 balanceBeforeConvexCurve = fallbackConvexCurve.balanceOf(address(ALUSD_FRAXBP));
        uint256 balanceBeforeStakeDAO = ERC20(gauges[address(ALUSD_FRAXBP)]).balanceOf(address(LOCKER));

        // === KILL PROCESS === //
        optimizor.killConvexFrax();

        // === ASSERTIONS === //
        //Assertion 1: Check ConvexFrax balance
        assertEq(fallbackConvexFrax.balanceOf(address(ALUSD_FRAXBP)), 0, "1");
        //Assertion 2: Check ConvexCurve balance
        assertGt(fallbackConvexCurve.balanceOf(address(ALUSD_FRAXBP)), balanceBeforeConvexCurve, "2");
        //Assertion 3: Check StakeDAO balance
        assertGt(ERC20(gauges[address(ALUSD_FRAXBP)]).balanceOf(address(LOCKER)), balanceBeforeStakeDAO, "3");
    }

    function test_KillConvexFrax_RevertWhen_NOT_PAUSED() public useFork(forkId1) {
        vm.expectRevert(Optimizor.NOT_PAUSED.selector);
        optimizor.killConvexFrax();
    }

    function test_KillConvexFrax_RevertWhen_TOO_SOON() public useFork(forkId1) {
        optimizor.pauseConvexFraxDeposit();

        vm.expectRevert(Optimizor.TOO_SOON.selector);
        optimizor.killConvexFrax();
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

        // Get veCRVStakeDAO balance
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);
        // Calculate optimization
        uint256 calculatedOpti = optimizor.optimalAmount(address(gauges[address(ALUSD_FRAXBP)]), veCRVStakeDAO, true);

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
        // Get veCRVStakeDAO balance
        veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);
        // Calculate optimization
        calculatedOpti = optimizor.optimalAmount(address(gauges[address(CRV3)]), veCRVStakeDAO, false);

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

    function test_OptimizedDepositReturnedValueAfterCRVLockMetapool() public useFork(forkId1) {
        _optimizedDepositReturnedValueAfterCRVLock(ALUSD_FRAXBP);
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
        curveStrategy.manageFee(CurveStrategy.MANAGEFEE.PERFFEE, address(0), 10);
    }

    function test_RevertWhen_FeeTooHigh_ManageFee() public useFork(forkId1) {
        vm.expectRevert(CurveStrategy.FEE_TOO_HIGH.selector);
        curveStrategy.manageFee(CurveStrategy.MANAGEFEE.PERFFEE, gauges[address(ALUSD_FRAXBP)], 10001);
    }

    function test_SetCurveStrategy() public useFork(forkId1) {
        address before = address(fallbackConvexCurve.curveStrategy());

        fallbackConvexCurve.setCurveStrategy(address(0x1));

        assertNotEq(address(fallbackConvexCurve.curveStrategy()), before, "0");
        assertEq(address(fallbackConvexCurve.curveStrategy()), address(0x1), "1");

        before = address(optimizor.curveStrategy());

        optimizor.setCurveStrategy(address(0x1));
        assertNotEq(address(optimizor.curveStrategy()), before, "2");
        assertEq(address(optimizor.curveStrategy()), address(0x1), "3");
    }

    function test_SetSdtDistributor() public useFork(forkId1) {
        assertTrue(address(curveStrategy.sdtDistributor()) != address(0x1), "0");

        curveStrategy.setSdtDistributor(address(0x1));

        assertEq(address(curveStrategy.sdtDistributor()), address(0x1), "1");
    }

    function test_SetLockingIntervalSec() public useFork(forkId1) {
        uint256 before = fallbackConvexFrax.lockingIntervalSec();

        fallbackConvexFrax.setLockingIntervalSec(1);

        assertNotEq(fallbackConvexFrax.lockingIntervalSec(), before, "0");
        assertEq(fallbackConvexFrax.lockingIntervalSec(), 1, "1");
    }

    function test_toggleClaimAll() public useFork(forkId1) {
        bool before = curveStrategy.claimAll();

        curveStrategy.toggleClaimAll();

        assertEq(curveStrategy.claimAll(), !before, "1");
    }

    function test_ToggleClaimOnWithdraw() public useFork(forkId1) {
        bool before = fallbackConvexCurve.claimOnWithdraw();

        fallbackConvexCurve.toggleClaimOnWithdraw();

        assertEq(fallbackConvexCurve.claimOnWithdraw(), !before, "1");
    }

    function test_SetExtraConvexFraxBoost() public useFork(forkId1) {
        uint256 before = optimizor.extraConvexFraxBoost();

        optimizor.setExtraConvexFraxBoost(1);

        assertNotEq(optimizor.extraConvexFraxBoost(), before, "0");
        assertEq(optimizor.extraConvexFraxBoost(), 1, "1");
    }

    function test_SetVeCRVDifferenceThreshold() public useFork(forkId1) {
        uint256 before = optimizor.veCRVDifferenceThreshold();

        optimizor.setVeCRVDifferenceThreshold(1);

        assertNotEq(optimizor.veCRVDifferenceThreshold(), before, "0");
        assertEq(optimizor.veCRVDifferenceThreshold(), 1, "1");
    }

    // --- Execute
    function test_Execute() public useFork(forkId1) {
        (bool success, bytes memory data) =
            curveStrategy.execute(address(optimizor), 0, abi.encodeWithSignature("CRV()"));

        assertTrue(success, "0");
        assertEq(abi.decode(data, (address)), address(CRV), "1");
    }

    //////////////////////////////////////////////////////
    /// --- FALLBACKS
    //////////////////////////////////////////////////////

    function test_RescueTokens() public useFork(forkId1) {
        deal(address(CRV), address(fallbackConvexFrax), 1000);
        assertEq(CRV.balanceOf(address(fallbackConvexFrax)), 1000, "0");
        fallbackConvexFrax.rescueERC20(address(CRV), address(this), 1000);
        assertEq(CRV.balanceOf(address(fallbackConvexFrax)), 0, "1");
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

    function test_SetAllPidsOptimizedOnConvexFrax() public useFork(forkId2) {
        _addCOIL_FRAXBPOnConvexFrax();

        uint256 lastPidCount = fallbackConvexFrax.lastPidsCount();
        fallbackConvexFrax.setAllPidsOptimized();

        assertEq(fallbackConvexFrax.lastPidsCount(), lastPidCount + 1, "0");
    }
}
