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

    /*
    function test_Deposit_OnConvexCurveAndFrax() public useFork(forkId2) {
        // This situation could rarely happen, but it's possible
        // When a pool is added on ConvexCurve, user can deposit on curveStategy for this pool
        // And some times after, the pool is added on ConvexFrax
        // so this should have some tokens on both fallbacks,
        // let's test it using COIL_FRAXBP, added on ConvexFrax at block 17326004 on this tx :
        // https://etherscan.io/tx/0xbcc25272dad48329ed963991f156b929b28ee171e4ad157e2d9b749f3d85eb7b
        

        // First deposit into StakeDAO Locker and Convex Curve 
                (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(CRV3, MAX, 1);
                _deposit
    }*/

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
        assertEq(optimizor.convexFraxPaused(), false, "0");
        assertEq(optimizor.convexFraxPausedTimestamp(), 0, "1");

        // Pause ConvexFrax deposit
        optimizor.pauseConvexFraxDeposit();

        assertEq(optimizor.convexFraxPaused(), true, "2");
        assertEq(optimizor.convexFraxPausedTimestamp(), block.timestamp, "3");
    }
}
