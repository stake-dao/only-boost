// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "test/BaseTest.t.sol";

contract CurveStrategyTest is BaseTest {
    using SafeTransferLib for ERC20;

    // Contracts
    Optimizor public optimizor;
    ConvexMapper public convexMapper;
    CurveStrategy public curveStrategy;

    // Interfaces
    ILocker public locker;
    IBoosterConvexFrax public boosterConvexFrax;
    IBoosterConvexCurve public boosterConvexCurve;
    IPoolRegistryConvexFrax public poolRegistryConvexFrax;

    // Variables

    //////////////////////////////////////////////////////
    /// --- SETUP --- ///
    //////////////////////////////////////////////////////
    function setUp() public {
        // Create Fork
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet"), 17242848));

        // Label addresses
        labelAddress();

        // Deploy Contracts
        curveStrategy = new CurveStrategy(Authority(address(0)));
        // End of deployment section
        optimizor = Optimizor(curveStrategy.optimizor());
        convexMapper = ConvexMapper(curveStrategy.convexMapper());
        boosterConvexFrax = IBoosterConvexFrax(curveStrategy.boosterConvexFrax());
        boosterConvexCurve = IBoosterConvexCurve(convexMapper.boosterConvexCurve());
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(convexMapper.poolRegistryConvexFrax());

        locker = ILocker(curveStrategy.LOCKER_STAKEDAO());

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(address(curveStrategy));

        // Add all gauges
        addAllGauge();

        // Label contracts
        labelContract();
    }

    // All the following test are  using a fork of mainnet
    /////////////////////////////////////////////////
    /// --- TESTS --- ///
    //////////////////////////////////////////////////////
    function test_Deployment() public {
        // === ASSERTIONS === //
        assertTrue(address(curveStrategy) != address(0));
        assertTrue(address(curveStrategy.optimizor()) != address(0));
        assertTrue(address(curveStrategy.convexMapper()) != address(0));

        assertEq(convexMapper.lastPidsCountConvexFrax(), poolRegistryConvexFrax.poolLength(), "1");
        assertEq(convexMapper.lastPidsCountConvexCurve(), boosterConvexCurve.poolLength(), "2");
    }

    function test_Deposit_AllOnStakeDAO() public {
        // LP amount to deposit
        uint256 amount = 10e18;
        // Check max to deposit following optimization
        uint256 maxToDeposit = optimizor.optimization(address(GAUGE_CRV3), false);
        // Check amount is less than max to deposit, to unsure full deposit on Stake DAO
        assert(maxToDeposit > amount);

        // Deal 3CRV to this contract
        deal(address(CRV3), address(this), amount);
        // Approve 3CRV to strategy
        CRV3.safeApprove(address(curveStrategy), amount);
        // Cache balance before
        uint256 balanceBefore = ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO));

        // Deposit 3CRV
        curveStrategy.deposit(address(CRV3), amount);

        // === ASSERTIONS === //
        // Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO)) - balanceBefore, amount, "1");
    }

    function test_Deposit_UsingConvexCurveFallback() public {
        // Check max to deposit following optimization
        uint256 maxToDeposit = optimizor.optimization(address(GAUGE_CRV3), false);

        uint256 partStakeDAO = maxToDeposit - ERC20(GAUGE_CRV3).balanceOf(LOCKER_STAKEDAO);
        uint256 partConvex = 5_000_000e18;
        assert(partConvex > 0 && partStakeDAO > 0);

        // LP amount to deposit is 2 times the max amount, to unsure testing fallback.
        uint256 amount = partStakeDAO + partConvex;

        // Deal 3CRV to this contract
        deal(address(CRV3), address(this), amount);
        // Approve 3CRV to strategy
        CRV3.safeApprove(address(curveStrategy), amount);
        // Cache balance before
        uint256 balanceBeforeStakeDAO = ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO));
        uint256 balanceBeforeConvex = ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_CONVEX));

        // Deposit 3CRV
        curveStrategy.deposit(address(CRV3), amount);

        // === ASSERTIONS === //
        // Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_STAKEDAO)) - balanceBeforeStakeDAO, partStakeDAO, "1");
        // Assertion 2: Check Gauge balance of Convex Liquid Locker
        assertEq(ERC20(GAUGE_CRV3).balanceOf(address(LOCKER_CONVEX)) - balanceBeforeConvex, partConvex, "2");
    }

    function test_Deposit_UsingConvexFraxFallBack() public {
        // Check max to deposit following optimization
        uint256 maxToDeposit = optimizor.optimization(address(GAUGE_ALUSD_FRAXBP), true);

        uint256 partStakeDAO = maxToDeposit - ERC20(GAUGE_ALUSD_FRAXBP).balanceOf(LOCKER_STAKEDAO);
        uint256 partConvex = 5_000_000e18;
        assert(partConvex > 0 && partStakeDAO > 0);

        // LP amount to deposit is stakeDAO + convex
        uint256 amount = partStakeDAO + partConvex;

        // Deal ALUSD_FRAXBP to this contract
        deal(address(ALUSD_FRAXBP), address(this), amount);
        // Sometimes, deal cheatcode doesn't work, so we check balance
        assert(ERC20(ALUSD_FRAXBP).balanceOf(address(this)) == amount);

        // Approve ALUSD_FRAXBP to strategy
        ALUSD_FRAXBP.safeApprove(address(curveStrategy), amount);
        // Cache balance before
        uint256 balanceBeforeStakeDAO = ERC20(GAUGE_ALUSD_FRAXBP).balanceOf(address(LOCKER_STAKEDAO));

        // Deposit ALUSD_FRAXBP
        curveStrategy.deposit(address(ALUSD_FRAXBP), amount);

        // Get all needed infos for following assertions
        ConvexMapper.PidsInfo memory pid = convexMapper.getPidsFrax(address(ALUSD_FRAXBP));
        address personalVault = poolRegistryConvexFrax.vaultMap(pid.pid, address(curveStrategy));
        (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pid.pid);
        IFraxUnifiedFarm.LockedStake memory infos = IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[0];

        // === ASSERTIONS === //
        //Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(
            ERC20(GAUGE_ALUSD_FRAXBP).balanceOf(address(LOCKER_STAKEDAO)) - balanceBeforeStakeDAO, partStakeDAO, "1"
        );
        // Assertion 2: Check personal vault created
        assertTrue(poolRegistryConvexFrax.vaultMap(pid.pid, address(curveStrategy)) != address(0), "2");
        // Assertion 3: Check value for personal vault, such as liquidity, kek_id, timestamps, lock_multiplier
        assertEq(infos.liquidity, partConvex, "3");
        assertEq(infos.kek_id, curveStrategy.kekIds(curveStrategy.vaults(pid.pid)), "4"); // kek_id is the same as vault
        assertEq(infos.start_timestamp, block.timestamp, "5");
        assertEq(infos.ending_timestamp, block.timestamp + curveStrategy.lockingIntervalSec(), "6");
        assertGt(infos.lock_multiplier, 0, "7");
    }

    function test_Deposit_UsingConvexFraxSecondDeposit() public {
        // Deposit first time
        test_Deposit_UsingConvexFraxFallBack();

        // Cache timestamp before
        uint256 timestampBefore = block.timestamp;
        // Set timejump interval
        uint256 timejumpInterval = 10 days;
        // Timejump
        skip(timejumpInterval);

        // Check max to deposit following optimization
        uint256 maxToDeposit = optimizor.optimization(address(GAUGE_ALUSD_FRAXBP), true);

        uint256 partStakeDAO = maxToDeposit - ERC20(GAUGE_ALUSD_FRAXBP).balanceOf(LOCKER_STAKEDAO);
        uint256 partConvex = 5_000_000e18;

        // LP amount to deposit is stakeDAO + convex
        uint256 amount = partStakeDAO + partConvex;

        // Deal ALUSD_FRAXBP to this contract
        deal(address(ALUSD_FRAXBP), address(this), amount);
        // Sometimes, deal cheatcode doesn't work, so we check balance
        assert(ERC20(ALUSD_FRAXBP).balanceOf(address(this)) == amount);

        // Approve ALUSD_FRAXBP to strategy
        ALUSD_FRAXBP.safeApprove(address(curveStrategy), amount);

        // Deposit ALUSD_FRAXBP
        curveStrategy.deposit(address(ALUSD_FRAXBP), amount);

        // Get all needed infos for following assertions
        ConvexMapper.PidsInfo memory pid = convexMapper.getPidsFrax(address(ALUSD_FRAXBP));
        address personalVault = poolRegistryConvexFrax.vaultMap(pid.pid, address(curveStrategy));
        (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pid.pid);
        IFraxUnifiedFarm.LockedStake memory infos = IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[0];

        // === ASSERTIONS === //
        //Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertGt(ERC20(GAUGE_ALUSD_FRAXBP).balanceOf(address(LOCKER_STAKEDAO)), partStakeDAO, "1");
        // Assertion 2: Check value for personal vault, such as liquidity, kek_id, timestamps, lock_multiplier
        assertEq(IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault), 1, "2");
        assertEq(infos.liquidity, partConvex * 2, "3");
        assertEq(infos.kek_id, curveStrategy.kekIds(curveStrategy.vaults(pid.pid)), "4"); // kek_id is the same as vault
        assertEq(infos.start_timestamp, timestampBefore, "5");
        assertEq(infos.ending_timestamp, timestampBefore + curveStrategy.lockingIntervalSec(), "6");
        assertGt(infos.lock_multiplier, 0, "7");
        // Note: Locking additional liquidity doesn't change ending-timestamp
    }

    //////////////////////////////////////////////////////
    /// --- HELPER FUNCTIONS --- ///
    //////////////////////////////////////////////////////
    function addAllGauge() internal {
        curveStrategy.setGauge(address(CRV3), GAUGE_CRV3);
        curveStrategy.setGauge(address(ALUSD_FRAXBP), GAUGE_ALUSD_FRAXBP);
    }

    function labelContract() internal {
        vm.label(address(curveStrategy), "CurveStrategy");
        vm.label(address(curveStrategy.optimizor()), "Optimizor");
        vm.label(address(curveStrategy.convexMapper()), "ConvexMapper");
    }
}
